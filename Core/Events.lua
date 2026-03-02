-- GRIP: Events
-- Event frame wiring: ADDON_LOADED, PLAYER_LOGIN, WHO_LIST_UPDATE, system messages.

local ADDON_NAME, GRIP = ...
local state = GRIP.state

-- Some GlobalStrings contain grammar tokens like |3-6(%s) which do NOT appear in the final CHAT_MSG_SYSTEM text.
-- Normalize those to plain %s/%d before building patterns.
local function NormGS(gs)
  if type(gs) ~= "string" or gs == "" then return gs end
  gs = gs:gsub("|3%-%d%((%%s)%)", "%s")
  gs = gs:gsub("|3%-%d%((%%d)%)", "%d")
  return gs
end

-- Build system message patterns (localization-friendly)
local PAT_GUILD_INVITE_SENT       = GRIP:GlobalStringToPattern(NormGS(_G.ERR_GUILD_INVITE_S))
local PAT_GUILD_JOINED            = GRIP:GlobalStringToPattern(NormGS(_G.ERR_GUILD_JOIN_S))     -- "%s has joined the guild."
local PAT_GUILD_DECLINED          = GRIP:GlobalStringToPattern(NormGS(_G.ERR_GUILD_DECLINE_S))  -- "%s declines your guild invitation."

-- Some clients/locales/patches have alternate keys for decline messages
local PAT_GUILD_DECLINED_ALT1     = GRIP:GlobalStringToPattern(NormGS(_G.ERR_GUILD_DECLINED_S))
local PAT_GUILD_DECLINED_ALT2     = GRIP:GlobalStringToPattern(NormGS(_G.ERR_GUILD_INVITE_DECLINED_S))

local PAT_GUILD_ALREADY_IN        = GRIP:GlobalStringToPattern(NormGS(_G.ERR_ALREADY_IN_GUILD_S))
local PAT_GUILD_ALREADY_INVITED   = GRIP:GlobalStringToPattern(NormGS(_G.ERR_ALREADY_INVITED_TO_GUILD_S))
local PAT_GUILD_PLAYER_NOT_FOUND  = GRIP:GlobalStringToPattern(NormGS(_G.ERR_GUILD_PLAYER_NOT_FOUND_S))

local PAT_CHAT_PLAYER_NOT_FOUND   = GRIP:GlobalStringToPattern(NormGS(_G.ERR_CHAT_PLAYER_NOT_FOUND_S))
local PAT_CHAT_PLAYER_AMBIG       = GRIP:GlobalStringToPattern(NormGS(_G.ERR_CHAT_PLAYER_AMBIGUOUS_S))

-- "Ignored" whisper failures (may be named or name-less depending on client/locale)
local GS_CHAT_PLAYER_IGNORED      = _G.ERR_CHAT_PLAYER_IGNORED_S or _G.ERR_CHAT_PLAYER_IGNORED
local PAT_CHAT_PLAYER_IGNORED     = GRIP:GlobalStringToPattern(NormGS(GS_CHAT_PLAYER_IGNORED))

-- Name-less invite failure strings (if present on this client)
local MSG_GUILD_IS_FULL           = _G.ERR_GUILD_IS_FULL
local MSG_GUILD_INTERNAL          = _G.ERR_GUILD_INTERNAL
local MSG_GUILD_INVITE_SELF       = _G.ERR_GUILD_INVITE_SELF
local MSG_GUILD_INVITE_NO_GUILD   = _G.ERR_GUILD_NOGUILD or _G.ERR_GUILDEMBLEM_NOGUILD

local function GetSinglePendingName(map)
  local found
  for name, v in pairs(map or {}) do
    if v then
      if found then return nil end
      found = name
    end
  end
  return found
end

local function ResolvePotentialName(nameMaybe)
  if not nameMaybe or nameMaybe == "" then return nil end
  if _G.GRIPDB and GRIPDB.potential and GRIPDB.potential[nameMaybe] then return nameMaybe end

  local short = tostring(nameMaybe):match("^[^-]+")
  if not short or not _G.GRIPDB or not GRIPDB.potential then return nil end

  local found
  for name in pairs(GRIPDB.potential) do
    if name:match("^[^-]+") == short then
      if found then return nil end -- ambiguous
      found = name
    end
  end
  return found
end

-- Resolve a possibly-short name against a pending map (pendingInvite / pendingWhisper).
-- Returns the full key if it can be uniquely resolved.
local function ResolvePendingName(map, nameMaybe)
  if type(map) ~= "table" or not nameMaybe or nameMaybe == "" then return nil end
  if map[nameMaybe] then return nameMaybe end

  local short = tostring(nameMaybe):match("^[^-]+")
  if not short then return nil end

  local found
  for name, v in pairs(map) do
    if v and tostring(name):match("^[^-]+") == short then
      if found then return nil end -- ambiguous
      found = name
    end
  end
  return found
end

local function InviteFailFor(whoMaybe, reason)
  local who = whoMaybe

  -- Prefer resolving against pendingInvite first (most truthful), then against Potential keys.
  local resolved = ResolvePendingName(state.pendingInvite, whoMaybe) or ResolvePotentialName(whoMaybe)
  if resolved then
    who = resolved
  end

  -- Only attribute directly if this name is actually pending.
  if who and who ~= "" then
    if not (state.pendingInvite and state.pendingInvite[who]) then
      -- If it's not pending, only safe attribution is the single pending invite target (if unique).
      who = GetSinglePendingName(state.pendingInvite)
    end
  else
    who = GetSinglePendingName(state.pendingInvite)
  end

  if not who then
    if GRIP:IsDebugEnabled(2) then
      GRIP:Debug("Invite fail but no unique pending target:", reason or "?")
    end
    return false
  end

  GRIP:Debug("Invite fail:", reason or "unknown", "target=", who)
  GRIP:OnInviteSystemFail(who, reason)
  return true
end

local function HandleWhisperIgnored(whoMaybe, rawMsg)
  local who = whoMaybe
  if not who or who == "" then
    who = GetSinglePendingName(state.pendingWhisper)
  end
  if not who then return false end

  local full = ResolvePendingName(state.pendingWhisper, who) or ResolvePotentialName(who) or who
  if not full or full == "" then return false end

  -- cancel any pending interactions for this person
  if state.pendingWhisper then state.pendingWhisper[full] = nil end
  if state.pendingInvite then state.pendingInvite[full] = nil end

  if _G.GRIPDB and GRIPDB.potential and GRIPDB.potential[full] then
    GRIPDB.potential[full].invitePending = false
  end

  GRIP:Debug("Whisper ignored -> permanent blacklist + remove:", full, "msg=", tostring(rawMsg or ""))
  GRIP:BlacklistPermanent(full, "ignored")
  GRIP:RemovePotential(full)
  GRIP:UpdateUI()
  return true
end

-- English fallbacks observed in your logs (only used if GlobalString patterns don't match)
local function MatchDeclinedEN(msg)
  return msg:match("^(.+) declines your guild invitation%.?$")
end
local function MatchJoinedEN(msg)
  return msg:match("^(.+) has joined the guild%.?$")
end
local function MatchAlreadyInGuildEN(msg)
  return msg:match("^(.+) is already in a guild%.?$")
end
local function MatchNoPlayerNamedEN(msg)
  return msg:match("^No player named '(.+)' is currently playing%.?$")
      or msg:match('^No player named "(.+)" is currently playing%.?$')
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("WHO_LIST_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("INITIAL_CLUBS_LOADED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then return end

    if GRIP:IsDebugEnabled(3) then
      GRIP:Trace("EVENT:", event, "addon=", tostring(name))
    end

    GRIP:EnsureDB()
    GRIP:PurgeBlacklist()

    -- Reconcile runtime/pending state once, after DB exists (prevents reload-stuck invitePending).
    if GRIP.ReconcileAfterReload then
      pcall(function() GRIP:ReconcileAfterReload() end)
    end

    if GRIPDB.config and GRIPDB.config.debug then
      GRIP:ResolveDebugFrame(true)
      GRIP:Debug("Loaded. Debug window=", GRIPDB.config.debugWindowName, "verbosity=", GRIPDB.config.debugVerbosity)
    end

    GRIP:BuildWhoQueue()
    GRIP:RegisterSlashCommands()
    GRIP:CreateUI()

    eventFrame:UnregisterEvent("ADDON_LOADED")
    GRIP:Debug("ADDON_LOADED complete.")
    return
  end

  if GRIP:IsDebugEnabled(3) then
    GRIP:Trace("EVENT:", event)
  end

  if event == "PLAYER_LOGIN" then
    GRIP:PurgeBlacklist()
    GRIP:StartPostScheduler()
    GRIP:Debug("PLAYER_LOGIN init complete.")
    return
  end

  if event == "WHO_LIST_UPDATE" then
    GRIP:Debug("WHO_LIST_UPDATE received.")
    GRIP:OnWhoListUpdate()
    return
  end

  if event == "CHAT_MSG_WHISPER_INFORM" then
    local msg, _, _, _, target = ...
    GRIP:Debug("WHISPER_INFORM to:", tostring(target), "msgLen=", msg and #msg or 0)
    GRIP:OnWhisperInform(target)
    return
  end

  -- Guild data events: warm caches for guild name and guild finder link.
  if event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
    -- GetGuildInfo("player") becomes available after these events fire.
    GRIP:GetGuildName()
    if GRIP:IsDebugEnabled(3) then
      GRIP:Trace("Guild cache warmed on", event, "guild=", GRIP.state._gripLastGuildName or "?")
    end
    return
  end

  if event == "INITIAL_CLUBS_LOADED" then
    -- C_Club.GetGuildClubId() becomes available now; warm guild link cache.
    GRIP:GetGuildName()
    GRIP:GetGuildFinderLink()
    if GRIP:IsDebugEnabled(2) then
      GRIP:Debug("Club cache warmed on INITIAL_CLUBS_LOADED guild=",
        GRIP.state._gripLastGuildName or "?",
        "link=", (GRIP.state._gripGuildLinkCache and GRIP.state._gripGuildLinkCache ~= "") and "yes" or "no")
    end
    return
  end

  if event == "CHAT_MSG_SYSTEM" then
    local msg = ...
    if type(msg) ~= "string" then return end

    if GRIP:IsDebugEnabled(3) then
      GRIP:Trace("SYSTEM:", msg)
    end

    -- Whisper ignored (permanent blacklist)
    do
      local who
      if PAT_CHAT_PLAYER_IGNORED then
        who = msg:match(PAT_CHAT_PLAYER_IGNORED)
      end
      if who and HandleWhisperIgnored(who, msg) then return end

      -- Name-less ignore messages: exact match (only if the global string has no %s)
      if (not who) and GS_CHAT_PLAYER_IGNORED and not tostring(GS_CHAT_PLAYER_IGNORED):find("%%s", 1, true) then
        if msg == GS_CHAT_PLAYER_IGNORED then
          if HandleWhisperIgnored(nil, msg) then return end
        end
      end

      -- Heuristic fallback: only if exactly one pending whisper
      local low = msg:lower()
      if (low:find("ignoring you", 1, true) or low:find("ignore you", 1, true)) then
        if HandleWhisperIgnored(nil, msg) then return end
      end
    end

    -- "No player named 'X' is currently playing." (can happen for whisper and/or invite)
    do
      local whoRaw = MatchNoPlayerNamedEN(msg)
      if whoRaw and whoRaw ~= "" then
        local whoWhisper = ResolvePendingName(state.pendingWhisper, whoRaw) or whoRaw
        if state.pendingWhisper and state.pendingWhisper[whoWhisper] then
          GRIP:Debug("Whisper fail: player not found:", whoWhisper)
          GRIP:OnWhisperFailed(whoWhisper)
        end

        local whoInvite = ResolvePendingName(state.pendingInvite, whoRaw) or whoRaw
        if state.pendingInvite and (state.pendingInvite[whoInvite] or GetSinglePendingName(state.pendingInvite)) then
          GRIP:Debug("Invite fail: player not found:", whoInvite)
          InviteFailFor(whoInvite, "player_not_found")
        end
        return
      end
    end

    -- Whisper failures (not ignored)
    if PAT_CHAT_PLAYER_NOT_FOUND then
      local who = msg:match(PAT_CHAT_PLAYER_NOT_FOUND)
      if who then
        GRIP:Debug("Whisper fail: player not found:", who)
        GRIP:OnWhisperFailed(who)
      end
    end
    if PAT_CHAT_PLAYER_AMBIG then
      local who = msg:match(PAT_CHAT_PLAYER_AMBIG)
      if who then
        GRIP:Debug("Whisper fail: ambiguous:", who)
        GRIP:OnWhisperFailed(who)
      end
    end

    -- Invite lifecycle: sent (informational only)
    if PAT_GUILD_INVITE_SENT then
      local who = msg:match(PAT_GUILD_INVITE_SENT)
      if who then
        GRIP:Debug("Invite sent system msg:", who)
      end
    end

    -- Invite accepted / joined
    do
      local who
      if PAT_GUILD_JOINED then who = msg:match(PAT_GUILD_JOINED) end
      if not who then who = MatchJoinedEN(msg) end
      if who then
        GRIP:Debug("Invite accepted / joined guild:", who)
        GRIP:OnInviteSystemSuccess(who)
        return
      end
    end

    -- Invite declined
    do
      local who
      if PAT_GUILD_DECLINED then who = msg:match(PAT_GUILD_DECLINED) end
      if (not who) and PAT_GUILD_DECLINED_ALT1 then who = msg:match(PAT_GUILD_DECLINED_ALT1) end
      if (not who) and PAT_GUILD_DECLINED_ALT2 then who = msg:match(PAT_GUILD_DECLINED_ALT2) end
      if not who then who = MatchDeclinedEN(msg) end
      if who then
        GRIP:Debug("Invite declined:", who)
        GRIP:OnInviteSystemFail(who, "declined")
        return
      end
    end

    -- Invite hard failures (named)
    if PAT_GUILD_ALREADY_IN then
      local who = msg:match(PAT_GUILD_ALREADY_IN)
      if who then
        GRIP:Debug("Invite fail: already in guild:", who)
        GRIP:OnInviteSystemFail(who, "already_in")
        return
      end
    end
    if PAT_GUILD_ALREADY_INVITED then
      local who = msg:match(PAT_GUILD_ALREADY_INVITED)
      if who then
        GRIP:Debug("Invite fail: already invited:", who)
        GRIP:OnInviteSystemFail(who, "already_invited")
        return
      end
    end
    if PAT_GUILD_PLAYER_NOT_FOUND then
      local who = msg:match(PAT_GUILD_PLAYER_NOT_FOUND)
      if who then
        GRIP:Debug("Invite fail: player not found:", who)
        GRIP:OnInviteSystemFail(who, "player_not_found")
        return
      end
    end

    -- English fallback: "X is already in a guild."
    do
      local who = MatchAlreadyInGuildEN(msg)
      if who then
        GRIP:Debug("Invite fail: already in guild:", who)
        GRIP:OnInviteSystemFail(who, "already_in")
        return
      end
    end

    -- Hard failures (no name in message): only safe to attribute if exactly one invite is pending
    if MSG_GUILD_IS_FULL and msg == MSG_GUILD_IS_FULL then
      InviteFailFor(nil, "guild_full")
      return
    end
    if MSG_GUILD_INTERNAL and msg == MSG_GUILD_INTERNAL then
      InviteFailFor(nil, "guild_internal")
      return
    end
    if MSG_GUILD_INVITE_SELF and msg == MSG_GUILD_INVITE_SELF then
      InviteFailFor(nil, "invite_self")
      return
    end
    if MSG_GUILD_INVITE_NO_GUILD and msg == MSG_GUILD_INVITE_NO_GUILD then
      InviteFailFor(nil, "no_guild")
      return
    end

    -- Fallback heuristic for other invite-blocked errors that don't match known patterns.
    -- Only applies if there is exactly one pending invite target.
    do
      local single = GetSinglePendingName(state.pendingInvite)
      if single then
        local low = msg:lower()
        if low:find("guild", 1, true) and (low:find("invite", 1, true) or low:find("invitation", 1, true)) then
          if low:find("can't", 1, true) or low:find("cannot", 1, true) or low:find("error", 1, true) or low:find("failed", 1, true) then
            InviteFailFor(single, "blocked")
            return
          end
        end
      end
    end

    return
  end
end)