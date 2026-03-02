-- GRIP: DB Init
-- SavedVariables defaults, EnsureDB, seeding (classes/races/zones), schema migration.

local ADDON_NAME, GRIP = ...
local U = GRIP.DBUtil

local DEFAULT_DB = {
  config = {
    enabled = true,

    -- /who scan settings
    scanMinLevel = 1,
    scanMaxLevel = 90,
    scanStep = 5,
    scanZoneOnly = false,
    suppressWhoUI = true,

    -- Whisper settings
    whisperEnabled = true,
    whisperMessage = "Hey {player}! We're recruiting for {guild}. Interested? 🙂 {guildlink}",
    whisperDelay = 2.5,

    -- Optional: hide outgoing whisper echo lines ("To X: ...") in your chat frame
    -- (CHAT_MSG_WHISPER_INFORM still fires; this is only a visual filter)
    suppressWhisperEcho = false,

    -- Back-compat alias used by Slash.lua
    hideOutgoingWhispers = false,

    -- Invite settings
    inviteEnabled = true,
    blacklistDays = 7,

    -- Trade/General posts (queued; click to send)
    postEnabled = true,
    postIntervalMinutes = 15,
    postMessageGeneral = "{guild} recruiting! Friendly, active, and helpful. Whisper me for info 🙂 {guildlink}",
    postMessageTrade = "{guild} recruiting! PvE/PvP/social – whisper for details 🙂 {guildlink}",
    postQueueMax = 20,

    -- Safety throttles
    minWhoInterval = 15,
    minPostInterval = 8,

    -- Debug logging
    debug = false,
    debugVerbosity = 2,
    debugWindowName = "Debug",
    debugMirrorPrint = true,
    _warnedMissingDebugWindow = false,

    -- Persist debug lines to SavedVariables (WTF) for easy copy/paste
    -- (the Debug module will write to GRIPDB.debugLog when enabled)
    debugPersist = false,
    debugPersistMax = 800,

    -- Back-compat aliases used by some earlier drafts / Slash helpers
    debugCapture = false,
    debugCaptureMax = 800,

    -- Execution gate diagnostics (opt-in)
    traceExecutionGate = false,
  },

  minimap = {
    hide = false,
    angle = 225,
  },

  -- Discovered/seeded values for checkbox lists (UI)
  lists = {
    zones = {},
    zonesAll = {},
    races = {},
    classes = {},
  },

  -- Allowlists (checkbox selections)
  filters = {
    zones = {},
    races = {},
    classes = {},
  },

  potential = {},

  -- Purgeable / expiring blacklist (anti-spam, no-response cooldown, etc.)
  -- [fullName] = expiryEpochSeconds
  blacklist = {},

  -- Permanent blacklist (e.g. "has us on ignore")
  -- [fullName] = true | { at=epoch, reason="..." }
  blacklistPerm = {},

  -- Persistent counters (e.g. no-response escalation)
  counters = {
    -- [fullName] = count
    noResponse = {},
  },

  -- Persisted debug capture (SavedVariables/WTF)
  -- lines: array of strings (already formatted)
  -- dropped: count of lines dropped due to cap
  -- lastAt: last timestamp string written (optional metadata)
  debugLog = {
    lines = {},
    dropped = 0,
    lastAt = "",
  },
}

GRIP.DEFAULT_DB = DEFAULT_DB

local function SeedClasses(list)
  if #list > 0 then return end
  if not (C_CreatureInfo and C_CreatureInfo.GetClassInfo and GetNumClasses) then return end

  for i = 1, GetNumClasses() do
    local info = C_CreatureInfo.GetClassInfo(i)
    if info and info.className and info.className ~= "" then
      local name = info.className
      if name ~= "Adventurer" then
        U.EnsureInList(list, name)
      end
    end
  end

  local sorted = U.SortUnique(list)
  wipe(list)
  for i = 1, #sorted do list[i] = sorted[i] end
end

local PLAYABLE_RACE_IDS = {
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,        -- Core races
  22, 24, 25, 26,                              -- Worgen, Pandaren (3 variants)
  27, 28, 29, 30, 31, 32,                      -- Allied: Nightborne → Kul Tiran
  34, 35, 36, 37,                              -- Allied: Dark Iron → Mechagnome
  52, 70,                                      -- Dracthyr (Alliance, Horde)
  84, 85,                                      -- Earthen (Horde, Alliance)
  86, 91,                                      -- Haranir (2 variants)
}

local function SeedRaces(list)
  if not C_CreatureInfo or not C_CreatureInfo.GetRaceInfo then return end

  for _, id in ipairs(PLAYABLE_RACE_IDS) do
    local info = C_CreatureInfo.GetRaceInfo(id)
    if info and info.raceName and info.raceName ~= "" then
      U.EnsureInList(list, info.raceName)
    end
  end

  local sorted = U.SortUnique(list)
  wipe(list)
  for i = 1, #sorted do list[i] = sorted[i] end
end

local function SeedZones(list)
  if #list > 10 then return end

  local seeded = false
  local src, method = GRIP:GetBestZonesListForUI()
  if type(src) == "table" and #src > 0 then
    local filtered = {}
    for i = 1, #src do
      local n = src[i]
      if GRIP:ShouldIncludeZoneName(n) then
        filtered[#filtered + 1] = n
      end
    end
    filtered = U.SortUnique(filtered)

    if #filtered > 0 then
      wipe(list)
      for i = 1, #filtered do
        list[i] = filtered[i]
      end
      seeded = true
      GRIP:Debug("SeedZones: populated zone list:", #list, "method=", method)
    end
  end

  if not seeded then
    local z = (GetRealZoneText and GetRealZoneText()) or ""
    if z ~= "" then
      U.EnsureInList(list, z)
      local sorted = U.SortUnique(list)
      wipe(list)
      for i = 1, #sorted do list[i] = sorted[i] end
      GRIP:Debug("SeedZones: fallback current zone only:", z)
    end
  end
end

local function ClampPersistMax(n)
  n = tonumber(n) or 800
  if n < 50 then n = 50 end
  if n > 5000 then n = 5000 end
  return n
end

local function NormalizeConfigAliases(cfg)
  if type(cfg) ~= "table" then return end

  -- Whisper echo suppression: keep both keys in sync.
  if cfg.suppressWhisperEcho == nil then
    cfg.suppressWhisperEcho = cfg.hideOutgoingWhispers and true or false
  end
  if cfg.hideOutgoingWhispers == nil then
    cfg.hideOutgoingWhispers = cfg.suppressWhisperEcho and true or false
  end
  local w = cfg.suppressWhisperEcho and true or false
  cfg.suppressWhisperEcho = w
  cfg.hideOutgoingWhispers = w

  -- Debug persistence: keep both keys in sync.
  if cfg.debugPersist == nil then
    cfg.debugPersist = cfg.debugCapture and true or false
  end
  if cfg.debugCapture == nil then
    cfg.debugCapture = cfg.debugPersist and true or false
  end
  local d = cfg.debugPersist and true or false
  cfg.debugPersist = d
  cfg.debugCapture = d

  -- Persist max: keep both keys in sync + clamp
  if cfg.debugPersistMax == nil then
    cfg.debugPersistMax = cfg.debugCaptureMax
  end
  if cfg.debugCaptureMax == nil then
    cfg.debugCaptureMax = cfg.debugPersistMax
  end
  local m = ClampPersistMax(cfg.debugPersistMax or cfg.debugCaptureMax)
  cfg.debugPersistMax = m
  cfg.debugCaptureMax = m

  -- Gate trace: strict boolean
  cfg.traceExecutionGate = (cfg.traceExecutionGate == true) and true or false
end

local function NowEpochSafe(self)
  if self and self.Now then
    local ok, v = pcall(function() return self:Now() end)
    if ok and tonumber(v) then return tonumber(v) end
  end
  if time then
    local ok, v = pcall(time)
    if ok and tonumber(v) then return tonumber(v) end
  end
  return 0
end

local function MigrateLegacyBlacklistStrings(self)
  if not _G.GRIPDB then return end
  if type(GRIPDB.blacklist) ~= "table" then GRIPDB.blacklist = {} end
  if type(GRIPDB.blacklistPerm) ~= "table" then GRIPDB.blacklistPerm = {} end

  local now = NowEpochSafe(self)

  local moved, removedJunk = 0, 0
  local toRemove = {}
  for name, v in pairs(GRIPDB.blacklist) do
    if type(v) == "string" then
      local reason = tostring(v or "")

      local pv = GRIPDB.blacklistPerm[name]
      if pv == nil then
        GRIPDB.blacklistPerm[name] = { at = now, reason = reason }
      elseif pv == true then
        GRIPDB.blacklistPerm[name] = { at = now, reason = (reason ~= "" and reason or "permanent") }
      elseif type(pv) == "table" then
        pv.at = tonumber(pv.at) or now
        pv.reason = tostring(pv.reason or "")
        if (pv.reason == "" or pv.reason == "permanent") and reason ~= "" then
          pv.reason = reason
        end
        GRIPDB.blacklistPerm[name] = pv
      else
        GRIPDB.blacklistPerm[name] = { at = now, reason = reason }
      end

      toRemove[#toRemove + 1] = name
      moved = moved + 1
    elseif type(v) == "number" then
      -- keep numeric expiry entries unchanged
    else
      toRemove[#toRemove + 1] = name
      removedJunk = removedJunk + 1
    end
  end
  for _, name in ipairs(toRemove) do
    GRIPDB.blacklist[name] = nil
  end

  if (moved > 0 or removedJunk > 0) and self and self.Debug then
    self:Debug("SV migrate: blacklist string->perm moved=", moved, "removedJunk=", removedJunk)
  end
end

function GRIP:EnsureDB()
  if not _G.GRIPDB then _G.GRIPDB = {} end
  U.Merge(GRIPDB, DEFAULT_DB)

  if type(GRIPDB.potential) ~= "table" then GRIPDB.potential = {} end
  if type(GRIPDB.blacklist) ~= "table" then GRIPDB.blacklist = {} end
  if type(GRIPDB.blacklistPerm) ~= "table" then GRIPDB.blacklistPerm = {} end

  if type(GRIPDB.counters) ~= "table" then GRIPDB.counters = { noResponse = {} } end
  if type(GRIPDB.counters.noResponse) ~= "table" then GRIPDB.counters.noResponse = {} end

  if type(GRIPDB.debugLog) ~= "table" then GRIPDB.debugLog = { lines = {}, dropped = 0, lastAt = "" } end
  if type(GRIPDB.debugLog.lines) ~= "table" then GRIPDB.debugLog.lines = {} end
  GRIPDB.debugLog.dropped = tonumber(GRIPDB.debugLog.dropped) or 0
  GRIPDB.debugLog.lastAt = GRIPDB.debugLog.lastAt or ""

  if type(GRIPDB.lists) ~= "table" then GRIPDB.lists = { zones = {}, zonesAll = {}, races = {}, classes = {} } end
  if type(GRIPDB.filters) ~= "table" then GRIPDB.filters = { zones = {}, races = {}, classes = {} } end
  if type(GRIPDB.minimap) ~= "table" then GRIPDB.minimap = { hide = false, angle = 225 } end

  NormalizeConfigAliases(GRIPDB.config)

  SeedClasses(GRIPDB.lists.classes)
  SeedRaces(GRIPDB.lists.races)
  SeedZones(GRIPDB.lists.zones)

  -- SV schema alignment: migrate any legacy blacklist string values to blacklistPerm
  MigrateLegacyBlacklistStrings(self)

  -- Remove excluded zones from lists + selections
  do
    local zones = GRIPDB.lists.zones
    if type(zones) == "table" and #zones > 0 then
      local kept = {}
      local removed = 0
      for i = 1, #zones do
        local n2 = zones[i]
        if self:ShouldIncludeZoneName(n2) then
          kept[#kept + 1] = n2
        else
          removed = removed + 1
        end
      end
      if removed > 0 then
        wipe(zones)
        for i = 1, #kept do zones[i] = kept[i] end
        if self.IsDebugEnabled and self:IsDebugEnabled(2) then
          self:Debug("Zones list pruned excluded entries:", removed, "kept=", #zones)
        end
      end
    end

    local fz = GRIPDB.filters and GRIPDB.filters.zones
    if type(fz) == "table" then
      local pruned = 0
      local badKeys = {}
      for k in pairs(fz) do
        if not self:ShouldIncludeZoneName(k) then
          badKeys[#badKeys + 1] = k
        end
      end
      for _, k in ipairs(badKeys) do
        fz[k] = nil
        pruned = pruned + 1
      end
      if pruned > 0 and self.IsDebugEnabled and self:IsDebugEnabled(2) then
        self:Debug("Zone filter selections pruned:", pruned)
      end
    end
  end

  U.PruneFilterKeys(GRIPDB.filters.classes, GRIPDB.lists.classes)
  U.PruneFilterKeys(GRIPDB.filters.races, GRIPDB.lists.races)

  return GRIPDB
end