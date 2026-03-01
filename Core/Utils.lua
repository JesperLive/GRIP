-- GRIP: Utils
-- Shared helpers: template engine, chat compat, whisper echo suppression, pattern matching.

local ADDON_NAME, GRIP = ...
local state = GRIP.state

-- ----------------------------
-- Optional: hide outgoing whisper echoes in chat ("To X: ...")
-- This does NOT affect event processing (CHAT_MSG_WHISPER_INFORM still fires).
-- Enable with: GRIPDB.config.suppressWhisperEcho = true
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

  msg = tostring(msg or "")
  author = tostring(author or "")

  for i = #buf, 1, -1 do
    local e = buf[i]
    if e and e.msg == msg then
      -- author for CHAT_MSG_WHISPER_INFORM is usually the target name.
      if author == e.target or author:match("^[^-]+") == tostring(e.target):match("^[^-]+") then
        return true
      end
    end
  end
  return false
end

local function WhisperInformFilter(_, event, msg, author, ...)
  if event ~= "CHAT_MSG_WHISPER_INFORM" then return false end
  if not (_G.GRIPDB and GRIPDB.config and GRIPDB.config.suppressWhisperEcho) then
    return false
  end

  if RecentWhisperMatches(msg, author) then
    return true -- swallow this chat line
  end
  return false
end

local function EnsureWhisperEchoFilter()
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

  -- If the client can tell us we're not in a guild, don't reuse cached data.
  if IsInGuild and not IsInGuild() then
    state._gripLastGuildName = ""
    return ""
  end

  local name = ""

  -- Prefer modern Retail API when available.
  if C_GuildInfo and C_GuildInfo.GetGuildInfo then
    local ok, info = pcall(C_GuildInfo.GetGuildInfo, "player")
    if ok and type(info) == "table" and type(info.guildName) == "string" then
      name = info.guildName
    end
  end

  -- Fallback to legacy global API.
  if name == "" and GetGuildInfo then
    local g = GetGuildInfo("player")
    if type(g) == "string" then
      name = g
    end
  end

  -- Cache last known good value to survive transient empty returns.
  if type(name) == "string" and name ~= "" then
    state._gripLastGuildName = name
    return name
  end

  if state._gripLastGuildName ~= "" then
    return state._gripLastGuildName
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

  return (ClubFinderGetCurrentClubListingInfo ~= nil) and (GetClubFinderLink ~= nil)
end

-- Clickable Guild Finder link (if available)
-- Uses ClubFinder listing APIs when present.
function GRIP:GetGuildFinderLink()
  if not C_Club or not C_Club.GetGuildClubId then
    if self:IsDebugEnabled(3) then
      self:Trace("GetGuildFinderLink: missing C_Club.GetGuildClubId")
    end
    return ""
  end

  -- These globals may not exist until Blizzard_ClubFinder is loaded.
  if not ClubFinderGetCurrentClubListingInfo or not GetClubFinderLink then
    self:_TryLoadClubFinder()
  end

  if not ClubFinderGetCurrentClubListingInfo or not GetClubFinderLink then
    if self:IsDebugEnabled(3) then
      self:Trace("GetGuildFinderLink: ClubFinder link APIs unavailable (Blizzard_ClubFinder not loaded?)")
    end
    return ""
  end

  local ok, clubId = pcall(C_Club.GetGuildClubId)
  if not ok or not clubId then
    if self:IsDebugEnabled(3) then
      self:Trace("GetGuildFinderLink: no clubId from C_Club.GetGuildClubId")
    end
    return ""
  end

  local ok2, listing = pcall(ClubFinderGetCurrentClubListingInfo, clubId)
  if not ok2 or not listing then
    if self:IsDebugEnabled(3) then
      self:Trace("GetGuildFinderLink: no listing info (guild listing may not be published or not cached yet)")
    end
    return ""
  end
  if not listing.clubFinderGUID or not listing.name then
    if self:IsDebugEnabled(3) then
      self:Trace("GetGuildFinderLink: listing missing clubFinderGUID/name")
    end
    return ""
  end

  local ok3, link = pcall(GetClubFinderLink, listing.clubFinderGUID, listing.name)
  if ok3 and type(link) == "string" and link ~= "" then
    return link
  end

  if self:IsDebugEnabled(3) then
    self:Trace("GetGuildFinderLink: GetClubFinderLink failed or returned empty")
  end
  return ""
end

local function IsBlank(s)
  if type(s) ~= "string" then return true end
  return s:gsub("%s+", "") == ""
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
  tpl = tpl:gsub("{guild}", self:GetGuildName():gsub("%%", "%%%%"))

  -- If the template includes {guildlink}, make sure the link (or fallback) survives truncation.
  if tpl:find("{guildlink}", 1, true) then
    local guildName = self:GetGuildName()
    local inGuild = (guildName and guildName ~= "")

    -- Prefer clickable ClubFinder link only if actually in a guild; otherwise don't poke ClubFinder APIs.
    local link = ""
    if inGuild then
      link = self:GetGuildFinderLink() or ""
    end

    -- Guaranteed fallback (still useful even if listing isn't published/cached yet).
    if IsBlank(link) then
      if inGuild then
        link = guildName
      else
        link = "your guild"
      end
    end

    -- Replace token before truncation decisions.
    tpl = tpl:gsub("{guildlink}", link:gsub("%%", "%%%%"))

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

  return self:SafeTruncateChat(tpl)
end

function GRIP:Count(tbl)
  if type(tbl) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(tbl) do n = n + 1 end
  return n
end

function GRIP:SortPotentialNames()
  local names = {}
  if not _G.GRIPDB or type(GRIPDB.potential) ~= "table" then
    return names
  end
  for name in pairs(GRIPDB.potential) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function GateTraceEnabled()
  return (_G.GRIPDB and type(GRIPDB.config) == "table" and GRIPDB.config.traceExecutionGate == true) and true or false
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

  if chatType == "WHISPER" then
    EnsureWhisperEchoFilter()
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

function GRIP:GlobalStringToPattern(gs)
  if type(gs) ~= "string" or gs == "" then return nil end
  local pat = gs:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  pat = pat:gsub("%%s", "(.+)")
  pat = pat:gsub("%%d", "(%%d+)")
  return "^" .. pat .. "$"
end