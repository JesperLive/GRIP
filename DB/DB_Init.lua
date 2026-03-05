-- GRIP: DB Init
-- SavedVariables defaults, EnsureDB (account + per-char), seeding, schema migration.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, ipairs, pcall, wipe = pairs, ipairs, pcall, wipe
local format = string.format
local tremove, tsort = table.remove, table.sort
local time, date = time, date

-- WoW API
local GetNumClasses = GetNumClasses
local GetRealZoneText = GetRealZoneText
local C_CreatureInfo = C_CreatureInfo
local C_DateAndTime = C_DateAndTime

local U = GRIP.DBUtil

-- Schema versions
local SCHEMA_VERSION_ACCOUNT = 2   -- bump from implicit "1" (pre-split)
local SCHEMA_VERSION_CHAR = 1

-- =========================================================================
-- Account-wide defaults (GRIPDB — shared across all characters)
-- =========================================================================
local DEFAULT_DB_ACCOUNT = {
  -- Temp blacklist: [fullName] = expiryEpochSeconds
  blacklist = {},

  -- Perm blacklist: [fullName] = { at=epoch, reason="..." }
  blacklistPerm = {},

  -- Shared counters (tracks TARGET player behavior, not per-alt)
  counters = {
    noResponse = {},   -- [fullName] = count
  },

  -- Officer blacklist sync (FE4)
  syncEnabled = true,
  lastSyncAt = 0,

  schemaVersion = SCHEMA_VERSION_ACCOUNT,
}

-- =========================================================================
-- Per-character defaults (GRIPDB_CHAR — isolated per character)
-- =========================================================================
local DEFAULT_DB_CHAR = {
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
    whisperMessage = "Hey {player}! We're recruiting for {guild}. Interested? \xF0\x9F\x99\x82 {guildlink}",
    whisperMessages = {},
    whisperRotation = "sequential",
    whisperDelay = 3.0,

    -- Optional: hide outgoing whisper echo lines
    suppressWhisperEcho = false,

    -- Back-compat alias used by Slash.lua
    hideOutgoingWhispers = false,

    -- Invite settings
    inviteEnabled = true,
    blacklistDays = 14,
    -- Invite-first mode: send invite before whisper (safer)
    inviteFirst = false,

    -- Trade/General posts (queued; click to send)
    postEnabled = true,
    postIntervalMinutes = 20,
    postMessageGeneral = "{guild} recruiting! Friendly, active, and helpful. Whisper me for info \xF0\x9F\x99\x82 {guildlink}",
    postMessageTrade = "{guild} recruiting! PvE/PvP/social \xe2\x80\x93 whisper for details \xF0\x9F\x99\x82 {guildlink}",
    postQueueMax = 20,

    -- Daily whisper cap (0 = unlimited)
    whisperDailyCap = 500,

    -- Auto-blacklist candidates who reply with opt-out phrases
    optOutDetection = true,
    optOutLanguages = {"en"},
    optOutAggressiveEnabled = false,

    -- Sound feedback
    soundEnabled = true,
    soundWhisperDone = true,
    soundInviteAccepted = true,
    soundScanComplete = false,
    soundCapWarning = true,

    -- Campaign cooldown (session fatigue protection)
    campaignCooldownEnabled = true,
    campaignCooldownMinutes = 30,
    campaignGapResetMinutes = 5,
    campaignHardPauseEnabled = true,

    -- Raider.IO integration (FE3)
    rioMinScore = 0,          -- min M+ score filter (0 = disabled)
    rioShowColumn = true,     -- show M+ column in potential list

    -- Ghost Mode
    ghostModeEnabled = false,
    ghostModeMinInterval = 0.5,
    ghostModeMaxQueue = 50,
    ghostModeQueueAll = false,
    ghostSessionMaxMinutes = 60,
    ghostCooldownMinutes = 10,
    ghostCooldownUntil = 0,

    -- Safety throttles
    minWhoInterval = 15,
    minPostInterval = 8,

    -- Debug logging
    debug = false,
    debugVerbosity = 2,
    debugWindowName = "Debug",
    debugMirrorPrint = true,

    -- Persist debug lines to SavedVariables (WTF) for easy copy/paste
    debugPersist = false,
    debugPersistMax = 800,

    -- Back-compat aliases
    debugCapture = false,
    debugCaptureMax = 800,

    -- Execution gate diagnostics (opt-in)
    traceExecutionGate = false,

    -- Onboarding overlay dismissed flag
    _onboardingDismissed = false,
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

  -- Per-character counters (daily cap is per-alt)
  counters = {
    whispersSent = 0,
    whispersSentDate = "",
  },

  -- Persisted debug capture (SavedVariables/WTF)
  debugLog = {
    lines = {},
    dropped = 0,
    lastAt = "",
  },

  -- Recruitment statistics (daily buckets, 30-day rolling window)
  stats = {
    days = {},    -- array of { date, whispers, invites, accepted, declined, optOuts, posts, scans }
    today = nil,  -- populated on first action each day
  },

  schemaVersion = SCHEMA_VERSION_CHAR,
}

GRIP.DEFAULT_DB_ACCOUNT = DEFAULT_DB_ACCOUNT
GRIP.DEFAULT_DB_CHAR = DEFAULT_DB_CHAR

-- =========================================================================
-- Seeding helpers
-- =========================================================================

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

  wipe(list)

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
  local src, method = GRIP:GetBestZonesListForUI()
  if type(src) ~= "table" or #src == 0 then
    -- Fallback: current zone
    local z = (GetRealZoneText and GetRealZoneText()) or ""
    if z ~= "" then
      wipe(list)
      list[1] = z
    end
    return
  end

  local filtered = {}
  for i = 1, #src do
    if GRIP:ShouldIncludeZoneName(src[i]) then
      filtered[#filtered + 1] = src[i]
    end
  end
  filtered = U.SortUnique(filtered)

  wipe(list)
  for i = 1, #filtered do list[i] = filtered[i] end

  -- Append active seasonal zones
  local seasonal = GRIP:GetActiveSeasonalZones()
  for _, z in ipairs(seasonal) do
    U.EnsureInList(list, z)
  end

  GRIP:Debug("SeedZones:", #list, "zones, method=", method)
end

-- =========================================================================
-- Config helpers
-- =========================================================================

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

-- =========================================================================
-- Schema migration helpers
-- =========================================================================

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

-- =========================================================================
-- Account/Character split migration (one-time, idempotent)
-- =========================================================================

function GRIP:MigrateToSplitSV()
  if not _G.GRIPDB then return false end

  -- Already migrated?
  if GRIPDB.schemaVersion and GRIPDB.schemaVersion >= SCHEMA_VERSION_ACCOUNT then
    return false
  end

  -- Fresh install: no old config to migrate
  if not GRIPDB.config then
    GRIPDB.schemaVersion = SCHEMA_VERSION_ACCOUNT
    return false
  end

  -- Old combined GRIPDB detected — split into account + per-char
  if not _G.GRIPDB_CHAR then _G.GRIPDB_CHAR = {} end
  local char = GRIPDB_CHAR

  -- Move per-char data (only if target doesn't already have it)
  if not char.config then char.config = GRIPDB.config end
  if not char.potential then char.potential = GRIPDB.potential end
  if not char.filters then char.filters = GRIPDB.filters end
  if not char.lists then char.lists = GRIPDB.lists end
  if not char.minimap then char.minimap = GRIPDB.minimap end
  if not char.debugLog then char.debugLog = GRIPDB.debugLog end

  -- Move per-char counters
  char.counters = char.counters or {}
  if char.counters.whispersSent == nil then
    char.counters.whispersSent = (GRIPDB.counters and GRIPDB.counters.whispersSent) or 0
  end
  if char.counters.whispersSentDate == nil then
    char.counters.whispersSentDate = (GRIPDB.counters and GRIPDB.counters.whispersSentDate) or ""
  end

  -- Clean per-char keys from account table
  GRIPDB.config = nil
  GRIPDB.potential = nil
  GRIPDB.filters = nil
  GRIPDB.lists = nil
  GRIPDB.minimap = nil
  GRIPDB.debugLog = nil

  -- Clean per-char counters from account table (keep noResponse — it's shared)
  if GRIPDB.counters then
    GRIPDB.counters.whispersSent = nil
    GRIPDB.counters.whispersSentDate = nil
  end

  GRIPDB.schemaVersion = SCHEMA_VERSION_ACCOUNT
  char.schemaVersion = SCHEMA_VERSION_CHAR

  if self.Debug then
    self:Debug("MigrateToSplitSV: completed GRIPDB/GRIPDB_CHAR split")
  end

  return true
end

-- =========================================================================
-- EnsureDB — initializes both account-wide and per-character tables
-- =========================================================================

function GRIP:EnsureDB()
  -- Run one-time migration first (idempotent)
  self:MigrateToSplitSV()

  -- === Account-wide table (GRIPDB) ===
  if not _G.GRIPDB then _G.GRIPDB = {} end
  U.Merge(GRIPDB, DEFAULT_DB_ACCOUNT)

  if type(GRIPDB.blacklist) ~= "table" then GRIPDB.blacklist = {} end
  if type(GRIPDB.blacklistPerm) ~= "table" then GRIPDB.blacklistPerm = {} end
  if type(GRIPDB.counters) ~= "table" then GRIPDB.counters = { noResponse = {} } end
  if type(GRIPDB.counters.noResponse) ~= "table" then GRIPDB.counters.noResponse = {} end

  -- Sync defaults (FE4)
  if type(GRIPDB.syncEnabled) ~= "boolean" then GRIPDB.syncEnabled = true end
  if type(GRIPDB.lastSyncAt) ~= "number" then GRIPDB.lastSyncAt = 0 end

  -- Migrate legacy blacklist string values to blacklistPerm
  MigrateLegacyBlacklistStrings(self)

  -- === Per-character table (GRIPDB_CHAR) ===
  if not _G.GRIPDB_CHAR then _G.GRIPDB_CHAR = {} end
  U.Merge(GRIPDB_CHAR, DEFAULT_DB_CHAR)

  if type(GRIPDB_CHAR.potential) ~= "table" then GRIPDB_CHAR.potential = {} end

  -- Per-char counters
  if type(GRIPDB_CHAR.counters) ~= "table" then
    GRIPDB_CHAR.counters = { whispersSent = 0, whispersSentDate = "" }
  end

  -- Reset whisper counter if date has changed
  local ctr = GRIPDB_CHAR.counters
  if type(ctr.whispersSent) ~= "number" then ctr.whispersSent = 0 end
  if type(ctr.whispersSentDate) ~= "string" then ctr.whispersSentDate = "" end
  local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime()
  local today
  if t and t.year and t.month and t.monthDay then
    today = ("%04d-%02d-%02d"):format(t.year, t.month, t.monthDay)
  else
    today = date("%Y-%m-%d")
  end
  if ctr.whispersSentDate ~= today then
    ctr.whispersSent = 0
    ctr.whispersSentDate = today
  end

  -- Debug log
  if type(GRIPDB_CHAR.debugLog) ~= "table" then
    GRIPDB_CHAR.debugLog = { lines = {}, dropped = 0, lastAt = "" }
  end
  if type(GRIPDB_CHAR.debugLog.lines) ~= "table" then GRIPDB_CHAR.debugLog.lines = {} end
  GRIPDB_CHAR.debugLog.dropped = tonumber(GRIPDB_CHAR.debugLog.dropped) or 0
  GRIPDB_CHAR.debugLog.lastAt = GRIPDB_CHAR.debugLog.lastAt or ""

  -- Lists, filters, minimap
  if type(GRIPDB_CHAR.lists) ~= "table" then
    GRIPDB_CHAR.lists = { zones = {}, zonesAll = {}, races = {}, classes = {} }
  end
  if type(GRIPDB_CHAR.filters) ~= "table" then
    GRIPDB_CHAR.filters = { zones = {}, races = {}, classes = {} }
  end
  if type(GRIPDB_CHAR.minimap) ~= "table" then
    GRIPDB_CHAR.minimap = { hide = false, angle = 225 }
  end

  -- Config-specific fixups
  local cfg = GRIPDB_CHAR.config
  if type(cfg.whisperDailyCap) ~= "number" then cfg.whisperDailyCap = DEFAULT_DB_CHAR.config.whisperDailyCap end
  if type(cfg.optOutDetection) ~= "boolean" then cfg.optOutDetection = DEFAULT_DB_CHAR.config.optOutDetection end
  if type(cfg.optOutAggressiveEnabled) ~= "boolean" then cfg.optOutAggressiveEnabled = DEFAULT_DB_CHAR.config.optOutAggressiveEnabled end

  if type(cfg.rioMinScore) ~= "number" then cfg.rioMinScore = DEFAULT_DB_CHAR.config.rioMinScore end
  if type(cfg.rioShowColumn) ~= "boolean" then cfg.rioShowColumn = DEFAULT_DB_CHAR.config.rioShowColumn end

  if type(cfg.soundEnabled) ~= "boolean" then cfg.soundEnabled = DEFAULT_DB_CHAR.config.soundEnabled end
  if type(cfg.soundWhisperDone) ~= "boolean" then cfg.soundWhisperDone = DEFAULT_DB_CHAR.config.soundWhisperDone end
  if type(cfg.soundInviteAccepted) ~= "boolean" then cfg.soundInviteAccepted = DEFAULT_DB_CHAR.config.soundInviteAccepted end
  if type(cfg.soundScanComplete) ~= "boolean" then cfg.soundScanComplete = DEFAULT_DB_CHAR.config.soundScanComplete end
  if type(cfg.soundCapWarning) ~= "boolean" then cfg.soundCapWarning = DEFAULT_DB_CHAR.config.soundCapWarning end

  -- Migrate single whisperMessage → whisperMessages array
  if type(cfg.whisperMessages) ~= "table" or #cfg.whisperMessages == 0 then
    cfg.whisperMessages = { cfg.whisperMessage or DEFAULT_DB_CHAR.config.whisperMessage }
  end
  cfg.whisperMessage = cfg.whisperMessages[1]
  if cfg.whisperRotation ~= "random" then
    cfg.whisperRotation = "sequential"
  end

  -- Defensive cap: max 10 templates
  while type(cfg.whisperMessages) == "table" and #cfg.whisperMessages > 10 do
    table.remove(cfg.whisperMessages)
  end

  NormalizeConfigAliases(cfg)

  -- Seed per-character lists
  SeedClasses(GRIPDB_CHAR.lists.classes)
  SeedRaces(GRIPDB_CHAR.lists.races)
  SeedZones(GRIPDB_CHAR.lists.zones)

  -- Remove excluded zones from per-char lists + selections
  do
    local zones = GRIPDB_CHAR.lists.zones
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

    local fz = GRIPDB_CHAR.filters and GRIPDB_CHAR.filters.zones
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

  U.PruneFilterKeys(GRIPDB_CHAR.filters.classes, GRIPDB_CHAR.lists.classes)
  U.PruneFilterKeys(GRIPDB_CHAR.filters.races, GRIPDB_CHAR.lists.races)

  -- Stats structure
  if type(GRIPDB_CHAR.stats) ~= "table" then
    GRIPDB_CHAR.stats = { days = {}, today = nil }
  end
  if type(GRIPDB_CHAR.stats.days) ~= "table" then
    GRIPDB_CHAR.stats.days = {}
  end

  self:EnsureStatsToday()

  return GRIPDB, GRIPDB_CHAR
end

-- =========================================================================
-- Stats helpers
-- =========================================================================

local STATS_MAX_DAYS = 30

local function GetTodayString()
  local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime()
  if t and t.year and t.month and t.monthDay then
    return ("%04d-%02d-%02d"):format(t.year, t.month, t.monthDay)
  end
  return date("%Y-%m-%d")
end

function GRIP:EnsureStatsToday()
  if not _G.GRIPDB_CHAR or type(GRIPDB_CHAR.stats) ~= "table" then return nil end
  if type(GRIPDB_CHAR.stats.days) ~= "table" then GRIPDB_CHAR.stats.days = {} end

  local today = GetTodayString()
  local st = GRIPDB_CHAR.stats

  if st.today and type(st.today) == "table" and st.today.date == today then
    if type(st.today.hours) ~= "table" then st.today.hours = {} end
    return st.today
  end

  -- Roll over previous day
  if st.today and type(st.today) == "table" and st.today.date and st.today.date ~= today then
    st.days[#st.days + 1] = st.today
  end

  -- Create fresh today
  st.today = {
    date = today,
    whispers = 0, invites = 0, accepted = 0, declined = 0,
    optOuts = 0, posts = 0, scans = 0,
    hours = {},  -- [0..23] = total action count for that hour
  }

  -- Prune to max days (remove oldest from front)
  while #st.days > STATS_MAX_DAYS do
    tremove(st.days, 1)
  end

  return st.today
end

function GRIP:RecordStat(key)
  local t = self:EnsureStatsToday()
  if not t then return end
  t[key] = (t[key] or 0) + 1

  -- Hourly bucketing
  if type(t.hours) ~= "table" then t.hours = {} end
  local ct = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime()
  local h = ct and ct.hour or tonumber(date("%H")) or 0
  t.hours[h] = (t.hours[h] or 0) + 1
end
