-- GRIP: DB Zones
-- Zone gathering, deep scan, exclusion building, export.

local ADDON_NAME, GRIP = ...
local U = GRIP.DBUtil

function GRIP:_TryLoadEncounterJournal()
  if EJ_GetInstanceByIndex then return true end

  if not IsAddOnLoaded or not LoadAddOn then
    return false
  end

  if not IsAddOnLoaded("Blizzard_EncounterJournal") then
    pcall(LoadAddOn, "Blizzard_EncounterJournal")
  end

  if not EJ_GetInstanceByIndex and EncounterJournal_LoadUI then
    pcall(EncounterJournal_LoadUI)
  end

  return EJ_GetInstanceByIndex ~= nil
end

function GRIP:BuildExcludedZoneNames(force)
  if self._excludedZones and not force then
    return self._excludedZones
  end

  local excluded = {}
  local counts = { extra = 0, dungeons = 0, raids = 0, bgs = 0 }

  local function add(name, bucket)
    if type(name) ~= "string" or name == "" then return end
    if excluded[name] then return end
    excluded[name] = true
    if bucket and counts[bucket] ~= nil then
      counts[bucket] = counts[bucket] + 1
    end
  end

  -- Manual exact excludes (mostly scenarios and world PvP zones)
  local extra = GRIP.STATIC_ZONE_EXCLUDE_EXACT
  if type(extra) ~= "table" then
    extra = {
      "Dagger in the Dark",
      "Secrets of Ragefire",
      "Cooking: Impossible",
      "Inconspicuous Crate",
      "Sir Thomas",
      "Town Hall",

      "Ashran",
      "Tol Barad",
      "Tol Barad Peninsula",
      "Wintergrasp",

      -- Arena maps that don't reliably come from BG enumeration
      "Dalaran Sewers",
      "Ruins of Lordaeron",
    }
  end
  for _, name in ipairs(extra) do
    add(name, "extra")
  end

  -- Encounter Journal: dungeons + raids (adds instance names)
  if self:_TryLoadEncounterJournal() then
    local tiers = (EJ_GetNumTiers and EJ_GetNumTiers()) or 1
    if type(tiers) ~= "number" or tiers < 1 then tiers = 1 end

    for tier = 1, tiers do
      if EJ_SelectTier then
        pcall(EJ_SelectTier, tier)
      end

      for i = 1, 500 do
        local instanceID, name = EJ_GetInstanceByIndex(i, false)
        if not instanceID then break end
        add(name, "dungeons")
      end

      for i = 1, 500 do
        local instanceID, name = EJ_GetInstanceByIndex(i, true)
        if not instanceID then break end
        add(name, "raids")
      end
    end
  end

  -- Battlegrounds: queued PvP maps
  if GetNumBattlegroundTypes and GetBattlegroundInfo then
    local n = GetNumBattlegroundTypes() or 0
    for i = 1, n do
      local name = GetBattlegroundInfo(i)
      add(name, "bgs")
    end
  end

  self._excludedZones = excluded
  self._excludedZonesCounts = counts

  if self.IsDebugEnabled and self:IsDebugEnabled(2) then
    local total = 0
    for _ in pairs(excluded) do total = total + 1 end
    self:Debug("Excluded zones built:",
      "total=", total,
      "dungeons=", counts.dungeons,
      "raids=", counts.raids,
      "bgs=", counts.bgs,
      "extra=", counts.extra
    )
  end

  return excluded
end

function GRIP:IsExcludedZoneName(name)
  if type(name) ~= "string" or name == "" then return false end
  local excluded = self._excludedZones or self:BuildExcludedZoneNames(false)
  return excluded and excluded[name] == true
end

-- Simple name filter to avoid obvious junk zones (scenarios/prototypes/disabled/etc).
function GRIP:ShouldIncludeZoneName(name)
  if type(name) ~= "string" or name == "" then return false end

  if self:IsExcludedZoneName(name) then
    return false
  end

  local pats = GRIP.STATIC_ZONE_EXCLUDE_PATTERNS
  if type(pats) ~= "table" or #pats == 0 then
    pats = { "Scenario", "Prototype", " - Disabled", "Arena" }
  end
  for _, pat in ipairs(pats) do
    if type(pat) == "string" and pat ~= "" then
      if name:find(pat, 1, true) then
        return false
      end
    end
  end

  return true
end

-- ---------------------
-- Seasonal zone detection
-- ---------------------

function GRIP:IsDarkmoonFaireActive()
  if not C_DateAndTime or not C_DateAndTime.GetCurrentCalendarTime then return false end
  -- Primary: check if calendar API has told us
  if self.state._seasonalHolidays then
    return self.state._seasonalHolidays["Darkmoon Faire"] == true
  end
  -- Fallback: date math. Faire runs first Sun-Sat of month, portal from Fri before.
  local t = C_DateAndTime.GetCurrentCalendarTime()
  if not t or not t.monthDay or not t.weekday then return false end
  if t.monthDay > 13 then return false end
  local dayOneWeekday = ((t.weekday - ((t.monthDay - 1) % 7) - 1) % 7) + 1
  local firstSunday = ((8 - dayOneWeekday) % 7) + 1
  local portalStart = math.max(1, firstSunday - 2)
  local faireEnd = firstSunday + 6
  return t.monthDay >= portalStart and t.monthDay <= faireEnd
end

function GRIP:IsSeasonalZoneActive(zoneName)
  local info = GRIP.SEASONAL_ZONES and GRIP.SEASONAL_ZONES[zoneName]
  if not info then return false end
  if info.fallback == "darkmoon" then return self:IsDarkmoonFaireActive() end
  return false
end

function GRIP:GetActiveSeasonalZones()
  local out = {}
  if type(GRIP.SEASONAL_ZONES) ~= "table" then return out end
  for name, _ in pairs(GRIP.SEASONAL_ZONES) do
    if self:IsSeasonalZoneActive(name) then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

function GRIP:RefreshSeasonalFromCalendar()
  if not C_Calendar or not C_DateAndTime then return end
  local t = C_DateAndTime.GetCurrentCalendarTime()
  if not t then return end
  local n = C_Calendar.GetNumDayEvents and C_Calendar.GetNumDayEvents(0, t.monthDay) or 0
  local holidays = {}
  for i = 1, n do
    local event = C_Calendar.GetDayEvent and C_Calendar.GetDayEvent(0, t.monthDay, i)
    if event and event.calendarType == "HOLIDAY" and event.title then
      holidays[event.title] = true
    end
  end
  self.state._seasonalHolidays = holidays
  if self:IsDebugEnabled(2) then
    local names = {}
    for k in pairs(holidays) do names[#names + 1] = k end
    self:Debug("Seasonal holidays today:", #names > 0 and table.concat(names, ", ") or "none")
  end
end

-- Root map selection is unreliable on some clients; try player map root as fallback.
function GRIP:GetPlayerMapRoot()
  if not C_Map or not C_Map.GetBestMapForUnit then return nil end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return nil end
  if not C_Map.GetMapInfo then return mapID end
  local info = C_Map.GetMapInfo(mapID)
  if not info then return mapID end
  local parent = info.parentMapID
  while parent and parent ~= 0 do
    local pinfo = C_Map.GetMapInfo(parent)
    if not pinfo then break end
    mapID = parent
    parent = pinfo.parentMapID
  end
  return mapID
end

local function addName(dst, name)
  if type(name) ~= "string" or name == "" then return end
  dst[name] = true
end

local function getChildren(mapID, mapType)
  if not C_Map or not C_Map.GetMapChildrenInfo then return nil end
  local ok, children = pcall(C_Map.GetMapChildrenInfo, mapID, mapType, true)
  if not ok then return nil end
  return children
end

local function getChildrenRoot0(mapType)
  return getChildren(0, mapType)
end

local DUNGEON_MAP_TYPE = Enum.UIMapType and Enum.UIMapType.Dungeon  -- value 4

local function isDungeonMap(mapID)
  if not DUNGEON_MAP_TYPE or not mapID or not C_Map or not C_Map.GetMapInfo then return false end
  local info = C_Map.GetMapInfo(mapID)
  return info and info.mapType == DUNGEON_MAP_TYPE
end

local function markUsed(stats, key)
  stats.used = stats.used or {}
  stats.used[key] = true
end

function GRIP:GatherAllZoneNames(withStats)
  local stats = {
    used = {},
    method = "unknown",
    truncated = false,
    total = 0,
  }

  local names = {}

  -- Try Zone children of root (0). Some clients return nil here.
  local zones = getChildrenRoot0(Enum.UIMapType and Enum.UIMapType.Zone)
  if type(zones) == "table" then
    markUsed(stats, "root0_zone")
    for _, c in ipairs(zones) do
      if c and c.name and not isDungeonMap(c.mapID) and self:ShouldIncludeZoneName(c.name) then
        addName(names, c.name)
      end
    end
  end

  -- Try World/Continent children of root; then walk down for Zones.
  local worldRoots = getChildrenRoot0(Enum.UIMapType and Enum.UIMapType.World)
  local contRoots = getChildrenRoot0(Enum.UIMapType and Enum.UIMapType.Continent)

  local function walkDown(roots, rootKey)
    if type(roots) ~= "table" then return end
    markUsed(stats, rootKey)
    for _, r in ipairs(roots) do
      if r and r.mapID then
        local continents = getChildren(r.mapID, Enum.UIMapType and Enum.UIMapType.Continent)
        local zones2 = getChildren(r.mapID, Enum.UIMapType and Enum.UIMapType.Zone)
        if type(zones2) == "table" then
          for _, z in ipairs(zones2) do
            if z and z.name and not isDungeonMap(z.mapID) and self:ShouldIncludeZoneName(z.name) then
              addName(names, z.name)
            end
          end
        end
        if type(continents) == "table" then
          for _, c in ipairs(continents) do
            if c and c.mapID then
              local zones3 = getChildren(c.mapID, Enum.UIMapType and Enum.UIMapType.Zone)
              if type(zones3) == "table" then
                for _, z in ipairs(zones3) do
                  if z and z.name and not isDungeonMap(z.mapID) and self:ShouldIncludeZoneName(z.name) then
                    addName(names, z.name)
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  walkDown(worldRoots, "world_roots")
  walkDown(contRoots, "continent_roots")

  -- Player root fallback
  if next(names) == nil then
    local root = self:GetPlayerMapRoot()
    if root then
      markUsed(stats, "player_root")
      local zones4 = getChildren(root, Enum.UIMapType and Enum.UIMapType.Zone)
      if type(zones4) == "table" then
        for _, z in ipairs(zones4) do
          if z and z.name and not isDungeonMap(z.mapID) and self:ShouldIncludeZoneName(z.name) then
            addName(names, z.name)
          end
        end
      end
    end
  end

  -- Flatten set -> array
  local out = {}
  for n in pairs(names) do
    out[#out + 1] = n
  end

  local out2 = U.SortUnique(out)
  stats.total = #out2

  -- Derive a method label
  if stats.used.root0_zone then
    stats.method = "root0_zone"
  elseif stats.used.world_roots or stats.used.continent_roots then
    stats.method = "root_children"
  elseif stats.used.player_root then
    stats.method = "player_root"
  else
    stats.method = "empty"
  end

  if stats.truncated then
    stats.method = stats.method .. "_truncated"
  end

  if withStats then return out2, stats end
  return out2
end

-- Prefer shipped static zones (if present), else deep scan, else hierarchy.
-- Appends active seasonal zones to the result.
function GRIP:GetBestZonesListForUI()
  local base, method
  if type(GRIP.STATIC_ZONES) == "table" and #GRIP.STATIC_ZONES > 0 then
    base, method = GRIP.STATIC_ZONES, "static"
  elseif _G.GRIPDB and GRIPDB.lists and type(GRIPDB.lists.zonesAll) == "table" and #GRIPDB.lists.zonesAll > 0 then
    base, method = GRIPDB.lists.zonesAll, "zonesAll"
  else
    local z, stats = self:GatherAllZoneNames(true)
    base, method = z, (stats and stats.method) or "hierarchy"
  end

  -- Append active seasonal zones
  local seasonal = self:GetActiveSeasonalZones()
  if #seasonal > 0 then
    -- Copy base to avoid mutating the original
    local combined = {}
    for i = 1, #base do combined[i] = base[i] end
    for _, z in ipairs(seasonal) do
      combined[#combined + 1] = z
    end
    return combined, method
  end

  return base, method
end

-- Returns ZONES_BY_EXPANSION with active seasonal zones appended as a group.
-- Used by the UI to render expansion-grouped checklists.
function GRIP:GetZonesGroupedForUI()
  local groups = {}
  if type(GRIP.ZONES_BY_EXPANSION) == "table" then
    for _, g in ipairs(GRIP.ZONES_BY_EXPANSION) do
      local filtered = {}
      for _, z in ipairs(g.zones) do
        if self:ShouldIncludeZoneName(z) then
          filtered[#filtered + 1] = z
        end
      end
      if #filtered > 0 then
        groups[#groups + 1] = { name = g.name, zones = filtered }
      end
    end
  end
  local seasonal = self:GetActiveSeasonalZones()
  if #seasonal > 0 then
    groups[#groups + 1] = { name = "Seasonal (active)", zones = seasonal }
  end
  return groups
end

function GRIP:ReseedZones()
  if not _G.GRIPDB or type(GRIPDB.lists) ~= "table" or type(GRIPDB.lists.zones) ~= "table" then
    return 0, 0, nil
  end

  local oldCount = #GRIPDB.lists.zones

  local zones, stats
  if type(GRIPDB.lists.zonesAll) == "table" and #GRIPDB.lists.zonesAll > 0 then
    zones = {}
    for i = 1, #GRIPDB.lists.zonesAll do
      zones[i] = GRIPDB.lists.zonesAll[i]
    end
    stats = { method = "zonesAll", total = #zones }
  else
    zones, stats = self:GatherAllZoneNames(true)
  end

  if type(zones) ~= "table" or #zones == 0 then
    return 0, oldCount, stats
  end

  wipe(GRIPDB.lists.zones)
  for i = 1, #zones do
    GRIPDB.lists.zones[i] = zones[i]
  end

  return #zones, oldCount, stats
end

function GRIP:PrintZoneDiag()
  if not _G.GRIPDB or type(GRIPDB.lists) ~= "table" or type(GRIPDB.lists.zones) ~= "table" then
    self:Print("Zones: saved=0 (no DB yet).")
    return
  end

  local saved = GRIPDB.lists.zones
  local hierarchy, stats = self:GatherAllZoneNames(true)
  local allCount = (type(GRIPDB.lists.zonesAll) == "table" and #GRIPDB.lists.zonesAll) or 0
  local staticCount = (type(GRIP.STATIC_ZONES) == "table" and #GRIP.STATIC_ZONES) or 0

  self:Print(("Zones: saved=%d hierarchy=%d method=%s"):format(#saved, #hierarchy, (stats and stats.method) or "?"))
  if staticCount > 0 then
    self:Print(("Static zones: %d (shipped)"):format(staticCount))
  end
  if allCount > 0 then
    self:Print(("Deep-scan zonesAll: %d (SavedVariables)"):format(allCount))
  end

  local counts = self._excludedZonesCounts or {}
  self:Print(("Excluded zones: dungeons=%d raids=%d bgs=%d extra=%d"):format(
    counts.dungeons or 0, counts.raids or 0, counts.bgs or 0, counts.extra or 0
  ))
end

-- ----------------------------
-- Deep scan (async mapID scan)
-- ----------------------------
local deep = {
  running = false,
  ticker = nil,
  mapID = 1,
  maxMapID = 10000,
  found = {},
  checked = 0,
  startedAt = 0,
}

function GRIP:IsDeepZoneScanRunning()
  return deep.running == true
end

function GRIP:StopDeepZoneScan(silent)
  if deep.ticker then
    deep.ticker:Cancel()
    deep.ticker = nil
  end
  deep.running = false

  if not silent then
    self:Print("Deep scan stopped.")
    self:Debug("Deep scan stopped.")
  end
end

function GRIP:StartDeepZoneScan(maxMapID)
  if self:IsDeepZoneScanRunning() then
    self:Print("Deep scan is already running. Use: /grip zones deep stop")
    return false
  end

  if not C_Map or not C_Map.GetMapInfo then
    self:Print("Deep scan unavailable: C_Map.GetMapInfo missing.")
    return false
  end

  maxMapID = tonumber(maxMapID) or 10000
  maxMapID = self:Clamp(maxMapID, 100, 200000)

  deep.running = true
  deep.mapID = 1
  deep.maxMapID = maxMapID
  deep.found = {}
  deep.checked = 0
  deep.startedAt = GetTime()

  self:Print(("Starting deep scan: mapID 1..%d (async). Use /grip zones deep stop to cancel."):format(maxMapID))
  self:Debug("Deep scan start:", "maxMapID=", maxMapID)

  local perTick = 200
  deep.ticker = C_Timer.NewTicker(0.02, function()
    if not deep.running then return end

    local n = 0
    while n < perTick and deep.mapID <= deep.maxMapID do
      local ok, info = pcall(C_Map.GetMapInfo, deep.mapID)
      deep.checked = deep.checked + 1
      if ok and info and info.name and info.name ~= "" then
        if self:ShouldIncludeZoneName(info.name) then
          deep.found[info.name] = true
        end
      end
      deep.mapID = deep.mapID + 1
      n = n + 1
    end

    if deep.mapID > deep.maxMapID then
      self:StopDeepZoneScan(true)

      local out = {}
      for name in pairs(deep.found) do
        out[#out + 1] = name
      end
      local zones = U.SortUnique(out)

      if _G.GRIPDB and GRIPDB.lists then
        GRIPDB.lists.zonesAll = zones
        GRIPDB.lists.zonesAllCount = #zones
        GRIPDB.lists.zonesAllTime = date("%Y-%m-%d %H:%M:%S")
      end

      self:Print(("Deep scan complete: %d names (checked %d mapIDs)."):format(#zones, deep.checked))
      self:Debug("Deep scan complete:", "#=", #zones, "checked=", deep.checked, "secs=", GetTime() - deep.startedAt)

      self:UpdateUI()
    end
  end)

  return true
end

function GRIP:ExportZonesToSavedVars()
  if not _G.GRIPDB or not GRIPDB.lists then
    self:Print("No DB yet; cannot export.")
    return false
  end

  local src, method = self:GetBestZonesListForUI()
  if type(src) ~= "table" or #src == 0 then
    self:Print("No zones available to export.")
    return false
  end

  local filtered = {}
  for i = 1, #src do
    local n = src[i]
    if self:ShouldIncludeZoneName(n) then
      filtered[#filtered + 1] = n
    end
  end
  filtered = U.SortUnique(filtered)

  local srcLabel = method or "unknown"
  local lines = {}
  lines[#lines + 1] = "-- Paste into Maps_Zones.lua (replacing GRIP.STATIC_ZONES)."
  lines[#lines + 1] = "GRIP.STATIC_ZONES = {"
  for _, name in ipairs(filtered) do
    lines[#lines + 1] = ("  %q,"):format(name)
  end
  lines[#lines + 1] = "}"
  local out = table.concat(lines, "\n")

  GRIPDB.lists.zonesExportLua = out
  GRIPDB.lists.zonesExportCount = #filtered
  GRIPDB.lists.zonesExportSource = srcLabel
  GRIPDB.lists.zonesExportTime = date("%Y-%m-%d %H:%M:%S")

  self:Print(("Zones export written to SavedVariables: zonesExportLua (%d zones from %s)."):format(#filtered, srcLabel))
  self:Debug("Zones export saved:", #filtered, "source", srcLabel)

  return true
end