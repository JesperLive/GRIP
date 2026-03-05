-- GRIP: Utils
-- Shared helpers: template engine, chat compat, whisper echo suppression, pattern matching.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, pcall, wipe, strsplit = pairs, pcall, wipe, strsplit
local gsub, sub, find, match = string.gsub, string.sub, string.find, string.match
local tremove, tsort = table.remove, table.sort
local floor = math.floor
local time = time

-- WoW API
local GetTime = GetTime
local IsInGuild, GetGuildInfo = IsInGuild, GetGuildInfo
local InCombatLockdown = InCombatLockdown
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
local C_Club = C_Club
local C_ClubFinder = C_ClubFinder
local C_ChatInfo = C_ChatInfo
local SendChatMessage = SendChatMessage

local state = GRIP.state

-- ----------------------------
-- Optional: hide outgoing whisper echoes in chat ("To X: ...")
-- This does NOT affect event processing (CHAT_MSG_WHISPER_INFORM still fires).
-- Enable with: GRIPDB_CHAR.config.suppressWhisperEcho = true
-- ----------------------------
local function EnsureRecentWhisperBuf()
  state._gripRecentWhispers = state._gripRecentWhispers or {}
  return state._gripRecentWhispers
end

local function CleanupRecentWhispers(buf, now)
  now = now or GetTime()
  for i = #buf, 1, -1 do
    local e = buf[i]
    if (not e) or (now - (e.t or 0) > 15) then
      table.remove(buf, i)
    end
  end
end

local function AddRecentWhisper(msg, target)
  local buf = EnsureRecentWhisperBuf()
  local now = GetTime()
  CleanupRecentWhispers(buf, now)

  buf[#buf + 1] = {
    t = now,
    msg = tostring(msg or ""),
    target = tostring(target or ""),
  }
end

local function RecentWhisperMatches(msg, author)
  local buf = EnsureRecentWhisperBuf()
  local now = GetTime()
  CleanupRecentWhispers(buf, now)
  author = tostring(author or "")
  for i = #buf, 1, -1 do
    local e = buf[i]
    if e and (now - (e.t or 0)) < 5 then
      if author == e.target or author:match("^[^-]+") == tostring(e.target):match("^[^-]+") then
        table.remove(buf, i)  -- consume the match
        return true
      end
    end
  end
  return false
end

local function WhisperInformFilter(_, event, msg, author, ...)
  if event ~= "CHAT_MSG_WHISPER_INFORM" then return false end
  if not (_G.GRIPDB_CHAR and GRIPDB_CHAR.config and GRIPDB_CHAR.config.suppressWhisperEcho) then
    return false
  end

  if RecentWhisperMatches(msg, author) then
    return true -- swallow this chat line
  end
  return false
end

function GRIP:EnsureWhisperEchoFilter()
  if state._gripWhisperEchoFilterInstalled then return end
  if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", WhisperInformFilter)
    state._gripWhisperEchoFilterInstalled = true
  end
end

function GRIP:Now()
  return time()
end

function GRIP:GetGuildName()
  state._gripLastGuildName = state._gripLastGuildName or ""

  -- If the client can tell us we're not in a guild, invalidate cache.
  if IsInGuild and not IsInGuild() then
    state._gripLastGuildName = ""
    return ""
  end

  -- Return cache immediately if we have one (GetGuildInfo returns nil during early login).
  if state._gripLastGuildName ~= "" then
    return state._gripLastGuildName
  end

  -- Primary source: GetGuildInfo("player") — the only guild-name API in 12.0.1.
  -- Returns nil before PLAYER_GUILD_UPDATE fires; the event handler will warm this cache.
  if GetGuildInfo then
    local g = GetGuildInfo("player")
    if type(g) == "string" and g ~= "" then
      state._gripLastGuildName = g
      return g
    end
  end

  return ""
end

function GRIP:Clamp(n, lo, hi)
  n = tonumber(n) or 0
  lo = tonumber(lo) or n
  hi = tonumber(hi) or n
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function GRIP:SafeTruncateChat(msg)
  msg = tostring(msg or "")
  if #msg > 250 then
    msg = msg:sub(1, 250)
  end
  msg = msg:gsub("[\r\n]+", " ")
  return msg
end

-- Try to load the Guild Finder / Club Finder UI module if needed.
-- This is required for GetClubFinderLink / ClubFinderGetCurrentClubListingInfo on some clients.
function GRIP:_TryLoadClubFinder()
  if ClubFinderGetCurrentClubListingInfo and GetClubFinderLink then
    return true
  end

  if InCombatLockdown and InCombatLockdown() then
    return false
  end

  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if not (isLoaded and load) then
    return false
  end

  if not isLoaded("Blizzard_ClubFinder") then
    pcall(load, "Blizzard_ClubFinder")
  end

  -- Prime the C_ClubFinder data cache (async — fires CLUB_FINDER_RECRUITMENT_POST_RETURNED)
  if C_ClubFinder and C_ClubFinder.RequestPostingInformationFromClubId then
    local ok, cid = pcall(C_Club.GetGuildClubId)
    if ok and cid then
      pcall(C_ClubFinder.RequestPostingInformationFromClubId, cid)
    end
  end

  return (ClubFinderGetCurrentClubListingInfo ~= nil) and (GetClubFinderLink ~= nil)
end

-- Store a successful guild link in both runtime and SV caches.
local function CacheGuildLink(link, guid, guildName)
  state._gripGuildLinkCache = link
  state._gripGuildLinkCacheAt = GetTime()
  state._gripGuildLinkTraced = nil

  if _G.GRIPDB_CHAR then
    GRIPDB_CHAR._guildLinkCache = {
      link = link,
      guid = guid,
      name = guildName,
      at   = time(),
    }
  end
end

-- Clickable Guild Finder link (if available)
-- Multi-path resolution: runtime cache → SV cache → C_ClubFinder API → ClubListingInfo → SV GUID → async request.
function GRIP:GetGuildFinderLink()
  -- If we're not in a guild, invalidate SV cache and bail.
  if IsInGuild and not IsInGuild() then
    if _G.GRIPDB_CHAR then GRIPDB_CHAR._guildLinkCache = nil end
    return ""
  end

  -- Path 0: Runtime cache (5 min TTL)
  local now = GetTime()
  if state._gripGuildLinkCache and state._gripGuildLinkCacheAt then
    if (now - state._gripGuildLinkCacheAt) < 300 then
      return state._gripGuildLinkCache
    end
  end

  -- Path 0b: SV cache (10 min TTL, survives /reload)
  if _G.GRIPDB_CHAR and GRIPDB_CHAR._guildLinkCache then
    local sv = GRIPDB_CHAR._guildLinkCache
    if sv.link and sv.at and (time() - sv.at) < 600 then
      -- Promote to runtime cache
      state._gripGuildLinkCache = sv.link
      state._gripGuildLinkCacheAt = now
      if self:IsDebugEnabled(3) then
        self:Trace("GetGuildFinderLink: resolved from SV cache")
      end
      return sv.link
    end
  end

  if not C_Club or not C_Club.GetGuildClubId then
    return ""
  end

  local ok, clubId = pcall(C_Club.GetGuildClubId)
  if not ok or not clubId then
    return ""
  end

  -- Ensure Blizzard_ClubFinder addon is loaded (needed for GetClubFinderLink global)
  if not GetClubFinderLink then
    self:_TryLoadClubFinder()
  end

  local guildName = self:GetGuildName()

  -- Path 1: C_ClubFinder.GetRecruitingClubInfoFromClubID (no UI dependency)
  if C_ClubFinder and C_ClubFinder.GetRecruitingClubInfoFromClubID then
    local ok1, info = pcall(C_ClubFinder.GetRecruitingClubInfoFromClubID, clubId)
    if ok1 and info and info.clubFinderGUID then
      if self:IsDebugEnabled(3) then
        self:Trace("GetGuildFinderLink: Path 1 hit (C_ClubFinder), guid=", info.clubFinderGUID)
      end
      if GetClubFinderLink then
        local ok2, link = pcall(GetClubFinderLink, info.clubFinderGUID, info.name or guildName)
        if ok2 and type(link) == "string" and link ~= "" then
          CacheGuildLink(link, info.clubFinderGUID, info.name or guildName)
          return link
        end
      end
    end
  end

  -- Path 2: ClubFinderGetCurrentClubListingInfo (requires Communities frame opened)
  if ClubFinderGetCurrentClubListingInfo and GetClubFinderLink then
    local ok1, listing = pcall(ClubFinderGetCurrentClubListingInfo, clubId)
    if ok1 and listing and listing.clubFinderGUID and listing.name then
      if self:IsDebugEnabled(3) then
        self:Trace("GetGuildFinderLink: Path 2 hit (ClubListingInfo)")
      end
      local ok2, link = pcall(GetClubFinderLink, listing.clubFinderGUID, listing.name)
      if ok2 and type(link) == "string" and link ~= "" then
        CacheGuildLink(link, listing.clubFinderGUID, listing.name)
        return link
      end
    end
  end

  -- Path 3: Reconstruct from SV-cached GUID (if we have one but it was expired above)
  if _G.GRIPDB_CHAR and GRIPDB_CHAR._guildLinkCache and GRIPDB_CHAR._guildLinkCache.guid and GetClubFinderLink then
    local sv = GRIPDB_CHAR._guildLinkCache
    if self:IsDebugEnabled(3) then
      self:Trace("GetGuildFinderLink: Path 3 trying SV GUID reconstruction")
    end
    local ok1, link = pcall(GetClubFinderLink, sv.guid, sv.name or guildName)
    if ok1 and type(link) == "string" and link ~= "" then
      CacheGuildLink(link, sv.guid, sv.name or guildName)
      return link
    end
  end

  -- Path 4: Async request (prime the pump for next call)
  if C_ClubFinder and C_ClubFinder.RequestPostingInformationFromClubId then
    pcall(C_ClubFinder.RequestPostingInformationFromClubId, clubId)
    if self:IsDebugEnabled(3) then
      self:Trace("GetGuildFinderLink: Path 4 — requested posting data (async)")
    end
  end

  -- Log once per session if all paths failed
  if self:IsDebugEnabled(3) and not state._gripGuildLinkTraced then
    state._gripGuildLinkTraced = true
    self:Trace("GetGuildFinderLink: all paths returned nil (listing may not be published or cached yet)")
  end

  return ""
end

function GRIP:ApplyTemplate(tpl, targetFullName)
  tpl = tostring(tpl or "")

  local shortName = ""
  if targetFullName and targetFullName ~= "" then
    shortName = tostring(targetFullName):match("^[^-]+") or tostring(targetFullName)
  end

  local safeShort = shortName:gsub("%%", "%%%%")
  tpl = tpl:gsub("{player}", safeShort)
  tpl = tpl:gsub("{name}", safeShort)

  -- Handle {guildlink} BEFORE {guild} — {guild} is a substring of {guildlink} and gsub would mangle it.
  if tpl:find("{guildlink}", 1, true) then
    local guildName = self:GetGuildName()
    local inGuild = (guildName and guildName ~= "")

    -- Prefer clickable ClubFinder link only if actually in a guild; otherwise don't poke ClubFinder APIs.
    local link = ""
    if inGuild then
      link = self:GetGuildFinderLink() or ""
    end

    -- Guaranteed fallback (still useful even if listing isn't published/cached yet).
    if self:IsBlank(link) then
      if inGuild then
        link = guildName
        -- P-1: One-time per-session notice about guild link fallback
        if not state._gripGuildLinkFallbackNotified then
          state._gripGuildLinkFallbackNotified = true
          self:Print("Note: {guildlink} couldn't resolve a clickable Guild Finder link — using guild name instead.")
          self:Print("To fix: Open your Communities window (J) once per session, or ensure your guild has an active Guild Finder listing.")
          self:Print("Use /grip link for diagnostics.")
        end
      else
        link = "your guild"
      end
    end

    -- Replace tokens before truncation decisions (guildlink first, then guild).
    tpl = tpl:gsub("{guildlink}", (link:gsub("%%", "%%%%")))
    tpl = tpl:gsub("{guild}", (guildName:gsub("%%", "%%%%")))

    -- Reserve tail space for the link so long messages don't drop it.
    -- Strategy:
    --   - Ensure final output <= 250 chars (like SafeTruncateChat).
    --   - If needed, truncate from the non-link portions, keeping the last occurrence of link intact.
    tpl = tpl:gsub("[\r\n]+", " ")

    local MAX = 250
    if #tpl > MAX then
      local linkPos = tpl:find(link, 1, true)
      local lastPos
      while linkPos do
        lastPos = linkPos
        linkPos = tpl:find(link, (linkPos or 1) + 1, true)
      end

      if lastPos then
        local tailStart = lastPos
        local tail = tpl:sub(tailStart)
        -- If the tail alone is too big, hard-truncate it (should be rare; link might be huge).
        if #tail > MAX then
          tpl = tail:sub(1, MAX)
        else
          local headBudget = MAX - #tail
          local head = tpl:sub(1, tailStart - 1)
          if #head > headBudget then
            head = head:sub(1, headBudget)
          end
          tpl = head .. tail
        end
      else
        tpl = tpl:sub(1, MAX)
      end
    end

    -- Final sanitize (just in case)
    return tpl
  end

  -- No {guildlink} — just replace {guild} and truncate.
  tpl = tpl:gsub("{guild}", (self:GetGuildName():gsub("%%", "%%%%")))
  return self:SafeTruncateChat(tpl)
end

function GRIP:Count(tbl)
  if type(tbl) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(tbl) do n = n + 1 end
  return n
end

-- ── Shared utility helpers (centralized from per-file locals) ──────────

function GRIP:GetCfg()
  return (_G.GRIPDB_CHAR and GRIPDB_CHAR.config) or nil
end

function GRIP:GetPotential()
  return (_G.GRIPDB_CHAR and GRIPDB_CHAR.potential) or nil
end

function GRIP:IsBlank(s)
  if type(s) ~= "string" then return true end
  return s:gsub("%s+", "") == ""
end

function GRIP:Trim(s)
  if type(s) ~= "string" then return "" end
  return s:match("^%s*(.-)%s*$") or ""
end

function GRIP:SanitizeOneLine(s)
  s = tostring(s or "")
  s = s:gsub("[\r\n]+", " ")
  return s
end

function GRIP:SecondsLeft(untilT)
  local now = GetTime()
  local left = (untilT or 0) - now
  if left < 0 then left = 0 end
  return left
end

function GRIP:ResolvePotentialName(nameMaybe)
  if not nameMaybe or nameMaybe == "" then return nil end
  local pot = self:GetPotential()
  if not pot then return nil end
  if pot[nameMaybe] then return nameMaybe end
  local short = tostring(nameMaybe):match("^[^%-]+")
  if not short then return nil end
  local found
  for name in pairs(pot) do
    if name:match("^[^%-]+") == short then
      if found then return nil end
      found = name
    end
  end
  return found
end

function GRIP:BuildNameKeyVariants(fullName)
  fullName = self:Trim(fullName)
  if fullName == "" then return {} end
  local out = {}
  local function add(k)
    k = GRIP:Trim(k)
    if k == "" then return end
    out[#out + 1] = k
  end
  add(fullName)
  local base, realm = fullName:match("^([^%-]+)%-(.+)$")
  if base and realm then
    add(base)
  else
    base = fullName
  end
  local playerName, playerRealm = UnitFullName("player")
  if playerRealm and playerRealm ~= "" then
    if not fullName:find("%-") then
      add(fullName .. "-" .. playerRealm)
    end
  end
  return out
end

function GRIP:BuildGateCtx(action, moduleName, phase, extra)
  local ctx = {
    action = action,
    phase = tostring(phase or ""),
    module = moduleName,
  }
  if extra ~= nil then
    ctx.extra = extra
  end
  return ctx
end

function GRIP:CfgBool(key, default)
  local cfg = self:GetCfg()
  if not cfg then return default end
  local v = cfg[key]
  if v == nil then return default end
  return v and true or false
end

function GRIP:CfgNum(key, default)
  local cfg = self:GetCfg()
  if not cfg then return default end
  local v = tonumber(cfg[key])
  if v == nil then return default end
  return v
end

-- ── End shared utility helpers ─────────────────────────────────────────

function GRIP:SortPotentialNames()
  local names = {}
  if not _G.GRIPDB_CHAR or type(GRIPDB_CHAR.potential) ~= "table" then
    return names
  end
  for name in pairs(GRIPDB_CHAR.potential) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function GateTraceEnabled()
  return (_G.GRIPDB_CHAR and type(GRIPDB_CHAR.config) == "table" and GRIPDB_CHAR.config.traceExecutionGate == true) and true or false
end

local function PreviewForTrace(msg)
  msg = tostring(msg or "")
  if #msg > 80 then
    return msg:sub(1, 80) .. "…"
  end
  return msg
end

function GRIP:SendChatMessageCompat(msg, chatType, languageID, target)
  msg = self:SafeTruncateChat(msg)

  -- Skip blank/whitespace-only sends (prevents empty whispers/posts)
  if msg:gsub("%s+", "") == "" then
    if self:IsDebugEnabled(2) then
      self:Debug("SendChatMessageCompat: blank message; skip. type=", tostring(chatType), "target=", tostring(target))
    end
    return false
  end

  -- NH-6: Don't attempt sends during messaging lockdown (encounter/M+/PvP safety net)
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local isRestricted, reason = C_ChatInfo.InChatMessagingLockdown()
    if isRestricted then
      if self:IsDebugEnabled(2) then
        self:Debug("SendChatMessageCompat: messaging lockdown, reason=",
          tostring(reason), "type=", tostring(chatType), "target=", tostring(target))
      end
      return false
    end
  end

  if chatType == "WHISPER" then
    GRIP:EnsureWhisperEchoFilter()
    AddRecentWhisper(msg, target)
  end

  -- Gate Trace Mode: attempted-send trace (opt-in, TRACE-level only).
  -- This intentionally does NOT gate; call sites should have already called BL_ExecutionGate().
  if GateTraceEnabled() and self.IsDebugEnabled and self:IsDebugEnabled(3) then
    self:Trace(
      "SEND ATTEMPT:",
      "type=", tostring(chatType),
      "target=", tostring(target),
      "len=", tostring(#msg),
      "preview=", PreviewForTrace(msg)
    )
  end

  -- Ghost Mode integration (Phase 1):
  -- ONLY route CHANNEL sends through Ghost Mode (posts), leave everything else direct for now.
  if chatType == "CHANNEL" then
    local gm = self.GhostMode
    if gm and gm.IsEnabled and gm.Send and gm:IsEnabled() then
      if GateTraceEnabled() and self.IsDebugEnabled and self:IsDebugEnabled(3) then
        self:Trace("SEND ROUTE: GhostMode", "type=CHANNEL", "channelId=", tostring(target))
      end
      local ok = gm:Send(chatType, msg, languageID, target)
      return ok and true or false
    end
  end

  -- ChatThrottleLib integration: route whispers through CTL for CPS fairness.
  -- CTL queues to OnUpdate which breaks CHANNEL (hardware-event restricted).
  -- WHISPER is NOT hardware-event restricted, so CTL queueing is safe.
  if chatType == "WHISPER" and _G.ChatThrottleLib then
    if GateTraceEnabled() and self.IsDebugEnabled and self:IsDebugEnabled(3) then
      self:Trace("SEND ROUTE: ChatThrottleLib", "type=WHISPER", "target=", tostring(target))
    end
    _G.ChatThrottleLib:SendChatMessage("NORMAL", "GRIP", msg, "WHISPER", languageID, target)
    return true
  end

  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    return C_ChatInfo.SendChatMessage(msg, chatType, languageID, target)
  end
  return SendChatMessage(msg, chatType, languageID, target)
end

-- Guild invite compat: prefer C_GuildInfo.Invite (12.0+), fall back to GuildInvite (deprecated 10.2.6)
function GRIP:SafeGuildInvite(name)
  if C_GuildInfo and C_GuildInfo.Invite then
    C_GuildInfo.Invite(name)
  elseif GuildInvite then
    GuildInvite(name)
  else
    self:Print("No guild invite API available.")
    return false
  end
  return true
end

function GRIP:PlayAlertSound(soundKitID)
  if not (_G.GRIPDB_CHAR and GRIPDB_CHAR.config and GRIPDB_CHAR.config.soundEnabled) then return end
  if not soundKitID then return end
  if _G.SOUNDKIT and PlaySound then
    PlaySound(soundKitID, "SFX")
  end
end

function GRIP:GlobalStringToPattern(gs)
  if type(gs) ~= "string" or gs == "" then return nil end
  local pat = gs:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  pat = pat:gsub("%%s", "(.+)")
  pat = pat:gsub("%%d", "(%%d+)")
  return "^" .. pat .. "$"
end

-- Find the longest prefix of `s` (in whole UTF-8 characters) where
-- `costFn(prefix) <= maxCost`. Uses binary search on character count.
function GRIP:TrimToBudget(s, maxCost, costFn)
  if type(s) ~= "string" or s == "" then return s end
  if costFn(s) <= maxCost then return s end
  -- Collect UTF-8 character boundary positions
  local boundaries = {1}  -- byte positions where each char starts
  local i = 1
  local len = #s
  while i <= len do
    local b = s:byte(i)
    local charLen
    if b < 0x80 then charLen = 1
    elseif b < 0xE0 then charLen = 2
    elseif b < 0xF0 then charLen = 3
    else charLen = 4
    end
    i = i + charLen
    if i <= len + 1 then
      boundaries[#boundaries + 1] = i
    end
  end
  -- Binary search: find largest char count where cost <= maxCost
  local lo, hi = 0, #boundaries - 1
  while lo < hi do
    local mid = lo + math.ceil((hi - lo) / 2)
    local prefix = s:sub(1, boundaries[mid + 1] - 1)
    if costFn(prefix) <= maxCost then
      lo = mid
    else
      hi = mid - 1
    end
  end
  if lo == 0 then return "" end
  return s:sub(1, boundaries[lo + 1] - 1)
end