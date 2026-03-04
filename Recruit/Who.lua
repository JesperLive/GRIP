-- GRIP: Who Scanner
-- /who queue builder, bracket expansion, result ingestion, blacklist enforcement at scan time.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, ipairs, next = pairs, ipairs, next
local wipe, strsplit = wipe, strsplit
local gsub, match, find, lower, format = string.gsub, string.match, string.find, string.lower, string.format
local tinsert, tremove, tsort = table.insert, table.remove, table.sort
local min = math.min

-- WoW API
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local GetNormalizedRealmName = GetNormalizedRealmName
local GetRealZoneText = GetRealZoneText
local C_FriendList = C_FriendList
local C_Timer = C_Timer

local state = GRIP.state

local MIN_WHO_INTERVAL = 15
local WHO_SATURATED = 50

local function HideFriendsWhoUIIfNeeded()
  local cfg = GRIP:GetCfg()
  if not cfg or not cfg.suppressWhoUI then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if FriendsFrame and FriendsFrame.IsShown and FriendsFrame:IsShown() then
    HideUIPanel(FriendsFrame)
  end
end

local function NormalizeWhoCounts(a, b)
  local numWhos = tonumber(a) or 0
  local total = tonumber(b) or 0
  if total > 0 and numWhos > total then
    numWhos, total = total, numWhos
  end
  return numWhos, total
end

local function AnySelected(t)
  if type(t) ~= "table" then return false end
  for _, v in pairs(t) do
    if v == true then return true end
  end
  return false
end

local function StripClassToken(filter)
  if type(filter) ~= "string" then return "" end
  -- Remove:  c-"Some Class"
  filter = filter:gsub("%s+c%-%b\"\"", "")
  -- Normalize whitespace
  filter = filter:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return filter
end

local function GetExpansionClassList()
  if not _G.GRIPDB_CHAR or not GRIPDB_CHAR.lists or type(GRIPDB_CHAR.lists.classes) ~= "table" then
    return nil
  end

  local src = GRIPDB_CHAR.lists.classes
  if #src == 0 then return nil end

  local selected = (GRIPDB_CHAR.filters and GRIPDB_CHAR.filters.classes) or {}
  local hasSel = AnySelected(selected)

  local out = {}
  for _, cls in ipairs(src) do
    if (not hasSel) or (selected[cls] == true) then
      out[#out + 1] = cls
    end
  end

  if #out == 0 then return nil end
  return out
end

local function ThrottlePrint(key, seconds)
  seconds = tonumber(seconds) or 2
  local now = GetTime()
  state._printThrottle = state._printThrottle or {}
  local t = tonumber(state._printThrottle[key]) or 0
  if (now - t) < seconds then
    return false
  end
  state._printThrottle[key] = now
  return true
end

-- Structured context for execution gate diagnostics (trace remains opt-in).
local function GateCtx(phase, extra)
  return GRIP:BuildGateCtx("who", "Recruit/Who", phase, extra)
end

-- ---------- Blacklist enforcement helpers ----------

local function Lower(s)
  if type(s) ~= "string" then return "" end
  return s:lower()
end

-- Centralized blacklist decision:
-- Use the shared "last-line defense" gate so WHO ingestion and purge match the execution pipelines.
local function IsBlacklistedName(fullName)
  fullName = GRIP:Trim(fullName)
  if fullName == "" then return false end
  if type(GRIP) ~= "table" or type(GRIP.BL_ExecutionGate) ~= "function" then
    return false
  end
  local ok = GRIP:BL_ExecutionGate(fullName, GateCtx("blacklist-check"))
  return ok == false
end

local function RemoveFromArrayByName(arr, nameLower)
  if type(arr) ~= "table" then return false end
  local changed = false
  for i = #arr, 1, -1 do
    local v = arr[i]
    local n = v
    if type(v) == "table" then
      n = v.fullName or v.name or v.target or v.player
    end
    if type(n) == "string" and Lower(GRIP:Trim(n)) == nameLower then
      table.remove(arr, i)
      changed = true
    end
  end
  return changed
end

local function RemoveFromMapByName(map, nameLower)
  if type(map) ~= "table" then return false end
  local changed = false
  for k, v in pairs(map) do
    if type(k) == "string" and Lower(GRIP:Trim(k)) == nameLower then
      map[k] = nil
      changed = true
    elseif type(v) == "table" then
      local n = v.fullName or v.name or v.target or v.player
      if type(n) == "string" and Lower(GRIP:Trim(n)) == nameLower then
        map[k] = nil
        changed = true
      end
    elseif type(v) == "string" then
      if Lower(GRIP:Trim(v)) == nameLower then
        map[k] = nil
        changed = true
      end
    end
  end
  return changed
end

local function PurgeCandidateFromPipeline(self, fullName)
  if not _G.GRIPDB_CHAR then return false end
  fullName = GRIP:Trim(fullName)
  if fullName == "" then return false end

  local changed = false
  local nameLower = Lower(fullName)
  local variants = GRIP:BuildNameKeyVariants(fullName)

  -- Remove from Potential (prefer API if present, else direct DB surgery)
  if type(self) == "table" and type(self.RemovePotential) == "function" then
    if self:RemovePotential(fullName) then changed = true end
    for _, k in ipairs(variants) do
      if k ~= fullName then
        local ok = self:RemovePotential(k)
        if ok then changed = true end
      end
    end
  else
    local pot = GRIPDB_CHAR.potential
    if type(pot) == "table" then
      for _, k in ipairs(variants) do
        if pot[k] ~= nil then
          pot[k] = nil
          changed = true
        end
      end
    end
  end

  -- Secondary defense: clear any obvious queued/pending action state (best-effort, nil-safe).
  local s = GRIP.state
  if type(s) == "table" then
    local queueKeys = {
      "whisperQueue", "inviteQueue", "recruitQueue", "actionQueue",
      "pendingWhisper", "pendingInvite", "pendingRecruit", "pendingAction",
      "lastWhisperTarget", "lastInviteTarget", "lastRecruitTarget"
    }

    for _, key in ipairs(queueKeys) do
      local t = s[key]
      if type(t) == "table" then
        if RemoveFromArrayByName(t, nameLower) then changed = true end
        if RemoveFromMapByName(t, nameLower) then changed = true end
      elseif type(t) == "string" then
        if Lower(GRIP:Trim(t)) == nameLower then
          s[key] = nil
          changed = true
        end
      end
    end
  end

  -- Also defensive: DB-level queues (if any exist)
  local dbQueueKeys = { "whisperQueue", "inviteQueue", "recruitQueue", "actionQueue" }
  for _, key in ipairs(dbQueueKeys) do
    local q = GRIPDB_CHAR[key]
    if type(q) == "table" then
      if RemoveFromArrayByName(q, nameLower) then changed = true end
      if RemoveFromMapByName(q, nameLower) then changed = true end
    end
  end

  return changed
end

local function PurgeAllBlacklistedFromPotential(self)
  if not _G.GRIPDB_CHAR then return 0 end
  local pot = GRIPDB_CHAR.potential
  if type(pot) ~= "table" then return 0 end

  local purged = 0

  local toPurge = {}
  for k, v in pairs(pot) do
    local n = k
    if type(v) == "table" then
      n = v.fullName or v.name or v.target or v.player or k
    end
    if type(n) == "string" and n ~= "" and IsBlacklistedName(n) then
      toPurge[#toPurge + 1] = n
    end
  end
  for _, n in ipairs(toPurge) do
    if PurgeCandidateFromPipeline(self, n) then
      purged = purged + 1
    end
  end

  return purged
end

-- ----------------------------------------------------------

function GRIP:MaybeExpandWhoByClass(filter, numWhos, total)
  if type(filter) ~= "string" then return end
  if filter:find('c-"', 1, true) then return end -- already class-filtered

  if (numWhos or 0) < WHO_SATURATED then return end
  if (total or 0) ~= 0 and (total or 0) < WHO_SATURATED then return end

  state._whoExpanded = state._whoExpanded or {}

  local baseKey = StripClassToken(filter)
  if baseKey == "" then return end
  if state._whoExpanded[baseKey] then return end
  state._whoExpanded[baseKey] = true

  local a, b, tail = baseKey:match("^(%d+)%-(%d+)(.*)$")
  if not a or not b then return end
  tail = tail or ""

  local classes = GetExpansionClassList()
  if not classes then return end

  local insertPos = state.whoIndex
  for i = #classes, 1, -1 do
    local cls = classes[i]
    local q = ("%s-%s c-\"%s\"%s"):format(a, b, cls, tail)
    table.insert(state.whoQueue, insertPos, q)
  end

  self:Debug("WHO saturated; expanded by class:", baseKey, "added=", #classes)
end

function GRIP:BuildWhoQueue()
  wipe(state.whoQueue)
  state.whoIndex = 1
  state.pendingWho = nil
  state._whoExpanded = {}

  local cfg = GRIP:GetCfg()
  if not cfg then
    self:Print("Cannot build /who queue: GRIPDB not initialized yet.")
    return
  end

  local minL = self:Clamp(cfg.scanMinLevel or 1, 1, 100)
  local maxL = self:Clamp(cfg.scanMaxLevel or 90, minL, 100)
  local step = self:Clamp(cfg.scanStep or 5, 1, 20)

  local zoneFilter = ""
  if cfg.scanZoneOnly then
    local zone = (GetRealZoneText and GetRealZoneText()) or ""
    if zone ~= "" then
      zoneFilter = (' z-"%s"'):format(zone)
    end
  end

  local l = minL
  while l <= maxL do
    local h = math.min(l + step - 1, maxL)
    state.whoQueue[#state.whoQueue + 1] = ("%d-%d%s"):format(l, h, zoneFilter)
    l = h + 1
  end

  self:Print(("Built /who queue: %d queries (%d-%d, step %d)%s"):format(
    #state.whoQueue, minL, maxL, step, cfg.scanZoneOnly and " + zone" or ""
  ))
  self:Debug("WhoQueue built:", "#=", #state.whoQueue, "min=", minL, "max=", maxL, "step=", step, "zoneOnly=", tostring(cfg.scanZoneOnly))
  self:UpdateUI()
end

function GRIP:SendNextWho()
  local cfg = GRIP:GetCfg()
  if not cfg then
    self:Print("Cannot send /who: GRIPDB not initialized yet.")
    return false
  end

  if not cfg.enabled then
    self:Print("Addon disabled in config.")
    return false
  end

  if not (C_FriendList and C_FriendList.SendWho) then
    self:Print("SendWho API unavailable on this client.")
    return false
  end

  if #state.whoQueue == 0 then
    self:BuildWhoQueue()
  end

  if state.pendingWho then
    if ThrottlePrint("who_waiting", 2.0) then
      self:Print("Waiting for WHO_LIST_UPDATE…")
    end
    return false
  end

  if state.whoIndex > #state.whoQueue then
    state.whoIndex = 1
    self:Print("Who queue wrapped. Starting over.")
  end

  local now = GetTime()
  local minInterval = tonumber(cfg.minWhoInterval) or MIN_WHO_INTERVAL
  if minInterval < MIN_WHO_INTERVAL then
    minInterval = MIN_WHO_INTERVAL
  end

  local elapsed = (now - (state.lastWhoSentAt or 0))
  if elapsed < minInterval then
    if ThrottlePrint("who_interval", 1.5) then
      self:Print(("Please wait %.1fs before sending the next /who."):format(minInterval - elapsed))
    end
    return false
  end

  local filter = state.whoQueue[state.whoIndex]
  state.whoIndex = state.whoIndex + 1

  -- Ghost Mode: queue scan instead of executing directly
  if GRIP.Ghost and GRIP.Ghost:IsSessionActive() then
    state.pendingWho = { filter = filter, sentAt = 0, ghostQueued = true }
    local capturedFilter = filter
    GRIP.Ghost:QueueAction("scan", function()
      if state.pendingWho and state.pendingWho.filter == capturedFilter then
        state.pendingWho.sentAt = GetTime()
        state.pendingWho.ghostQueued = nil
      end
      state.lastWhoSentAt = GetTime()
      if C_FriendList and C_FriendList.SetWhoToUi then
        C_FriendList.SetWhoToUi(true)
      end
      self:Debug("SendWho (ghost):", capturedFilter)
      C_FriendList.SendWho(capturedFilter,
        Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or 1)
      C_Timer.After(10, function()
        if state.pendingWho and state.pendingWho.filter == capturedFilter
           and (GetTime() - state.pendingWho.sentAt) >= 10 then
          self:Debug("WHO timeout (ghost):", capturedFilter)
          state.pendingWho = nil
          self:UpdateUI()
          if GRIP.Ghost and GRIP.Ghost:IsSessionActive() then
            self:SendNextWho()
          end
        end
      end)
    end, { filter = capturedFilter })
    self:Print(("Queued /who (Ghost): %s (%d/%d)"):format(
      filter, state.whoIndex - 1, #state.whoQueue))
    self:UpdateUI()
    return true
  end

  -- Normal (non-ghost) path
  state.lastWhoSentAt = now
  state.pendingWho = { filter = filter, sentAt = now }

  if C_FriendList and C_FriendList.SetWhoToUi then
    C_FriendList.SetWhoToUi(true)
  end

  self:Debug("SendWho:", filter)
  C_FriendList.SendWho(filter, Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or 1)

  C_Timer.After(10, function()
    if state.pendingWho and (GetTime() - state.pendingWho.sentAt) >= 10 then
      self:Debug("WHO timeout:", state.pendingWho.filter)
      state.pendingWho = nil
      self:UpdateUI()
      self:Print("No WHO_LIST_UPDATE received (server throttle?). Try again in a few seconds.")
    end
  end)

  self:Print(("Sent /who: %s (%d/%d)"):format(filter, state.whoIndex - 1, #state.whoQueue))
  self:UpdateUI()
  return true
end

function GRIP:ProcessWhoResults(pending)
  if not (C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo) then
    self:Print("Who results APIs unavailable on this client.")
    return
  end

  local purged = PurgeAllBlacklistedFromPotential(self)
  if purged > 0 then
    self:Debug("Purged blacklisted from Potential:", purged)
  end

  local a, b = C_FriendList.GetNumWhoResults()
  local numWhos, total = NormalizeWhoCounts(a, b)

  self:Debug("ProcessWhoResults:",
    "filter=", pending and pending.filter or "?",
    "numWhos=", numWhos,
    "total=", total
  )

  if pending and pending.filter then
    self:MaybeExpandWhoByClass(pending.filter, numWhos, total)
  end

  local added = 0
  local skippedBlacklisted = 0
  for i = 1, numWhos do
    local w = C_FriendList.GetWhoInfo(i)
    if w and w.fullName then
      local guild = w.fullGuildName
      local unguilded = (guild == nil or guild == "")
      if unguilded then
        local info = {
          fullName = w.fullName,
          level = w.level,
          race = w.raceStr or w.race or "",
          class = w.classStr or w.class or "",
          area = w.area or w.zone or "",
          zone = w.area or w.zone or "",
          fullGuildName = w.fullGuildName,
        }

        if IsBlacklistedName(info.fullName) then
          skippedBlacklisted = skippedBlacklisted + 1
          PurgeCandidateFromPipeline(self, info.fullName)
        else
          if self:AddPotential(info.fullName, info) then
            added = added + 1
          end
        end
      end
    end
  end

  if skippedBlacklisted > 0 then
    self:Debug("WHO ingestion skipped blacklisted:", skippedBlacklisted)
  end

  self:Print(("WHO results processed: %d results, %d unguilded added."):format(numWhos, added))

  if added > 0 then
    local cfg = GRIP:GetCfg()
    if cfg and cfg.soundScanComplete then
      self:PlayAlertSound(SOUNDKIT and SOUNDKIT.UI_AUTO_QUEST_COMPLETE or 23404)
    end
  end

  HideFriendsWhoUIIfNeeded()
  self:UpdateUI()
end

function GRIP:OnWhoListUpdate()
  if not state.pendingWho then
    if self:IsDebugEnabled(3) then
      self:Trace("WHO_LIST_UPDATE ignored (no pending query)")
    end
    return
  end

  local pending = state.pendingWho
  state.pendingWho = nil

  C_Timer.After(0, function()
    GRIP:ProcessWhoResults(pending)
    -- Ghost Mode auto-chain: queue next scan after interval
    if GRIP.Ghost and GRIP.Ghost:IsSessionActive() then
      local cfg = (GRIPDB_CHAR and GRIPDB_CHAR.config) or {}
      local interval = math.max(tonumber(cfg.minWhoInterval) or 15, 15)
      C_Timer.After(interval, function()
        if GRIP.Ghost and GRIP.Ghost:IsSessionActive() and not state.pendingWho then
          GRIP:SendNextWho()
        end
      end)
    end
  end)
end