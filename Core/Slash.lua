-- GRIP: Slash
-- /grip command handler and all subcommands.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, pcall, wipe = pairs, pcall, wipe
local time = time

-- WoW API
local C_Club = C_Club
local C_ClubFinder = C_ClubFinder

local state = GRIP.state
local L = LibStub("AceLocale-3.0"):GetLocale("GRIP")

-- =========================================================================
-- Import/Export popups (registered once, lazily)
-- =========================================================================

local function EnsureExportPopup()
  if not StaticPopupDialogs then return end
  if StaticPopupDialogs["GRIP_EXPORT"] then return end

  StaticPopupDialogs["GRIP_EXPORT"] = {
    text = L["Copy this GRIP export string:"],
    button1 = L["Close"],
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    hasEditBox = true,
    editBoxWidth = 350,
    OnShow = function(self)
      if self.editBox then
        self.editBox:SetMaxBytes(0)
        self.editBox:SetText(self.data or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
      end
    end,
    EditBoxOnEscapePressed = function(self)
      local parent = self:GetParent()
      if parent and parent.button1 and parent.button1.Click then
        parent.button1:Click()
      end
    end,
  }
end

local function EnsureImportPopup()
  if not StaticPopupDialogs then return end
  if StaticPopupDialogs["GRIP_IMPORT"] then return end

  StaticPopupDialogs["GRIP_IMPORT"] = {
    text = L["Paste a GRIP import string:"],
    button1 = L["Import"],
    button2 = L["Cancel"],
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    hasEditBox = true,
    editBoxWidth = 350,
    OnShow = function(self)
      if self.editBox then
        self.editBox:SetMaxBytes(0)
        self.editBox:SetText("")
        self.editBox:SetFocus()
      end
    end,
    OnAccept = function(self)
      local text = self.editBox and self.editBox:GetText() or ""
      text = text:gsub("^%s+", ""):gsub("%s+$", "")
      if text == "" then
        GRIP:Print(L["No import string provided."])
        return
      end

      -- Detect type from prefix
      if text:sub(1, 9) == "!GRIP:BL:" then
        if not GRIP.ImportBlacklist then
          GRIP:Print(L["Import module not loaded."])
          return
        end
        local result = GRIP:ImportBlacklist(text)
        if result then
          GRIP:Print((L["Imported: %d new blacklist entries (%d already existed)."]):format(
            result.added, result.existing))
          GRIP:UpdateUI()
        else
          GRIP:Print(L["Invalid blacklist import string."])
        end
      elseif text:sub(1, 10) == "!GRIP:TPL:" then
        if not GRIP.ImportTemplates then
          GRIP:Print(L["Import module not loaded."])
          return
        end
        local result = GRIP:ImportTemplates(text)
        if result then
          GRIP:Print((L["Imported %d whisper templates (%s rotation)."]):format(
            result.count, result.rotation))
          GRIP:UpdateUI()
        else
          GRIP:Print(L["Invalid template import string."])
        end
      else
        GRIP:Print(L["Invalid import string. Must start with !GRIP:BL: or !GRIP:TPL:"])
      end
    end,
    EditBoxOnEnterPressed = function(self)
      local parent = self:GetParent()
      if parent and parent.button1 and parent.button1.Click then
        parent.button1:Click()
      end
    end,
    EditBoxOnEscapePressed = function(self)
      local parent = self:GetParent()
      if parent and parent.button2 and parent.button2.Click then
        parent.button2:Click()
      end
    end,
  }
end

-- Constants
local DUMP_LINES_DEFAULT      = 50
local DUMP_LINES_MIN          = 1
local DUMP_LINES_MAX          = 200
local PERMBL_DISPLAY_CAP      = 20
local MAX_WHISPER_TEMPLATES   = 10
local DEBUG_PERSIST_MIN       = 100
local DEBUG_PERSIST_MAX       = 5000
local SCAN_STEP_MIN           = 1
local SCAN_STEP_MAX           = 20
local VERBOSITY_MIN           = 1
local VERBOSITY_MAX           = 3
local BLACKLIST_DAYS_MIN      = 1
local BLACKLIST_DAYS_MAX      = 365
local POST_INTERVAL_MIN       = 1
local POST_INTERVAL_MAX       = 180
local COOLDOWN_MIN            = 5
local COOLDOWN_MAX            = 120
local SYNC_COOLDOWN           = 3600

local function SplitArgs(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local a, b = msg:match("^(%S+)%s*(.*)$")
  return a and a:lower() or "", b or ""
end

local function EnsureStateTables()
  state.whoQueue = state.whoQueue or {}
  state.whisperQueue = state.whisperQueue or {}
  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingInvite = state.pendingInvite or {}
  state.postQueue = state.postQueue or {}
end

function GRIP:PrintHelp()
  self:Print(L["GRIP Commands:"])
  self:Print(L["  /grip — toggle UI"])
  self:Print(L["  /grip build — rebuild /who queue"])
  self:Print(L["  /grip scan — next /who (needs click/keybind)"])
  self:Print(L["  /grip whisper — start/stop whisper queue"])
  self:Print(L["  /grip invite — whisper+invite next (needs click/keybind)"])
  self:Print(L["  /grip post — send next post (needs click/keybind)"])
  self:Print(L["  /grip clear — clear Potential list"])
  self:Print(L["  /grip status — print counts"])
  self:Print(L["  /grip link — show guild link info"])
  self:Print(L["  /grip permbl list|add|remove|clear — manage permanent blacklist"])
  self:Print(L["  /grip ghost [start|stop|status] — Ghost Mode sessions"])
  self:Print(L["  /grip sync [on|off|now] — officer sync control"])
  self:Print(L["  /grip export bl|templates — export data to clipboard"])
  self:Print(L["  /grip import — paste an import string"])
  self:Print(L["  /grip templates list|add|remove|rotation — manage whisper templates"])
  self:Print(L["  /grip stats [7d|30d] — recruitment stats"])
  self:Print(L["  /grip stats reset — clear stats history"])
  self:Print(L["  /grip perf — performance baseline (perf all = extra detail)"])
  self:Print(L["  /grip zones diag|reseed|deep|export — zone diagnostics"])
  self:Print(L["  /grip reset — reset UI position/size"])
  self:Print(L["  /grip tracegate on|off|toggle — execution gate diagnostics"])
  self:Print(L["  /grip debug on|off|dump|copy|clear|capture|status"])
  self:Print(L["  /grip set <key> <value> — change settings"])
  self:Print(L["  /grip minimap on|off|toggle"])
  self:Print(L["  /grip help — this help"])
  self:Print(L["Settings keys:"])
  self:Print(L["  whisper <msg> — set whisper template #1"])
  self:Print(L["  general <msg> — set General channel message"])
  self:Print(L["  trade <msg> — set Trade channel message"])
  self:Print(L["  blacklistdays <n> — temp blacklist duration"])
  self:Print(L["  interval <n> — post interval (minutes)"])
  self:Print(L["  zoneonly on|off — restrict /who to current zone"])
  self:Print(L["  levels <min> <max> <step> — scan range"])
  self:Print(L["  debugwindow <name> — debug output window"])
  self:Print(L["  verbosity <1|2|3> — debug verbosity"])
  self:Print(L["  hidewhispers on|off — suppress outgoing whisper echo"])
  self:Print(L["  dailycap <n> — daily whisper cap (0=unlimited)"])
  self:Print(L["  optout on|off — auto-blacklist opt-out replies"])
  self:Print(L["  aggressive on|off — aggressive opt-out detection"])
  self:Print(L["  sound on|off — master sound toggle"])
  self:Print(L["  ghostmode on|off — Ghost Mode (experimental)"])
  self:Print(L["  invitefirst on|off — invite before whisper"])
  self:Print(L["  cooldown <n>|on|off — campaign break timer"])
  self:Print(L["  riominscore <n> — M+ score filter (0=disabled)"])
  self:Print(L["  riocolumn on|off — show M+ column"])
  self:Print(L["Note: {guildlink} in whisper/post messages requires an active Guild Finder listing."])
end

local function PrintPermBLUsage()
  GRIP:Print(L["Usage: /grip permbl list|add <name> [reason]|remove <name>|clear"])
end

local function PrintDebugUsage()
  GRIP:Print(L["Usage: /grip debug on|off | dump [n] | copy [n] | clear | capture on|off [max] | status"])
end

local function IsGhostLocked()
  return GRIP.Ghost and GRIP.Ghost.IsSessionLocked and GRIP.Ghost:IsSessionLocked()
end

local function PrintGhostLocked()
  GRIP:Print(L["Command locked during Ghost session. Use /grip ghost stop first."])
end

local function BoolFromWord(w)
  w = (w or ""):lower()
  return (w == "on" or w == "1" or w == "true" or w == "yes")
end

local function DumpPersisted(n)
  n = tonumber(n) or DUMP_LINES_DEFAULT
  n = GRIP:Clamp(n, DUMP_LINES_MIN, DUMP_LINES_MAX)

  if not GRIP.GetPersistedDebugLines then
    GRIP:Print(L["Debug dump unavailable (Debug module not wired yet)."])
    return
  end

  local lines = GRIP:GetPersistedDebugLines()
  if type(lines) ~= "table" or #lines == 0 then
    GRIP:Print(L["Debug persisted log is empty (or capture is OFF)."])
    return
  end

  local total = #lines
  GRIP:Print((L["Debug dump (last %d of %d):"]):format(math.min(n, total), total))

  local start = math.max(1, total - n + 1)
  for i = start, total do
    GRIP:Print(lines[i])
  end
end

local function ClearPersisted()
  if not GRIP.ClearPersistedDebugLines then
    GRIP:Print(L["Debug clear unavailable (Debug module not wired yet)."])
    return
  end
  local removed = GRIP:ClearPersistedDebugLines()
  GRIP:Print((L["Debug persisted log cleared (%d lines)."]):format(tonumber(removed) or 0))
end

local function DebugStatus()
  local cfg = GRIP:GetCfg() or {}
  local on = (cfg.debugPersist == true) or (cfg.debugCapture == true)
  local max = tonumber(cfg.debugPersistMax or cfg.debugCaptureMax) or 800

  local stored = 0
  if GRIP.GetPersistedDebugLines then
    local t = GRIP:GetPersistedDebugLines()
    stored = (type(t) == "table" and #t) or 0
  end

  local dropped = 0
  if GRIP.GetPersistedDebugDropped then
    dropped = tonumber(GRIP:GetPersistedDebugDropped()) or 0
  elseif _G.GRIPDB_CHAR and GRIPDB_CHAR.debugLog and GRIPDB_CHAR.debugLog.dropped then
    dropped = tonumber(GRIPDB_CHAR.debugLog.dropped) or 0
  end

  GRIP:Print((L["Debug capture: %s (max=%d, stored=%d, dropped=%d)"]):format(
      on and L["ON"] or L["OFF"], max, stored, dropped))
end

local function TraceGateStatus()
  local cfg = GRIP:GetCfg()
  local on = (cfg and cfg.traceExecutionGate == true) and true or false
  GRIP:Print(L["Gate Trace Mode: "] .. (on and L["ON"] or L["OFF"]) .. " (GRIPDB.config.traceExecutionGate)")
end

local function HandleTraceGate(rest)
  local sub = (GRIP:Trim(rest) or ""):lower()

  if sub == "" then
    TraceGateStatus()
    return
  end

  local cfg = GRIP:GetCfg()
  if not cfg then
    GRIP:Print(L["GRIPDB not initialized yet."])
    return
  end

  if sub == "toggle" then
    cfg.traceExecutionGate = not (cfg.traceExecutionGate == true)
    TraceGateStatus()
    return
  end

  if sub == "on" or sub == "off" or sub == "1" or sub == "0"
      or sub == "true" or sub == "false" or sub == "yes" or sub == "no" then
    cfg.traceExecutionGate = BoolFromWord(sub) and true or false
    TraceGateStatus()
    return
  end

  GRIP:Print(L["Usage: /grip tracegate on|off|toggle"])
end

function GRIP:HandleSlash(msg)
  EnsureStateTables()

  local cmd, rest = SplitArgs(msg)

  if cmd == "" then
    self:ToggleUI()
    return
  end

  if cmd == "help" then
    self:PrintHelp()
    return
  end

  -- Most commands require a configured DB
  if not _G.GRIPDB_CHAR or not GRIPDB_CHAR.config then
    self:Print(L["GRIPDB not initialized yet."])
    return
  end

  if cmd == "reset" then
    GRIP:ResetUI()
    return
  end

  if cmd == "tracegate" or cmd == "gatetrace" then
    HandleTraceGate(rest)
    return
  end

  if cmd == "build" then
    if IsGhostLocked() then PrintGhostLocked() return end
    self:BuildWhoQueue()
    return
  end

  if cmd == "scan" or cmd == "who" then
    if IsGhostLocked() then PrintGhostLocked() return end
    self:SendNextWho()
    return
  end

  if cmd == "whisper" then
    if IsGhostLocked() then PrintGhostLocked() return end
    self:StartWhispers()
    return
  end

  if cmd == "invite" then
    if IsGhostLocked() then PrintGhostLocked() return end
    self:InviteNext()
    return
  end

  if cmd == "post" then
    if IsGhostLocked() then PrintGhostLocked() return end
    self:PostNext()
    return
  end

  if cmd == "ghost" then
    local sub = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if sub == "start" then
      local ok, _ = GRIP.Ghost:StartSession()
      if ok then
        self:Print(L["Ghost Mode session started. Queue actions will execute from any input."])
      end
    elseif sub == "stop" then
      GRIP.Ghost:StopSession("manual")
      self:Print(L["Ghost Mode session stopped."])
    elseif sub == "status" then
      local cfg = GRIPDB_CHAR.config
      if GRIP.Ghost:IsSessionActive() then
        local elapsed = math.floor((time() - (state.ghost.sessionStartedAt or time())) / 60)
        local maxMin = cfg and cfg.ghostSessionMaxMinutes or 60
        self:Print((L["Ghost Mode: ACTIVE (%d/%d min, %d actions, %d queued)"]):format(
          elapsed, maxMin, state.ghost.sessionActionCount or 0, GRIP.Ghost:GetNumPending()))
      else
        local now = time()
        local cdUntil = tonumber(cfg and cfg.ghostCooldownUntil) or 0
        if now < cdUntil then
          local remaining = math.ceil((cdUntil - now) / 60)
          self:Print((L["Ghost Mode: COOLDOWN (%d min remaining)"]):format(remaining))
        else
          self:Print(L["Ghost Mode: inactive (ready)"])
        end
      end
    elseif sub == "" then
      -- Toggle: start if inactive, stop if active
      if GRIP.Ghost:IsSessionActive() then
        GRIP.Ghost:StopSession("manual")
        self:Print(L["Ghost Mode session stopped."])
      else
        local ok, _ = GRIP.Ghost:StartSession()
        if ok then
          self:Print(L["Ghost Mode session started. Queue actions will execute from any input."])
        end
      end
    else
      self:Print(L["Usage: /grip ghost [start|stop|status]"])
    end
    return
  end

  if cmd == "sync" then
    local sub = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if sub == "on" then
      if not _G.GRIPDB then self:Print(L["GRIPDB not initialized."]) return end
      GRIPDB.syncEnabled = true
      self:Print((L["Officer sync: %s"]):format(L["ON"]))
      if self.InitSync then pcall(function() self:InitSync() end) end
      return
    end

    if sub == "off" then
      if not _G.GRIPDB then self:Print(L["GRIPDB not initialized."]) return end
      GRIPDB.syncEnabled = false
      self:Print((L["Officer sync: %s"]):format(L["OFF"]))
      return
    end

    if sub == "now" then
      if self.SyncForceNow then
        self:SyncForceNow()
      else
        self:Print(L["Sync module not loaded."])
      end
      return
    end

    -- Default: status
    local info = self.GetSyncStatus and self:GetSyncStatus() or {}
    local cfg = GRIPDB_CHAR.config
    self:Print((L["Sync: %s (libs=%s, guild=%s)"]):format(
      info.enabled and L["ON"] or L["OFF"],
      info.libsLoaded and "ok" or "missing",
      info.inGuild and "yes" or "no"
    ))
    self:Print((L["  Blacklist hash: %s"]):format(info.blHash or "?"))
    self:Print((L["  Templates: %s (hash: %s)"]):format(
      cfg.syncTemplates ~= false and L["ON"] or L["OFF"],
      info.tplHash or "?"
    ))
    if info.lastSyncAt and info.lastSyncAt > 0 then
      local ago = math.floor(time() - info.lastSyncAt)
      self:Print((L["  Last broadcast: %ds ago (cooldown: %ds)"]):format(ago, SYNC_COOLDOWN or 3600))
    else
      self:Print(L["  Last broadcast: never"])
    end
    return
  end

  if cmd == "export" then
    local sub = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if sub == "bl" or sub == "blacklist" then
      if not self.ExportBlacklist then
        self:Print(L["Export module not loaded."])
        return
      end
      local str = self:ExportBlacklist()
      if not str then
        self:Print(L["Export failed (empty blacklist or codec error)."])
        return
      end
      local count = self:Count(GRIPDB.blacklistPerm)
      EnsureExportPopup()
      if StaticPopup_Show then
        StaticPopup_Show("GRIP_EXPORT", nil, nil, str)
      end
      self:Print((L["Exported %d blacklist entries — copy the string from the popup."]):format(count))
      return
    end

    if sub == "templates" or sub == "tpl" then
      if not self.ExportTemplates then
        self:Print(L["Export module not loaded."])
        return
      end
      local str = self:ExportTemplates()
      if not str then
        self:Print(L["Export failed (no templates or codec error)."])
        return
      end
      local cfg = GRIPDB_CHAR.config
      local count = type(cfg.whisperMessages) == "table" and #cfg.whisperMessages or 0
      EnsureExportPopup()
      if StaticPopup_Show then
        StaticPopup_Show("GRIP_EXPORT", nil, nil, str)
      end
      self:Print((L["Exported %d whisper templates — copy the string from the popup."]):format(count))
      return
    end

    self:Print(L["Usage: /grip export bl|templates"])
    return
  end

  if cmd == "import" then
    EnsureImportPopup()
    if StaticPopup_Show then
      StaticPopup_Show("GRIP_IMPORT")
    else
      self:Print(L["StaticPopup not available."])
    end
    return
  end

  if cmd == "permbl" or cmd == "permblacklist" then
    local sub, subrest = SplitArgs(rest)
    subrest = GRIP:Trim(subrest)

    if sub == "" or sub == "list" then
      local names = self.GetPermanentBlacklistNames and self:GetPermanentBlacklistNames() or {}
      local total = #names
      self:Print((L["Permanent blacklist: %d"]):format(total))

      local cap = PERMBL_DISPLAY_CAP
      for i = 1, math.min(total, cap) do
        local n = names[i]
        local e = _G.GRIPDB and GRIPDB.blacklistPerm and GRIPDB.blacklistPerm[n]
        local reason = (type(e) == "table" and e.reason) or (e == true and "permanent") or nil
        if reason and reason ~= "" then
          self:Print((L["  - %s (%s)"]):format(n, reason))
        else
          self:Print((L["  - %s"]):format(n))
        end
      end
      if total > cap then
        self:Print((L["  ... and %d more"]):format(total - cap))
      end
      return
    end

    if sub == "add" then
      local name, reason = SplitArgs(subrest)
      name = GRIP:Trim(name)
      reason = GRIP:Trim(reason)
      if name == "" then
        PrintPermBLUsage()
        return
      end
      self:BlacklistPermanent(name, reason ~= "" and reason or "manual")
      self:RemovePotential(name)
      self:Print((L["Permanent blacklisted: %s"]):format(name))
      self:UpdateUI()
      return
    end

    if sub == "remove" or sub == "del" or sub == "rm" then
      local name = GRIP:Trim(subrest)
      if name == "" then
        PrintPermBLUsage()
        return
      end
      local ok = self.UnblacklistPermanent and self:UnblacklistPermanent(name)
      if ok then
        self:Print((L["Permanent blacklist removed: %s"]):format(name))
      else
        self:Print((L["Not in permanent blacklist: %s"]):format(name))
      end
      self:UpdateUI()
      return
    end

    if sub == "clear" then
      local n = self.ClearPermanentBlacklist and self:ClearPermanentBlacklist() or 0
      self:Print((L["Permanent blacklist cleared: %d"]):format(n))
      self:UpdateUI()
      return
    end

    PrintPermBLUsage()
    return
  end

  if cmd == "minimap" then
    local v = (rest or ""):lower()
    if v == "on" then
      self:ToggleMinimapButton(true)
    elseif v == "off" then
      self:ToggleMinimapButton(false)
    else
      self:ToggleMinimapButton(nil)
    end
    return
  end

  if cmd == "templates" or cmd == "template" then
    local sub, subrest = SplitArgs(rest)
    subrest = GRIP:Trim(subrest)
    local cfg = GRIPDB_CHAR.config

    if sub == "" or sub == "list" then
      local msgs = cfg.whisperMessages or {}
      self:Print((L["Whisper templates (%d), rotation: %s"]):format(#msgs, cfg.whisperRotation or "sequential"))
      for i = 1, #msgs do
        self:Print((L["  [%d] %s"]):format(i, msgs[i] or ""))
      end
      return
    end

    if sub == "add" then
      if subrest == "" then
        self:Print(L["Usage: /grip templates add <message text>"])
        return
      end
      cfg.whisperMessages = cfg.whisperMessages or {}
      if #cfg.whisperMessages >= MAX_WHISPER_TEMPLATES then
        self:Print((L["Max %d templates."]):format(MAX_WHISPER_TEMPLATES))
        return
      end
      cfg.whisperMessages[#cfg.whisperMessages + 1] = subrest
      cfg.templatesEditedAt = time()
      self:Print((L["Added template #%d."]):format(#cfg.whisperMessages))
      return
    end

    if sub == "remove" or sub == "rm" or sub == "del" then
      local n = tonumber(subrest)
      cfg.whisperMessages = cfg.whisperMessages or {}
      if not n or n < 1 or n > #cfg.whisperMessages then
        self:Print((L["Usage: /grip templates remove <1-%d>"]):format(math.max(1, #cfg.whisperMessages)))
        return
      end
      if #cfg.whisperMessages <= 1 then
        self:Print(L["Must have at least 1 template."])
        return
      end
      table.remove(cfg.whisperMessages, n)
      cfg.whisperMessage = cfg.whisperMessages[1] or ""
      cfg.templatesEditedAt = time()
      self:Print((L["Removed template #%d. (%d remaining)"]):format(n, #cfg.whisperMessages))
      return
    end

    if sub == "rotation" then
      local mode = (subrest or ""):lower()
      if mode == "sequential" or mode == "seq" then
        cfg.whisperRotation = "sequential"
        self:Print(L["Whisper rotation: sequential"])
      elseif mode == "random" or mode == "rand" then
        cfg.whisperRotation = "random"
        self:Print(L["Whisper rotation: random"])
      else
        self:Print(L["Usage: /grip templates rotation sequential|random"])
      end
      return
    end

    self:Print(L["Usage: /grip templates list|add <text>|remove <n>|rotation sequential|random"])
    return
  end

  if cmd == "clear" then
    if IsGhostLocked() then PrintGhostLocked() return end
    GRIPDB_CHAR.potential = GRIPDB_CHAR.potential or {}
    wipe(GRIPDB_CHAR.potential)

    wipe(state.whisperQueue)
    wipe(state.pendingWhisper)
    wipe(state.pendingInvite)

    self:Print(L["Cleared Potential list."])
    self:UpdateUI()
    return
  end

  if cmd == "status" then
    local potCount = self:Count(GRIPDB_CHAR.potential)
    local blTemp = self:Count(GRIPDB.blacklist)
    local blPerm = self:Count(GRIPDB.blacklistPerm)
    local optOutCount = 0
    local noResponseCount = 0
    if type(GRIPDB.blacklistPerm) == "table" then
      for _, entry in pairs(GRIPDB.blacklistPerm) do
        if type(entry) == "table" then
          if entry.reason == "opt-out" then
            optOutCount = optOutCount + 1
          elseif entry.reason == "no-response" then
            noResponseCount = noResponseCount + 1
          end
        end
      end
    end
    self:Print((L["Potential: %d, WhoQueue: %d/%d, PostQueue: %d"]):format(
      potCount, (state.whoIndex - 1), #state.whoQueue, #state.postQueue))
    self:Print((L["  Blacklist: %d perm, %d temp"]):format(blPerm, blTemp))
    if optOutCount > 0 or noResponseCount > 0 then
      self:Print((L["  Perm breakdown: %d opt-out, %d no-response, %d other"]):format(
        optOutCount, noResponseCount, blPerm - optOutCount - noResponseCount))
    end
    local sent, cap = self:GetWhisperCapStatus()
    if cap > 0 then
      self:Print((L["  Whispers today: %d/%d"]):format(sent, cap))
    else
      self:Print((L["  Whispers today: %d (no cap)"]):format(sent))
    end
    local tplCount = type(GRIPDB_CHAR.config.whisperMessages) == "table" and #GRIPDB_CHAR.config.whisperMessages or 0
    self:Print((L["  Templates: %d (%s)"]):format(tplCount, GRIPDB_CHAR.config.whisperRotation or "sequential"))
    self:Print((L["  Sound: %s"]):format(GRIPDB_CHAR.config.soundEnabled and L["ON"] or L["OFF"]))
    -- Campaign cooldown status
    local cfg_s = GRIPDB_CHAR.config
    if cfg_s.campaignCooldownEnabled then
      if state.campaignActivityStart then
        local elapsed = math.floor((time() - state.campaignActivityStart) / 60)
        local threshold = cfg_s.campaignCooldownMinutes or 30
        self:Print((L["  Campaign: %d min active (%d actions), warning at %d min"]):format(
          elapsed, state.campaignActionCount or 0, threshold))
      else
        self:Print((L["  Campaign cooldown: enabled (%d min threshold)"]):format(cfg_s.campaignCooldownMinutes or 30))
      end
    else
      self:Print(L["  Campaign cooldown: disabled"])
    end
    -- Ghost Mode status
    if GRIP.Ghost:IsSessionActive() then
      local elapsed = math.floor((time() - (state.ghost.sessionStartedAt or time())) / 60)
      self:Print((L["  Ghost Mode: ACTIVE (%d min, %d actions, %d queued)"]):format(
        elapsed, state.ghost.sessionActionCount or 0, GRIP.Ghost:GetNumPending()))
    elseif cfg_s.ghostModeEnabled then
      self:Print(L["  Ghost Mode: enabled (no active session)"])
    end
    -- Sync status
    if _G.GRIPDB then
      self:Print((L["  Sync: %s"]):format(GRIPDB.syncEnabled ~= false and L["ON"] or L["OFF"]))
    end
    self:Debug("Status requested.")
    return
  end

  if cmd == "perf" then
    if not Enum or not Enum.AddOnProfilerMetric or not C_AddOnProfiler or not C_AddOnProfiler.GetAddOnMetric then
      self:Print(L["C_AddOnProfiler not available (requires WoW 11.0.7+)."])
      return
    end
    local E = Enum.AddOnProfilerMetric
    local function getMetric(metric)
      local ok, val = pcall(C_AddOnProfiler.GetAddOnMetric, ADDON_NAME, metric)
      return (ok and val) or nil
    end
    local function fmtTime(val)
      return val and ("%.3f ms"):format(val) or L["N/A"]
    end
    local function fmtCount(val)
      return val and math.floor(val) or 0
    end
    self:Print(L["GRIP Performance Baseline:"])
    self:Print((L["  Session avg: %s | Recent avg: %s"]):format(
      fmtTime(getMetric(E.SessionAverageTime)),
      fmtTime(getMetric(E.RecentAverageTime))))
    self:Print((L["  Peak: %s | Last tick: %s"]):format(
      fmtTime(getMetric(E.PeakTime)),
      fmtTime(getMetric(E.LastTime))))
    self:Print((L["  Ticks >1ms: %d | >5ms: %d | >50ms: %d"]):format(
      fmtCount(getMetric(E.CountTimeOver1Ms)),
      fmtCount(getMetric(E.CountTimeOver5Ms)),
      fmtCount(getMetric(E.CountTimeOver50Ms))))
    -- Extended detail with /grip perf all
    local sub = (rest or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    if sub == "all" then
      self:Print((L["  Ticks >10ms: %d | >100ms: %d | >500ms: %d | >1000ms: %d"]):format(
        fmtCount(getMetric(E.CountTimeOver10Ms)),
        fmtCount(getMetric(E.CountTimeOver100Ms)),
        fmtCount(getMetric(E.CountTimeOver500Ms)),
        fmtCount(getMetric(E.CountTimeOver1000Ms))))
    end
    -- Encounter avg (only if meaningful)
    local encAvg = getMetric(E.EncounterAverageTime)
    if encAvg and encAvg > 0 then
      self:Print((L["  Encounter avg: %s"]):format(fmtTime(encAvg)))
    end
    -- Memory usage
    UpdateAddOnMemoryUsage()
    local memKB = GetAddOnMemoryUsage(ADDON_NAME)
    local memStr
    if memKB and memKB >= 1024 then
      memStr = ("%.2f MB"):format(memKB / 1024)
    elseif memKB then
      memStr = ("%.1f KB"):format(memKB)
    else
      memStr = L["N/A"]
    end
    self:Print((L["  Memory: %s"]):format(memStr))
    return
  end

  if cmd == "stats" then
    local sub = (rest or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    if sub == "reset" then
      if _G.GRIPDB_CHAR and GRIPDB_CHAR.stats then
        GRIPDB_CHAR.stats = { days = {}, today = nil }
        self:Print(L["Stats reset."])
        self:UpdateUI()
      end
      return
    end
    -- Determine time window
    local n, label
    if sub == "7d" or sub == "week" then
      n, label = 7, L["Last 7 Days"]
    elseif sub == "30d" or sub == "month" then
      n, label = 30, L["Last 30 Days"]
    else
      n, label = 1, L["Today"]
    end
    self:EnsureStatsToday()
    local stats = GRIPDB_CHAR.stats
    if not stats then
      self:Print(L["No stats data available."])
      return
    end
    local data
    local keys = {"whispers","invites","accepted","declined","optOuts","posts","scans"}
    if n == 1 then
      data = {}
      local t = stats.today
      if t and type(t) == "table" then
        for _, k in ipairs(keys) do data[k] = t[k] or 0 end
      else
        for _, k in ipairs(keys) do data[k] = 0 end
      end
    else
      data = {}
      for _, k in ipairs(keys) do data[k] = 0 end
      -- Include today
      if stats.today and type(stats.today) == "table" then
        for _, k in ipairs(keys) do data[k] = (stats.today[k] or 0) end
      end
      -- Include history (last n-1 entries)
      if stats.days and type(stats.days) == "table" then
        local historyCount = n - 1
        local startIdx = math.max(1, #stats.days - historyCount + 1)
        for i = startIdx, #stats.days do
          local day = stats.days[i]
          if day and type(day) == "table" then
            for _, k in ipairs(keys) do data[k] = data[k] + (day[k] or 0) end
          end
        end
      end
    end
    self:Print(label .. ":")
    self:Print((L["  Whispers: %d | Invites: %d | Accepted: %d | Declined: %d"]):format(
      data.whispers or 0, data.invites or 0, data.accepted or 0, data.declined or 0))
    self:Print((L["  Opt-Outs: %d | Posts: %d | Scans: %d"]):format(
      data.optOuts or 0, data.posts or 0, data.scans or 0))
    local rate = (data.whispers and data.whispers > 0)
      and ("%.1f%%"):format(((data.accepted or 0) / data.whispers) * 100)
      or L["N/A"]
    self:Print((L["  Accept Rate: %s"]):format(rate))
    return
  end

  if cmd == "link" then
    local guildName = self:GetGuildName()
    if guildName == "" then
      self:Print(L["Not in a guild (or guild data not loaded yet)."])
      return
    end
    self:Print(L["Guild: "] .. guildName)

    local clubId
    if C_Club and C_Club.GetGuildClubId then
      local ok, cid = pcall(C_Club.GetGuildClubId)
      if ok and cid then clubId = cid end
    end
    self:Print(L["ClubId: "] .. (clubId and tostring(clubId) or "nil"))

    -- Path 1: C_ClubFinder API
    local p1 = "nil"
    if clubId and C_ClubFinder and C_ClubFinder.GetRecruitingClubInfoFromClubID then
      local ok, info = pcall(C_ClubFinder.GetRecruitingClubInfoFromClubID, clubId)
      if ok and info and info.clubFinderGUID then
        p1 = info.clubFinderGUID
      end
    end
    self:Print("Path 1 (C_ClubFinder): " .. p1)

    -- Path 2: ClubFinderGetCurrentClubListingInfo
    local p2 = "nil"
    if clubId and ClubFinderGetCurrentClubListingInfo then
      local ok, listing = pcall(ClubFinderGetCurrentClubListingInfo, clubId)
      if ok and listing and listing.clubFinderGUID then
        p2 = listing.clubFinderGUID
      end
    end
    self:Print("Path 2 (ClubListingInfo): " .. p2)

    -- Path 3: SV cache
    local p3 = "nil"
    if _G.GRIPDB_CHAR and GRIPDB_CHAR._guildLinkCache and GRIPDB_CHAR._guildLinkCache.guid then
      p3 = GRIPDB_CHAR._guildLinkCache.guid .. " (age: " ..
        math.floor(time() - (GRIPDB_CHAR._guildLinkCache.at or 0)) .. "s)"
    end
    self:Print("Path 3 (SV cache): " .. p3)

    -- Final resolved link
    local link = self:GetGuildFinderLink() or ""
    if link ~= "" then
      self:Print(L["Link: "] .. link)
      self:Print(L["Link bytes: "] .. #link)
    else
      self:Print(L["Link: "] .. "(none)")
      -- Try to prime the pump
      if clubId and C_ClubFinder and C_ClubFinder.RequestPostingInformationFromClubId then
        pcall(C_ClubFinder.RequestPostingInformationFromClubId, clubId)
        self:Print(L["Requested posting data. Try /grip link again in a few seconds."])
      else
        self:Print(L["Open your Communities window once, then try again."])
      end
    end
    return
  end

  if cmd == "zones" then
    local sub, subrest = SplitArgs(rest)
    sub = (sub or ""):lower()

    if sub == "" or sub == "diag" then
      if self.PrintZoneDiag then
        self:PrintZoneDiag()
      else
        self:Print(L["Zones diagnostics unavailable."])
      end
      return
    end

    if sub == "export" then
      if self.ExportZonesToSavedVars then
        self:ExportZonesToSavedVars()
      else
        self:Print(L["Zones export unavailable."])
      end
      return
    end

    if sub == "deep" then
      local v = (subrest or "")
      local low = v:lower()

      if low == "stop" or low == "cancel" then
        if self.StopDeepZoneScan then
          self:StopDeepZoneScan()
        else
          self:Print(L["Zone deep scan unavailable."])
        end
      else
        local maxID = tonumber(v)
        if self.StartDeepZoneScan then
          self:StartDeepZoneScan(maxID)
        else
          self:Print(L["Zone deep scan unavailable."])
        end
      end
      return
    end

    if sub == "reseed" or sub == "rebuild" then
      if self.ReseedZones then
        local newCount, oldCount, stats = self:ReseedZones()
        if newCount and newCount > 0 then
          self:Print((L["Zones reseeded: %d (was %d)"]):format(newCount, oldCount or 0))
          self:Debug("Zones reseeded:", newCount, "was", oldCount or 0, "method", stats and stats.method)
          self:UpdateUI()
        else
          self:Print(L["Zones reseed failed (no zones)."])
        end
      else
        self:Print(L["Zones reseed unavailable."])
      end
      return
    end

    self:Print(L["Usage: /grip zones diag|reseed|deep [maxMapID]|deep stop|export"])
    return
  end

  if cmd == "debug" then
    local sub, subrest = SplitArgs(rest)
    subrest = GRIP:Trim(subrest)

    -- Back-compat: "/grip debug on|off"
    if sub == "on" or sub == "off" or sub == "1" or sub == "0"
        or sub == "true" or sub == "false" or sub == "yes" or sub == "no" then
      local val = sub
      GRIPDB_CHAR.config.debug = (val == "on" or val == "1" or val == "true" or val == "yes")
      self:Print(L["Debug: "] .. (GRIPDB_CHAR.config.debug and L["ON"] or L["OFF"]))

      if GRIPDB_CHAR.config.debug then
        -- Auto-create Debug chat window if it doesn't exist
        if self.EnsureDebugChatWindow then
          self:EnsureDebugChatWindow()
        end
        self:ResolveDebugFrame(true)
        -- Also enable capture automatically when debug is turned on
        GRIPDB_CHAR.config.debugCapture = true
        GRIPDB_CHAR.config.debugPersist = true
        if self.UpdateDebugCapture then self:UpdateDebugCapture() end
        self:Debug("Debug enabled. Window=", GRIPDB_CHAR.config.debugWindowName,
          "verbosity=", GRIPDB_CHAR.config.debugVerbosity)
      else
        -- Disable capture when debug is turned off
        GRIPDB_CHAR.config.debugCapture = false
        GRIPDB_CHAR.config.debugPersist = false
      end
      return
    end

    if sub == "" then
      PrintDebugUsage()
      return
    end

    if sub == "dump" then
      DumpPersisted(tonumber(subrest) or DUMP_LINES_DEFAULT)
      return
    end

    if sub == "copy" then
      if self.ShowDebugCopyFrame then
        self:ShowDebugCopyFrame(tonumber(subrest) or DUMP_LINES_MAX)
      else
        self:Print(L["Debug copy frame unavailable."])
      end
      return
    end

    if sub == "clear" then
      ClearPersisted()
      return
    end

    if sub == "capture" then
      local v, maybeMax = SplitArgs(subrest)
      if v == "" then
        PrintDebugUsage()
        return
      end

      local on = BoolFromWord(v)

      -- Keep alias keys in sync (some modules read debugCapture; some read debugPersist)
      GRIPDB_CHAR.config.debugPersist = on and true or false
      GRIPDB_CHAR.config.debugCapture = on and true or false

      local nMax = tonumber(maybeMax)
      if nMax then
        local clamped = self:Clamp(nMax, DEBUG_PERSIST_MIN, DEBUG_PERSIST_MAX)
        GRIPDB_CHAR.config.debugPersistMax = clamped
        GRIPDB_CHAR.config.debugCaptureMax = clamped
      else
        -- If one exists, mirror it so they stay in sync
        local m = tonumber(GRIPDB_CHAR.config.debugPersistMax or GRIPDB_CHAR.config.debugCaptureMax)
        if m then
          GRIPDB_CHAR.config.debugPersistMax = m
          GRIPDB_CHAR.config.debugCaptureMax = m
        end
      end

      self:Print(L["Debug capture: "] .. (GRIPDB_CHAR.config.debugPersist and L["ON"] or L["OFF"]))

      if self.UpdateDebugCapture then
        self:UpdateDebugCapture()
      end

      DebugStatus()
      return
    end

    if sub == "status" then
      DebugStatus()
      return
    end

    PrintDebugUsage()
    return
  end

  if cmd == "set" then
    local key, val = SplitArgs(rest)
    if key == "" then
      self:Print(L["Usage: /grip set <key> <value>"])
      return
    end

    local cfg = GRIPDB_CHAR.config

    if key == "whisper" then
      cfg.whisperMessage = (val ~= "" and val) or cfg.whisperMessage
      cfg.whisperMessages = cfg.whisperMessages or { cfg.whisperMessage }
      cfg.whisperMessages[1] = cfg.whisperMessage
      self:Print(L["Whisper message set (template #1)."])
      self:Debug("Set whisperMessage.")
      return
    end

    if key == "general" then
      cfg.postMessageGeneral = (val ~= "" and val) or cfg.postMessageGeneral
      self:Print(L["General message set."])
      self:Debug("Set postMessageGeneral.")
      return
    end

    if key == "trade" then
      cfg.postMessageTrade = (val ~= "" and val) or cfg.postMessageTrade
      self:Print(L["Trade message set."])
      self:Debug("Set postMessageTrade.")
      return
    end

    if key == "blacklistdays" then
      local n = tonumber(val)
      if n then
        cfg.blacklistDays = self:Clamp(n, BLACKLIST_DAYS_MIN, BLACKLIST_DAYS_MAX)
        self:Print(L["Blacklist days set to "] .. cfg.blacklistDays)
        self:Debug("Set blacklistDays:", cfg.blacklistDays)
      end
      return
    end

    if key == "interval" then
      local n = tonumber(val)
      if n then
        cfg.postIntervalMinutes = self:Clamp(n, POST_INTERVAL_MIN, POST_INTERVAL_MAX)
        self:Print(L["Post interval set to "] .. cfg.postIntervalMinutes .. L[" minutes."])
        self:Debug("Set postIntervalMinutes:", cfg.postIntervalMinutes)
        self:StartPostScheduler()
      end
      return
    end

    if key == "zoneonly" then
      val = (val or ""):lower()
      cfg.scanZoneOnly = (val == "on" or val == "1" or val == "true" or val == "yes")
      self:Print(L["Zone-only scanning: "] .. (cfg.scanZoneOnly and L["ON"] or L["OFF"]))
      self:Debug("Set scanZoneOnly:", tostring(cfg.scanZoneOnly))
      return
    end

    if key == "levels" then
      local a, b, c = val:match("^(%S+)%s+(%S+)%s+(%S+)")
      a, b, c = tonumber(a), tonumber(b), tonumber(c)
      if a and b and c then
        cfg.scanMinLevel = self:Clamp(a, GRIP.MIN_SCAN_LEVEL, GRIP.MAX_SCAN_LEVEL)
        cfg.scanMaxLevel = self:Clamp(b, cfg.scanMinLevel, GRIP.MAX_SCAN_LEVEL)
        cfg.scanStep = self:Clamp(c, SCAN_STEP_MIN, SCAN_STEP_MAX)
        self:Print((L["Scan levels set: %d-%d step %d"]):format(cfg.scanMinLevel, cfg.scanMaxLevel, cfg.scanStep))
        self:Debug("Set levels:", cfg.scanMinLevel, cfg.scanMaxLevel, cfg.scanStep)
      else
        self:Print(L["Usage: /grip set levels <min> <max> <step>"])
      end
      return
    end

    if key == "debugwindow" then
      if val == "" then
        self:Print(L["Usage: /grip set debugwindow <ChatWindowName>"])
        return
      end
      cfg.debugWindowName = val
      self:Print(L["Debug window name set to: "] .. cfg.debugWindowName)
      self:ResolveDebugFrame(true)
      self:Debug("Debug window changed to:", cfg.debugWindowName)
      return
    end

    if key == "verbosity" then
      local n = tonumber(val)
      if n then
        cfg.debugVerbosity = self:Clamp(n, VERBOSITY_MIN, VERBOSITY_MAX)
        self:Print(L["Debug verbosity set to: "] .. cfg.debugVerbosity)
        self:Debug("Verbosity now:", cfg.debugVerbosity)
      end
      return
    end

    if key == "hidewhispers" or key == "hidewhisper" or key == "suppresswhispers" then
      local low = (val or ""):lower()
      local v = (low == "on" or low == "1" or low == "true" or low == "yes")
      cfg.suppressWhisperEcho = v
      cfg.hideOutgoingWhispers = v
      self:Print(L["Hide outgoing whispers: "] .. (v and L["ON"] or L["OFF"]))
      return
    end

    if key == "dailycap" then
      local n = tonumber(val)
      if not n or n < 0 then
        self:Print(L["Usage: /grip set dailycap <number> (0 = unlimited)"])
        return
      end
      n = math.floor(n)
      GRIPDB_CHAR.config.whisperDailyCap = n
      if n == 0 then
        self:Print(L["Daily whisper cap disabled (unlimited)."])
      else
        self:Print((L["Daily whisper cap set to %d."]):format(n))
      end
      return
    end

    if key == "optout" or key == "optoutdetection" then
      local low = (val or ""):lower()
      local v = (low == "on" or low == "1" or low == "true" or low == "yes")
      GRIPDB_CHAR.config.optOutDetection = v
      self:Print(L["Opt-out detection: "] .. (v and L["ON"] or L["OFF"]))
      return
    end

    if key == "aggressive" then
      local low = (val or ""):lower()
      local v = (low == "on" or low == "1" or low == "true" or low == "yes")
      GRIPDB_CHAR.config.optOutAggressiveEnabled = v
      if self.RebuildOptOutPhrases then self:RebuildOptOutPhrases() end
      self:Print(L["Aggressive opt-out detection: "] .. (v and L["ON"] or L["OFF"]))
      return
    end

    if key == "sound" or key == "sounds" then
      local low = (val or ""):lower()
      local v = (low == "on" or low == "1" or low == "true" or low == "yes")
      GRIPDB_CHAR.config.soundEnabled = v
      self:Print(L["Sound feedback: "] .. (v and L["ON"] or L["OFF"]))
      return
    end

    if key == "ghostmode" then
      local low = (val or ""):lower()
      local v = (low == "on" or low == "1" or low == "true" or low == "yes")
      cfg.ghostModeEnabled = v
      self:Print(L["Ghost Mode: "] .. (v and L["ON (experimental)"] or L["OFF"]))
      return
    end

    if key == "invitefirst" then
      local low = (val or ""):lower()
      local v = (low == "on" or low == "1" or low == "true" or low == "yes")
      cfg.inviteFirst = v
      self:Print(L["Invite-first mode: "] .. (v and L["ON"] or L["OFF"]))
      return
    end

    if key == "riominscore" or key == "riominimum" then
      local n = tonumber(val)
      if not n or n < 0 then
        self:Print(L["Usage: /grip set riominscore <number> (0 = disabled)"])
        return
      end
      n = math.floor(n)
      cfg.rioMinScore = n
      if n == 0 then
        self:Print(L["Raider.IO minimum score filter disabled."])
      else
        self:Print((L["Raider.IO minimum M+ score set to %d."]):format(n))
      end
      self:UpdateUI()
      return
    end

    if key == "riocolumn" then
      local low = (val or ""):lower()
      local v = (low == "on" or low == "1" or low == "true" or low == "yes")
      cfg.rioShowColumn = v
      self:Print(L["M+ score column: "] .. (v and L["ON"] or L["OFF"]))
      self:UpdateUI()
      return
    end

    if key == "cooldown" then
      if val == "off" then
        cfg.campaignCooldownEnabled = false
        self:Print(L["Campaign cooldown disabled."])
      elseif val == "on" then
        cfg.campaignCooldownEnabled = true
        self:Print((L["Campaign cooldown enabled (%d min)."]):format(cfg.campaignCooldownMinutes or 30))
      else
        local n = tonumber(val)
        if n and n >= COOLDOWN_MIN and n <= COOLDOWN_MAX then
          cfg.campaignCooldownMinutes = n
          cfg.campaignCooldownEnabled = true
          self:Print((L["Campaign cooldown set to %d minutes."]):format(n))
        elseif n and n == 0 then
          cfg.campaignCooldownEnabled = false
          self:Print(L["Campaign cooldown disabled."])
        else
          self:Print((L["Usage: /grip set cooldown <%d-%d|on|off>"]):format(COOLDOWN_MIN, COOLDOWN_MAX))
        end
      end
      return
    end

    self:Print((L["Unknown setting key: %s (use /grip help)"]):format(key))
    return
  end

  self:Print(L["Unknown command. Use /grip help"])
end

function GRIP:RegisterSlashCommands()
  SLASH_GRIP1 = "/grip"
  SlashCmdList["GRIP"] = function(msg)
    GRIP:HandleSlash(msg)
  end
end