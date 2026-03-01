-- GRIP: Slash
-- /grip command handler and all subcommands.

local ADDON_NAME, GRIP = ...
local state = GRIP.state

local function SplitArgs(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local a, b = msg:match("^(%S+)%s*(.*)$")
  return a and a:lower() or "", b or ""
end

local function Trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function GetCfg()
  return (_G.GRIPDB and GRIPDB.config) or nil
end

local function EnsureStateTables()
  state.whoQueue = state.whoQueue or {}
  state.whisperQueue = state.whisperQueue or {}
  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingInvite = state.pendingInvite or {}
  state.postQueue = state.postQueue or {}
end

function GRIP:PrintHelp()
  self:Print("Commands:")
  self:Print("  /grip            - toggle UI")
  self:Print("  /grip build      - rebuild /who queue")
  self:Print("  /grip scan       - send next /who query (requires hardware event)")
  self:Print("  /grip whisper    - start/stop whisper queue")
  self:Print("  /grip invite     - whisper+invite next candidate (requires hardware event)")
  self:Print("  /grip post       - send next queued post (requires hardware event)")
  self:Print("  /grip clear      - clear Potential list")
  self:Print("  /grip status     - print counts")
  self:Print("  /grip permbl list|add|remove|clear   - manage permanent blacklist (ignore list)")
  self:Print("  /grip tracegate on|off|toggle        - execution gate diagnostics (trace mode)")

  self:Print("Debug:")
  self:Print("  /grip debug on|off")
  self:Print("  /grip debug dump [n]        - dump last n persisted lines (if capture enabled)")
  self:Print("  /grip debug copy [n]        - open copyable debug log window (last n lines)")
  self:Print("  /grip debug clear           - clear persisted debug log")
  self:Print("  /grip debug capture on|off [max]  - toggle saving debug lines to SavedVariables (WTF)")
  self:Print("  /grip debug status          - show capture settings + stored counts")

  self:Print("Zones:")
  self:Print("  /grip zones diag    - diagnostics")
  self:Print("  /grip zones reseed  - rebuild zone list (prefers static/zonesAll)")
  self:Print("  /grip zones deep [maxMapID] - deep scan mapIDs into ZonesAll (async)")
  self:Print("  /grip zones deep stop - cancel a running deep scan")
  self:Print("  /grip zones export  - write static zones Lua to SavedVariables for copy/paste")

  self:Print("Minimap:")
  self:Print("  /grip minimap on|off|toggle - minimap button visibility")

  self:Print("Settings:")
  self:Print("  /grip set whisper <message>")
  self:Print("  /grip set general <message>")
  self:Print("  /grip set trade <message>")
  self:Print("  /grip set blacklistdays <n>")
  self:Print("  /grip set interval <minutes>")
  self:Print("  /grip set zoneonly on|off")
  self:Print("  /grip set levels <min> <max> <step>")
  self:Print("  /grip set debugwindow <ChatWindowName>   (default: Debug)")
  self:Print("  /grip set verbosity <1|2|3>              (1=info 2=debug 3=trace)")
  self:Print("  /grip set hidewhispers on|off            (hide outgoing whisper echoes in chat)")
end

local function PrintPermBLUsage()
  GRIP:Print("Usage: /grip permbl list|add <name> [reason]|remove <name>|clear")
end

local function PrintDebugUsage()
  GRIP:Print("Usage: /grip debug on|off | dump [n] | copy [n] | clear | capture on|off [max] | status")
end

local function BoolFromWord(w)
  w = (w or ""):lower()
  return (w == "on" or w == "1" or w == "true" or w == "yes")
end

local function DumpPersisted(n)
  n = tonumber(n) or 50
  n = GRIP:Clamp(n, 1, 200)

  if not GRIP.GetPersistedDebugLines then
    GRIP:Print("Debug dump unavailable (Debug module not wired yet).")
    return
  end

  local lines = GRIP:GetPersistedDebugLines()
  if type(lines) ~= "table" or #lines == 0 then
    GRIP:Print("Debug persisted log is empty (or capture is OFF).")
    return
  end

  local total = #lines
  GRIP:Print(("Debug dump (last %d of %d):"):format(math.min(n, total), total))

  local start = math.max(1, total - n + 1)
  for i = start, total do
    GRIP:Print(lines[i])
  end
end

local function ClearPersisted()
  if not GRIP.ClearPersistedDebugLines then
    GRIP:Print("Debug clear unavailable (Debug module not wired yet).")
    return
  end
  local removed = GRIP:ClearPersistedDebugLines()
  GRIP:Print(("Debug persisted log cleared (%d lines)."):format(tonumber(removed) or 0))
end

local function DebugStatus()
  local cfg = GetCfg() or {}
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
  elseif _G.GRIPDB and GRIPDB.debugLog and GRIPDB.debugLog.dropped then
    dropped = tonumber(GRIPDB.debugLog.dropped) or 0
  end

  GRIP:Print(("Debug capture: %s (max=%d, stored=%d, dropped=%d)"):format(on and "ON" or "OFF", max, stored, dropped))
end

local function TraceGateStatus()
  local cfg = GetCfg()
  local on = (cfg and cfg.traceExecutionGate == true) and true or false
  GRIP:Print("Gate Trace Mode: " .. (on and "ON" or "OFF") .. " (GRIPDB.config.traceExecutionGate)")
end

local function HandleTraceGate(rest)
  local sub = (Trim(rest) or ""):lower()

  if sub == "" then
    TraceGateStatus()
    return
  end

  local cfg = GetCfg()
  if not cfg then
    GRIP:Print("GRIPDB not initialized yet.")
    return
  end

  if sub == "toggle" then
    cfg.traceExecutionGate = not (cfg.traceExecutionGate == true)
    TraceGateStatus()
    return
  end

  if sub == "on" or sub == "off" or sub == "1" or sub == "0" or sub == "true" or sub == "false" or sub == "yes" or sub == "no" then
    cfg.traceExecutionGate = BoolFromWord(sub) and true or false
    TraceGateStatus()
    return
  end

  GRIP:Print("Usage: /grip tracegate on|off|toggle")
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
  if not _G.GRIPDB or not GRIPDB.config then
    self:Print("GRIPDB not initialized yet.")
    return
  end

  if cmd == "tracegate" or cmd == "gatetrace" then
    HandleTraceGate(rest)
    return
  end

  if cmd == "build" then
    self:BuildWhoQueue()
    return
  end

  if cmd == "scan" or cmd == "who" then
    self:SendNextWho()
    return
  end

  if cmd == "whisper" then
    self:StartWhispers()
    return
  end

  if cmd == "invite" then
    self:InviteNext()
    return
  end

  if cmd == "post" then
    self:PostNext()
    return
  end

  if cmd == "permbl" or cmd == "permblacklist" then
    local sub, subrest = SplitArgs(rest)
    subrest = Trim(subrest)

    if sub == "" or sub == "list" then
      local names = self.GetPermanentBlacklistNames and self:GetPermanentBlacklistNames() or {}
      local total = #names
      self:Print(("Permanent blacklist: %d"):format(total))

      local cap = 20
      for i = 1, math.min(total, cap) do
        local n = names[i]
        local e = _G.GRIPDB and GRIPDB.blacklistPerm and GRIPDB.blacklistPerm[n]
        local reason = (type(e) == "table" and e.reason) or (e == true and "permanent") or nil
        if reason and reason ~= "" then
          self:Print(("  - %s (%s)"):format(n, reason))
        else
          self:Print(("  - %s"):format(n))
        end
      end
      if total > cap then
        self:Print(("  ... and %d more"):format(total - cap))
      end
      return
    end

    if sub == "add" then
      local name, reason = SplitArgs(subrest)
      name = Trim(name)
      reason = Trim(reason)
      if name == "" then
        PrintPermBLUsage()
        return
      end
      self:BlacklistPermanent(name, reason ~= "" and reason or "manual")
      self:RemovePotential(name)
      self:Print(("Permanent blacklisted: %s"):format(name))
      self:UpdateUI()
      return
    end

    if sub == "remove" or sub == "del" or sub == "rm" then
      local name = Trim(subrest)
      if name == "" then
        PrintPermBLUsage()
        return
      end
      local ok = self.UnblacklistPermanent and self:UnblacklistPermanent(name)
      if ok then
        self:Print(("Permanent blacklist removed: %s"):format(name))
      else
        self:Print(("Not in permanent blacklist: %s"):format(name))
      end
      self:UpdateUI()
      return
    end

    if sub == "clear" then
      local n = self.ClearPermanentBlacklist and self:ClearPermanentBlacklist() or 0
      self:Print(("Permanent blacklist cleared: %d"):format(n))
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

  if cmd == "clear" then
    GRIPDB.potential = GRIPDB.potential or {}
    wipe(GRIPDB.potential)

    wipe(state.whisperQueue)
    wipe(state.pendingWhisper)
    wipe(state.pendingInvite)

    self:Print("Cleared Potential list.")
    self:UpdateUI()
    return
  end

  if cmd == "status" then
    self:Print(("Potential: %d, Blacklist: %d, WhoQueue: %d/%d, PostQueue: %d"):format(
      self:Count(GRIPDB.potential),
      self:Count(GRIPDB.blacklist),
      (state.whoIndex - 1),
      #state.whoQueue,
      #state.postQueue
    ))
    self:Debug("Status requested.")
    return
  end

  if cmd == "zones" then
    local sub, subrest = SplitArgs(rest)
    sub = (sub or ""):lower()

    if sub == "" or sub == "diag" then
      if self.PrintZoneDiag then
        self:PrintZoneDiag()
      else
        self:Print("Zones diagnostics unavailable.")
      end
      return
    end

    if sub == "export" then
      if self.ExportZonesToSavedVars then
        self:ExportZonesToSavedVars()
      else
        self:Print("Zones export unavailable.")
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
          self:Print("Zone deep scan unavailable.")
        end
      else
        local maxID = tonumber(v)
        if self.StartDeepZoneScan then
          self:StartDeepZoneScan(maxID)
        else
          self:Print("Zone deep scan unavailable.")
        end
      end
      return
    end

    if sub == "reseed" or sub == "rebuild" then
      if self.ReseedZones then
        local newCount, oldCount, stats = self:ReseedZones()
        if newCount and newCount > 0 then
          self:Print(("Zones reseeded: %d (was %d)"):format(newCount, oldCount or 0))
          self:Debug("Zones reseeded:", newCount, "was", oldCount or 0, "method", stats and stats.method)
          self:UpdateUI()
        else
          self:Print("Zones reseed failed (no zones).")
        end
      else
        self:Print("Zones reseed unavailable.")
      end
      return
    end

    self:Print("Usage: /grip zones diag|reseed|deep [maxMapID]|deep stop|export")
    return
  end

  if cmd == "debug" then
    local sub, subrest = SplitArgs(rest)
    subrest = Trim(subrest)

    -- Back-compat: "/grip debug on|off"
    if sub == "on" or sub == "off" or sub == "1" or sub == "0" or sub == "true" or sub == "false" or sub == "yes" or sub == "no" then
      local val = sub
      GRIPDB.config.debug = (val == "on" or val == "1" or val == "true" or val == "yes")
      self:Print("Debug: " .. (GRIPDB.config.debug and "ON" or "OFF"))

      if GRIPDB.config.debug then
        self:ResolveDebugFrame(true)
        self:Debug("Debug enabled. Window=", GRIPDB.config.debugWindowName, "verbosity=", GRIPDB.config.debugVerbosity)
      end
      return
    end

    if sub == "" then
      PrintDebugUsage()
      return
    end

    if sub == "dump" then
      DumpPersisted(tonumber(subrest) or 50)
      return
    end

    if sub == "copy" then
      if self.ShowDebugCopyFrame then
        self:ShowDebugCopyFrame(tonumber(subrest) or 200)
      else
        self:Print("Debug copy frame unavailable.")
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
      GRIPDB.config.debugPersist = on and true or false
      GRIPDB.config.debugCapture = on and true or false

      local nMax = tonumber(maybeMax)
      if nMax then
        local clamped = self:Clamp(nMax, 100, 5000)
        GRIPDB.config.debugPersistMax = clamped
        GRIPDB.config.debugCaptureMax = clamped
      else
        -- If one exists, mirror it so they stay in sync
        local m = tonumber(GRIPDB.config.debugPersistMax or GRIPDB.config.debugCaptureMax)
        if m then
          GRIPDB.config.debugPersistMax = m
          GRIPDB.config.debugCaptureMax = m
        end
      end

      self:Print("Debug capture: " .. (GRIPDB.config.debugPersist and "ON" or "OFF"))

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
      self:Print("Usage: /grip set <key> <value>")
      return
    end

    local cfg = GRIPDB.config

    if key == "whisper" then
      cfg.whisperMessage = (val ~= "" and val) or cfg.whisperMessage
      self:Print("Whisper message set.")
      self:Debug("Set whisperMessage.")
      return
    end

    if key == "general" then
      cfg.postMessageGeneral = (val ~= "" and val) or cfg.postMessageGeneral
      self:Print("General message set.")
      self:Debug("Set postMessageGeneral.")
      return
    end

    if key == "trade" then
      cfg.postMessageTrade = (val ~= "" and val) or cfg.postMessageTrade
      self:Print("Trade message set.")
      self:Debug("Set postMessageTrade.")
      return
    end

    if key == "blacklistdays" then
      local n = tonumber(val)
      if n then
        cfg.blacklistDays = self:Clamp(n, 1, 365)
        self:Print("Blacklist days set to " .. cfg.blacklistDays)
        self:Debug("Set blacklistDays:", cfg.blacklistDays)
      end
      return
    end

    if key == "interval" then
      local n = tonumber(val)
      if n then
        cfg.postIntervalMinutes = self:Clamp(n, 1, 180)
        self:Print("Post interval set to " .. cfg.postIntervalMinutes .. " minutes.")
        self:Debug("Set postIntervalMinutes:", cfg.postIntervalMinutes)
        self:StartPostScheduler()
      end
      return
    end

    if key == "zoneonly" then
      val = (val or ""):lower()
      cfg.scanZoneOnly = (val == "on" or val == "1" or val == "true" or val == "yes")
      self:Print("Zone-only scanning: " .. (cfg.scanZoneOnly and "ON" or "OFF"))
      self:Debug("Set scanZoneOnly:", tostring(cfg.scanZoneOnly))
      return
    end

    if key == "levels" then
      local a, b, c = val:match("^(%S+)%s+(%S+)%s+(%S+)")
      a, b, c = tonumber(a), tonumber(b), tonumber(c)
      if a and b and c then
        cfg.scanMinLevel = self:Clamp(a, 1, 100)
        cfg.scanMaxLevel = self:Clamp(b, cfg.scanMinLevel, 100)
        cfg.scanStep = self:Clamp(c, 1, 20)
        self:Print(("Scan levels set: %d-%d step %d"):format(cfg.scanMinLevel, cfg.scanMaxLevel, cfg.scanStep))
        self:Debug("Set levels:", cfg.scanMinLevel, cfg.scanMaxLevel, cfg.scanStep)
      else
        self:Print("Usage: /grip set levels <min> <max> <step>")
      end
      return
    end

    if key == "debugwindow" then
      if val == "" then
        self:Print("Usage: /grip set debugwindow <ChatWindowName>")
        return
      end
      cfg.debugWindowName = val
      cfg._warnedMissingDebugWindow = false
      self:Print("Debug window name set to: " .. cfg.debugWindowName)
      self:ResolveDebugFrame(true)
      self:Debug("Debug window changed to:", cfg.debugWindowName)
      return
    end

    if key == "verbosity" then
      local n = tonumber(val)
      if n then
        cfg.debugVerbosity = self:Clamp(n, 1, 3)
        self:Print("Debug verbosity set to: " .. cfg.debugVerbosity)
        self:Debug("Verbosity now:", cfg.debugVerbosity)
      end
      return
    end

    if key == "hidewhispers" or key == "hidewhisper" or key == "suppresswhispers" then
      local low = (val or ""):lower()
      local v = (low == "on" or low == "1" or low == "true" or low == "yes")
      cfg.suppressWhisperEcho = v
      cfg.hideOutgoingWhispers = v
      self:Print("Hide outgoing whispers: " .. (v and "ON" or "OFF"))
      return
    end

    self:Print(("Unknown setting key: %s (use /grip help)"):format(key))
    return
  end

  self:Print("Unknown command. Use /grip help")
end

function GRIP:RegisterSlashCommands()
  SLASH_GRIP1 = "/grip"
  SlashCmdList["GRIP"] = function(msg)
    GRIP:HandleSlash(msg)
  end
end