-- GRIP: Whisper Queue
-- Whisper queue management, template rendering, rate-limited sending.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, ipairs, wipe = pairs, ipairs, wipe
local gsub, lower, find, format = string.gsub, string.lower, string.find, string.format
local tremove, tsort = table.remove, table.sort
local random = math.random
local time, date = time, date

-- WoW API
local GetTime = GetTime
local C_DateAndTime = C_DateAndTime
local C_Timer = C_Timer

local state = GRIP.state

local function GetCfg()
  return (_G.GRIPDB_CHAR and GRIPDB_CHAR.config) or nil
end

local function GetPotential()
  return (_G.GRIPDB_CHAR and GRIPDB_CHAR.potential) or nil
end

local function IsBlank(s)
  if type(s) ~= "string" then return true end
  return s:gsub("%s+", "") == ""
end

local function GetTodayDateString()
  local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime()
  if t and t.year and t.month and t.monthDay then
    return ("%04d-%02d-%02d"):format(t.year, t.month, t.monthDay)
  end
  return date("%Y-%m-%d")
end

local function ResetIfNewDay(counters)
  local today = GetTodayDateString()
  if counters.whispersSentDate ~= today then
    counters.whispersSent = 0
    counters.whispersSentDate = today
  end
end

local function IsDailyCapReached(cfg)
  if not cfg.whisperDailyCap or cfg.whisperDailyCap <= 0 then return false end
  if not _G.GRIPDB_CHAR or not GRIPDB_CHAR.counters then return false end
  ResetIfNewDay(GRIPDB_CHAR.counters)
  return GRIPDB_CHAR.counters.whispersSent >= cfg.whisperDailyCap
end

local function IncrementWhisperCount()
  if not _G.GRIPDB_CHAR or not GRIPDB_CHAR.counters then return end
  GRIPDB_CHAR.counters.whispersSent = (GRIPDB_CHAR.counters.whispersSent or 0) + 1
end

local OPT_OUT_PHRASES = {
  "no thanks",
  "no thank you",
  "no ty",
  "not interested",
  "no interest",
  "don't want",
  "dont want",
  "stop",
  "leave me alone",
  "don't whisper",
  "dont whisper",
  "don't message",
  "dont message",
  "don't contact",
  "dont contact",
  "already in a guild",
  "already guilded",
  "have a guild",
  "got a guild",
  "i'm in a guild",
  "im in a guild",
  "reported",
  "reporting you",
  "spam",
  "blocked",
}

local function IsOptOutMessage(text)
  if type(text) ~= "string" or text == "" then return false end
  local low = text:lower()
  for i = 1, #OPT_OUT_PHRASES do
    if low:find(OPT_OUT_PHRASES[i], 1, true) then
      return true
    end
  end
  return false
end

local function PickWhisperTemplate(cfg)
  local msgs = cfg.whisperMessages
  if not msgs or #msgs == 0 then
    return cfg.whisperMessage or ""
  end
  if #msgs == 1 then return msgs[1] end

  if cfg.whisperRotation == "random" then
    return msgs[math.random(1, #msgs)]
  end

  -- Sequential (default): round-robin
  state.whisperTemplateIndex = (state.whisperTemplateIndex or 0) + 1
  if state.whisperTemplateIndex > #msgs then
    state.whisperTemplateIndex = 1
  end
  return msgs[state.whisperTemplateIndex]
end

local function ResolvePotentialName(nameMaybe)
  if not nameMaybe or nameMaybe == "" then return nil end
  local pot = GetPotential()
  if not pot then return nil end
  if pot[nameMaybe] then return nameMaybe end

  local short = tostring(nameMaybe):match("^[^-]+")
  if not short then return nil end

  local found
  for name in pairs(pot) do
    if name:match("^[^-]+") == short then
      if found then return nil end -- ambiguous
      found = name
    end
  end
  return found
end

-- Structured context for execution gate diagnostics (trace remains opt-in).
local function GateCtx(phase, extra)
  local ctx = {
    action = "whisper",
    phase = tostring(phase or ""),
    module = "Recruit/Whisper",
  }
  if extra ~= nil then
    ctx.extra = extra
  end
  return ctx
end

local function IsWhisperBlocked(self, name, context)
  local ok = self:BL_ExecutionGate(name, context or GateCtx("unspecified"))
  return not ok
end

-- Last-line execution gate:
-- Returns true if the target is blocked and we should skip/clean up.
local function WhisperBlacklistGate(self, name, pot, cfg, context)
  if not name or name == "" then return true end
  if not IsWhisperBlocked(self, name, context or GateCtx("whisper")) then return false end

  -- Clean up any bad/legacy state safely.
  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingWhisper[name] = nil

  local entry = pot and pot[name] or nil
  if entry then
    entry.whisperAttempted = true
    entry.whisperSuccess = false
    entry.whisperLastAt = self:Now()
  end

  self:Debug("Blacklist gate (whisper): blocked execution for", name)
  self:MaybeFinalize(name)

  return true
end

local function PurgeBlacklistedFromPendingAndQueue(self, pot, cfg)
  state.pendingWhisper = state.pendingWhisper or {}
  state.whisperQueue = state.whisperQueue or {}

  -- Pending: remove any blocked keys (bad SV state safety).
  local blockedPending = {}
  for name in pairs(state.pendingWhisper) do
    if IsWhisperBlocked(self, name, GateCtx("pending")) then
      blockedPending[#blockedPending + 1] = name
    end
  end
  for _, name in ipairs(blockedPending) do
    WhisperBlacklistGate(self, name, pot, cfg, GateCtx("pending"))
  end

  -- Queue: remove blocked names before processing.
  if #state.whisperQueue > 0 then
    local i = 1
    while i <= #state.whisperQueue do
      local name = state.whisperQueue[i]
      if IsWhisperBlocked(self, name, GateCtx("queue")) then
        table.remove(state.whisperQueue, i)
        WhisperBlacklistGate(self, name, pot, cfg, GateCtx("queue"))
      else
        i = i + 1
      end
    end
  end
end

function GRIP:GetWhisperCapStatus()
  local cfg = GetCfg()
  if not cfg then return 0, 0 end
  local cap = cfg.whisperDailyCap or 0
  local sent = 0
  if _G.GRIPDB_CHAR and GRIPDB_CHAR.counters then
    ResetIfNewDay(GRIPDB_CHAR.counters)
    sent = GRIPDB_CHAR.counters.whispersSent or 0
  end
  return sent, cap
end

function GRIP:PickWhisperTemplate()
  local cfg = GetCfg()
  if not cfg then return "" end
  return PickWhisperTemplate(cfg)
end

function GRIP:OnWhisperReceived(senderName, messageText)
  local cfg = GetCfg()
  if not cfg or not cfg.optOutDetection then return end

  local pot = GetPotential()
  if not pot then return end

  -- Resolve sender against Potential keys (handles Name vs Name-Realm)
  local full = ResolvePotentialName(senderName)

  -- Also check pending maps if not in Potential
  if not full then
    state.pendingWhisper = state.pendingWhisper or {}
    state.pendingInvite = state.pendingInvite or {}
    local senderShort = tostring(senderName):match("^[^-]+")
    for name in pairs(state.pendingWhisper) do
      local short = name:match("^[^-]+")
      if name == senderName or short == senderShort then
        full = name
        break
      end
    end
  end

  if not full then
    for name in pairs(state.pendingInvite or {}) do
      local short = name:match("^[^-]+")
      local senderShort = tostring(senderName):match("^[^-]+")
      if name == senderName or short == senderShort then
        full = name
        break
      end
    end
  end

  -- Not a GRIP candidate — ignore completely
  if not full then return end

  if not IsOptOutMessage(messageText) then return end

  -- Opt-out detected: clean up all pending state
  self:Info(("Opt-out detected from %s: \"%s\" — permanently blacklisted."):format(
    full, tostring(messageText):sub(1, 60)))

  if state.pendingWhisper then state.pendingWhisper[full] = nil end
  if state.pendingInvite then state.pendingInvite[full] = nil end

  if pot[full] then
    pot[full].invitePending = false
  end

  self:BlacklistPermanent(full, "opt-out")
  self:RemovePotential(full)
  self:UpdateUI()
end

function GRIP:BuildWhisperQueue()
  state.whisperQueue = state.whisperQueue or {}
  wipe(state.whisperQueue)

  local cfg = GetCfg()
  local pot = GetPotential()
  if not cfg or not pot then return end
  if not cfg.whisperEnabled then return end
  if IsDailyCapReached(cfg) then return end

  for name, entry in pairs(pot) do
    if entry and not entry.whisperAttempted and not IsWhisperBlocked(self, name, GateCtx("build")) then
      state.whisperQueue[#state.whisperQueue + 1] = name
    end
  end
  table.sort(state.whisperQueue)
end

function GRIP:StartWhispers()
  local cfg = GetCfg()
  local pot = GetPotential()
  if not cfg or not pot then
    self:Print("Cannot start whispers: GRIPDB not initialized yet.")
    return
  end

  -- Toggle behavior
  if state.whisperTicker then
    self:StopWhispers()
    return
  end

  if not cfg.whisperEnabled then
    self:Print("Whispers are disabled in config.")
    return
  end

  if IsDailyCapReached(cfg) then
    self:Print(("Daily whisper cap reached (%d). Resets tomorrow."):format(cfg.whisperDailyCap))
    return
  end

  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingInvite = state.pendingInvite or {}

  self:BuildWhisperQueue()

  -- Bad-state safety: purge blocked targets from pending/queue before starting.
  PurgeBlacklistedFromPendingAndQueue(self, pot, cfg)

  if #state.whisperQueue == 0 then
    self:Print("No candidates in Potential list need whispers.")
    return
  end

  local delay = self:Clamp(tonumber(cfg.whisperDelay) or 2.5, 0.8, 10)
  self:Print(("Starting whisper queue: %d targets (%.1fs delay)."):format(#state.whisperQueue, delay))

  state.whisperTicker = C_Timer.NewTicker(delay, function()
    GRIP:WhisperTick()
  end)

  -- Force an immediate UI refresh on start (argument is safe even if UpdateUI ignores it).
  self:UpdateUI(true)
end

function GRIP:StopWhispers()
  if state.whisperTicker then
    state.whisperTicker:Cancel()
    state.whisperTicker = nil
    self:Print("Whisper queue stopped.")
    local cfg = GetCfg()
    if cfg and cfg.soundWhisperDone ~= false then
      self:PlayAlertSound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE or 878)
    end
    self:UpdateUI()
  end
end

function GRIP:WhisperTick()
  local cfg = GetCfg()
  local pot = GetPotential()
  if not cfg or not pot then
    self:StopWhispers()
    return
  end

  if not cfg.whisperEnabled then
    self:StopWhispers()
    return
  end

  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingInvite = state.pendingInvite or {}
  state.whisperQueue = state.whisperQueue or {}

  -- Bad-state safety every tick (covers /reload with tampered SavedVariables).
  PurgeBlacklistedFromPendingAndQueue(self, pot, cfg)

  if #state.whisperQueue == 0 then
    -- Ghost Mode: rebuild queue from Potential (new candidates from ongoing scans)
    if GRIP.Ghost and GRIP.Ghost:IsSessionActive() then
      self:BuildWhisperQueue()
      PurgeBlacklistedFromPendingAndQueue(self, pot, cfg)
      if #state.whisperQueue == 0 then
        return  -- no new candidates yet; try again next tick
      end
      -- Fall through to process next candidate
    else
      self:StopWhispers()
      return
    end
  end

  local didUIChange = false

  local name = table.remove(state.whisperQueue, 1)
  local entry = pot[name]
  if not entry then self:UpdateUI() return end
  if entry.whisperAttempted then self:UpdateUI() return end

  -- Gate early (queue already popped).
  if WhisperBlacklistGate(self, name, pot, cfg, GateCtx("tick-early")) then
    didUIChange = true
    if didUIChange then self:UpdateUI() end
    return
  end

  local msg = self:ApplyTemplate(PickWhisperTemplate(cfg), name)
  if IsBlank(msg) then
    self:Debug("Whisper message blank; skipping:", name)
    entry.whisperAttempted = true
    entry.whisperSuccess = false
    entry.whisperLastAt = self:Now()
    state.pendingWhisper[name] = nil
    self:MaybeFinalize(name)
    didUIChange = true
    if didUIChange then self:UpdateUI() end
    return
  end

  entry.whisperAttempted = true
  entry.whisperSuccess = nil           -- unknown until inform/fail
  entry.whisperLastAt = self:Now()
  state.pendingWhisper[name] = true
  didUIChange = true

  -- LAST-LINE DEFENSE: re-check right before execution.
  if WhisperBlacklistGate(self, name, pot, cfg, GateCtx("pre-exec")) then
    didUIChange = true
    if didUIChange then self:UpdateUI() end
    return
  end

  -- Daily cap check (GRIP-sent whispers only)
  if cfg.whisperDailyCap and cfg.whisperDailyCap > 0 then
    ResetIfNewDay(GRIPDB_CHAR.counters)
    if GRIPDB_CHAR.counters.whispersSent >= cfg.whisperDailyCap then
      self:Print(("Daily whisper cap reached (%d). Queue stopped. Resets tomorrow."):format(cfg.whisperDailyCap))
      if cfg.soundCapWarning ~= false then
        self:PlayAlertSound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
      end
      self:StopWhispers()
      return
    end
    IncrementWhisperCount()
    -- Soft warning at ~80% of cap
    local ratio = GRIPDB_CHAR.counters.whispersSent / cfg.whisperDailyCap
    if ratio >= 0.8 and ratio < 0.85 then
      self:Print(("Approaching daily whisper limit: %d/%d"):format(GRIPDB_CHAR.counters.whispersSent, cfg.whisperDailyCap))
      if cfg.soundCapWarning ~= false then
        self:PlayAlertSound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
      end
    end
  end

  self:Debug("Whisper ->", name, msg)
  -- Whisper is not #hwevent restricted, but is server rate-limited.
  self:SendChatMessageCompat(msg, "WHISPER", nil, name)
  self:RecordCampaignAction("whisper")

  C_Timer.After(8, function()
    if state.pendingWhisper and state.pendingWhisper[name] then
      -- If target became blocked after send, clear pending safely (no more actions should flow from it).
      if GRIP:BL_ExecutionGate(name, GateCtx("timeout")) == false then
        state.pendingWhisper[name] = nil
        GRIP:MaybeFinalize(name)
        GRIP:UpdateUI()
        return
      end

      state.pendingWhisper[name] = nil
      GRIP:Debug("Whisper confirm timeout:", name)
      GRIP:UpdateUI()
    end
  end)

  if didUIChange then
    self:UpdateUI()
  end
end

function GRIP:OnWhisperInform(targetName)
  local cfg = GetCfg()
  local pot = GetPotential()
  if not cfg or not pot then return end

  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingInvite = state.pendingInvite or {}

  local full = ResolvePotentialName(targetName)
  if not full then return end

  -- Last-line defense for inform path (no further pipeline effects for blocked targets).
  if WhisperBlacklistGate(self, full, pot, cfg, GateCtx("inform", targetName)) then
    self:UpdateUI()
    return
  end

  local entry = pot[full]
  if not entry then return end

  state.pendingWhisper[full] = nil
  entry.whisperSuccess = true

  -- Do not finalize/remove while an invite is pending; invite outcome must clear pending state reliably.
  if entry.invitePending or state.pendingInvite[full] then
    self:Debug("Whisper success (invite pending; defer finalize):", full)
    self:UpdateUI()
    return
  end

  -- If invites are disabled, keep legacy behavior to avoid clutter/repeated targeting.
  if not cfg.inviteEnabled then
    self:Blacklist(full, cfg.blacklistDays)
    self:Debug("Whisper success:", full, "(invites disabled -> blacklist)")
    self:MaybeFinalize(full)
  else
    -- Phase 2d: auto-queue invite through Ghost overlay after whisper success
    if GRIP.Ghost and GRIP.Ghost:IsSessionActive() and type(self.AutoQueueGhostInvite) == "function" then
      self:AutoQueueGhostInvite(full)
    else
      self:Debug("Whisper success:", full)
    end
  end

  self:UpdateUI()
end

function GRIP:OnWhisperFailed(targetName)
  local cfg = GetCfg()
  local pot = GetPotential()
  if not cfg or not pot then return end

  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingInvite = state.pendingInvite or {}

  local full = ResolvePotentialName(targetName)
  if not full then return end

  -- Last-line defense for fail path too.
  if WhisperBlacklistGate(self, full, pot, cfg, GateCtx("failed", targetName)) then
    self:UpdateUI()
    return
  end

  local entry = pot[full]
  if not entry then return end

  state.pendingWhisper[full] = nil
  entry.whisperSuccess = false

  -- Do not finalize/remove while an invite is pending.
  if entry.invitePending or state.pendingInvite[full] then
    self:Debug("Whisper failed (invite pending; defer finalize):", full)
    self:UpdateUI()
    return
  end

  self:Debug("Whisper failed:", full)
  self:MaybeFinalize(full)
  self:UpdateUI()
end