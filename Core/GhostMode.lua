-- GRIP: Ghost Mode
-- Universal action queue with invisible overlay frame for hardware-event gated execution.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, pcall, wipe = pairs, pcall, wipe
local gsub = string.gsub
local tremove = table.remove
local floor, ceil = math.floor, math.ceil
local time = time

-- WoW API
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsInGuild, CanGuildInvite = IsInGuild, CanGuildInvite
local C_Timer = C_Timer

local state = GRIP.state

-- Constants
local OVERLAY_FRAME_LEVEL     = 9999
local UPDATE_THROTTLE         = 0.2   -- seconds: overlay OnUpdate throttle
local AUTO_WHO_DELAY          = 0.5   -- seconds: delay before auto-who after session start
local SESSION_MIN_MINUTES     = 5
local SESSION_MAX_MINUTES     = 120
local COOLDOWN_MIN_MINUTES    = 1
local COOLDOWN_MAX_MINUTES    = 60
local QUEUE_MIN               = 1
local QUEUE_MAX               = 200

GRIP.Ghost = GRIP.Ghost or {}
local Ghost = GRIP.Ghost

-- Back-compat alias if older code references GRIP.GhostMode
GRIP.GhostMode = GRIP.GhostMode or Ghost

state.ghost = state.ghost or {
  queue = {},
  lastSentAt = 0,
  sessionActive = false,
  sessionStartedAt = nil,
  sessionActionCount = 0,
}

-- ----------------------------------------------------------------
-- Config helpers
-- ----------------------------------------------------------------

local function CfgBool(key, default)
  return GRIP:CfgBool(key, default)
end

local function CfgNum(key, default)
  return GRIP:CfgNum(key, default)
end

local function DebugEnabled()
  local cfg = GRIP:GetCfg()
  return cfg and cfg.debug and true or false
end

local function Dbg(...)
  if DebugEnabled() and GRIP and GRIP.Debug then
    GRIP:Debug(...)
  end
end

-- ----------------------------------------------------------------
-- Raw chat send (prefer C_ChatInfo, fall back to SendChatMessage)
-- ----------------------------------------------------------------

local function RawSend(msg, chatType, languageID, target)
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    C_ChatInfo.SendChatMessage(msg, chatType, languageID, target)
    return true
  end
  if SendChatMessage then
    SendChatMessage(msg, chatType, languageID, target)
    return true
  end
  return false
end

-- ----------------------------------------------------------------
-- Rate limiting (non-session queue path)
-- ----------------------------------------------------------------

local function CanSendNow()
  local minI = GRIP:Clamp(CfgNum("ghostModeMinInterval", 0.5), 0, 10)
  if minI <= 0 then return true end
  local now = GetTime and GetTime() or 0
  local last = tonumber(state.ghost and state.ghost.lastSentAt) or 0
  return (now - last) >= minI
end

local function MarkSentNow()
  local now = GetTime and GetTime() or 0
  state.ghost.lastSentAt = now
end

-- ----------------------------------------------------------------
-- Invisible overlay frame
-- ----------------------------------------------------------------

local overlay = CreateFrame("Frame", nil, UIParent)
overlay:SetAllPoints(UIParent)
overlay:SetFrameStrata("TOOLTIP")
overlay:SetFrameLevel(OVERLAY_FRAME_LEVEL)
overlay:EnableMouse(true)
overlay:EnableMouseWheel(true)
overlay:SetMouseMotionEnabled(true)
pcall(function() overlay:EnableGamePadButton(true) end)
pcall(function() overlay:EnableGamePadStick(true) end)
overlay:EnableKeyboard(true)
overlay:SetPropagateKeyboardInput(true)
overlay:Hide()

-- ----------------------------------------------------------------
-- RunNext — executes ONE queue item per hardware event
-- ----------------------------------------------------------------

local function RunNext()
  if not Ghost:IsSessionActive() then return end
  if InCombatLockdown and InCombatLockdown() then return end

  local q = state.ghost and state.ghost.queue
  if not q or #q == 0 then return end

  local item = table.remove(q, 1)
  if item and type(item.action) == "function" then
    state.ghost.sessionActionCount = (state.ghost.sessionActionCount or 0) + 1
    local ok, err = pcall(item.action)
    if not ok then
      Dbg("Ghost: action error:", tostring(err))
    else
      Dbg("Ghost: executed", tostring(item.actionType or "?"), "pending=", #q)
    end
  end

  Ghost:CheckSessionTimeout()
  Ghost:UpdateOverlay()
end

-- Wire all hardware event scripts to RunNext
overlay:SetScript("OnMouseDown", RunNext)
overlay:SetScript("OnMouseUp", RunNext)
overlay:SetScript("OnMouseWheel", RunNext)
overlay:SetScript("OnGamePadButtonDown", RunNext)
overlay:SetScript("OnGamePadButtonUp", RunNext)
overlay:SetScript("OnGamePadStick", RunNext)
overlay:SetScript("OnKeyDown", RunNext)
overlay:SetScript("OnKeyUp", RunNext)

-- ----------------------------------------------------------------
-- Updater frame — manages overlay visibility via OnUpdate
-- ----------------------------------------------------------------

local updater = CreateFrame("Frame")
local updaterElapsed = 0
updater:SetScript("OnUpdate", function(_, dt)
  updaterElapsed = updaterElapsed + dt
  if updaterElapsed < UPDATE_THROTTLE then return end
  updaterElapsed = 0
  if not Ghost:IsSessionActive() then
    if overlay:IsShown() then overlay:Hide() end
    return
  end
  local q = state.ghost and state.ghost.queue
  local hasItems = q and #q > 0
  if hasItems and not (InCombatLockdown and InCombatLockdown()) then
    if not overlay:IsShown() then overlay:Show() end
  else
    if overlay:IsShown() then overlay:Hide() end
  end
end)

-- ----------------------------------------------------------------
-- Overlay visibility helper
-- ----------------------------------------------------------------

function Ghost:UpdateOverlay()
  if not self:IsSessionActive() then
    if overlay:IsShown() then overlay:Hide() end
    return
  end
  local q = state.ghost and state.ghost.queue
  if q and #q > 0 and not (InCombatLockdown and InCombatLockdown()) then
    if not overlay:IsShown() then overlay:Show() end
  else
    if overlay:IsShown() then overlay:Hide() end
  end
end

-- ----------------------------------------------------------------
-- Session management
-- ----------------------------------------------------------------

function Ghost:IsEnabled()
  return CfgBool("ghostModeEnabled", false)
end

function Ghost:GetNumPending()
  local q = state.ghost and state.ghost.queue
  return (type(q) == "table" and #q) or 0
end

function Ghost:IsSessionActive()
  return state.ghost and state.ghost.sessionActive == true
end

function Ghost:IsSessionLocked()
  return self:IsSessionActive()
end

function Ghost:GetSessionElapsed()
  if not self:IsSessionActive() then return 0 end
  local started = state.ghost and state.ghost.sessionStartedAt
  if not started then return 0 end
  return time() - started
end

function Ghost:GetSessionMaxSeconds()
  local cfg = GRIP:GetCfg()
  local maxMin = GRIP:Clamp(tonumber(cfg and cfg.ghostSessionMaxMinutes) or 60, SESSION_MIN_MINUTES, SESSION_MAX_MINUTES)
  return maxMin * 60
end

function Ghost:GetCooldownRemaining()
  local cfg = GRIP:GetCfg()
  if not cfg then return 0 end
  local until_t = tonumber(cfg.ghostCooldownUntil) or 0
  local remaining = until_t - time()
  if remaining < 0 then remaining = 0 end
  return remaining
end

function Ghost:StartSession()
  local cfg = GRIP:GetCfg()
  if not cfg then return false, "no_config" end
  if not cfg.ghostModeEnabled then
    GRIP:Print("Ghost Mode is disabled. Enable with: /grip set ghostmode on")
    return false, "disabled"
  end

  local now = time()
  local cooldownUntil = tonumber(cfg.ghostCooldownUntil) or 0
  if now < cooldownUntil then
    local remaining = math.ceil((cooldownUntil - now) / 60)
    GRIP:Print(("Ghost Mode on cooldown. %d minute(s) remaining."):format(remaining))
    return false, "cooldown"
  end

  state.ghost = state.ghost or {}
  state.ghost.sessionActive = true
  state.ghost.sessionStartedAt = now
  state.ghost.sessionActionCount = 0
  state.ghost.queue = state.ghost.queue or {}

  Dbg("Ghost Mode session started.")

  -- Auto-rebuild /who queue if empty or exhausted
  if type(GRIP.BuildWhoQueue) == "function" then
    local whoQ = state.whoQueue
    if not whoQ or #whoQ == 0 or (state.whoIndex and state.whoIndex > #whoQ) then
      GRIP:BuildWhoQueue()
    end
  end

  -- Auto-queue first /who scan
  if type(GRIP.SendNextWho) == "function" then
    C_Timer.After(AUTO_WHO_DELAY, function()
      if Ghost:IsSessionActive() then
        GRIP:SendNextWho()
      end
    end)
  end

  -- Phase 2c: Auto-start whisper ticker if not already running
  if cfg.whisperEnabled and not state.whisperTicker then
    state.ghost.whisperAutoStarted = true
    state.pendingWhisper = state.pendingWhisper or {}
    state.pendingInvite = state.pendingInvite or {}
    state.whisperQueue = state.whisperQueue or {}
    local delay = GRIP:Clamp(tonumber(cfg.whisperDelay) or 2.5, 0.8, 10)
    state.whisperTicker = C_Timer.NewTicker(delay, function()
      GRIP:WhisperTick()
    end)
    Dbg("Ghost: whisper ticker auto-started (delay=", delay, "s)")
  end

  return true, "started"
end

function Ghost:StopSession(reason)
  if not state.ghost or not state.ghost.sessionActive then return end

  state.ghost.sessionActive = false
  state.ghost.queue = {}

  -- Clear ghost-queued pendingWho so it doesn't block future manual scans
  if state.pendingWho and state.pendingWho.ghostQueued then
    state.pendingWho = nil
  end

  -- Phase 2c: Stop whisper ticker on ghost session end
  if state.whisperTicker then
    GRIP:StopWhispers()
  end
  state.ghost.whisperAutoStarted = nil

  -- Set persistent cooldown
  local cfg = GRIP:GetCfg()
  if cfg then
    local cooldownMin = GRIP:Clamp(tonumber(cfg.ghostCooldownMinutes) or 10, COOLDOWN_MIN_MINUTES, COOLDOWN_MAX_MINUTES)
    cfg.ghostCooldownUntil = time() + (cooldownMin * 60)
  end

  overlay:Hide()

  local elapsed = 0
  if state.ghost.sessionStartedAt then
    elapsed = math.floor((time() - state.ghost.sessionStartedAt) / 60)
  end
  local count = state.ghost.sessionActionCount or 0

  state.ghost.sessionStartedAt = nil
  state.ghost.sessionActionCount = 0

  Dbg("Ghost Mode session stopped:", tostring(reason or "manual"),
    "elapsed=", elapsed, "min, actions=", count)
end

function Ghost:CheckSessionTimeout()
  if not self:IsSessionActive() then return end

  local cfg = GRIP:GetCfg()
  local maxMin = GRIP:Clamp(tonumber(cfg and cfg.ghostSessionMaxMinutes) or 60, SESSION_MIN_MINUTES, SESSION_MAX_MINUTES)
  local elapsed = time() - (state.ghost.sessionStartedAt or time())
  if elapsed >= (maxMin * 60) then
    self:StopSession("timeout")
    GRIP:Print(("Ghost Mode auto-stopped after %d minutes."):format(maxMin))
  end
end

-- ----------------------------------------------------------------
-- Combat event handlers
-- ----------------------------------------------------------------

function Ghost:OnCombatEnter()
  if overlay:IsShown() then overlay:Hide() end
end

function Ghost:OnCombatLeave()
  if self:IsSessionActive() and self:GetNumPending() > 0 then
    overlay:Show()
  end
end

-- ----------------------------------------------------------------
-- Universal action queue (new public API)
-- ----------------------------------------------------------------

function Ghost:QueueAction(actionType, actionFn, meta)
  if not self:IsSessionActive() then return false, "no_session" end
  if type(actionFn) ~= "function" then return false, "not_function" end

  state.ghost.queue = state.ghost.queue or {}

  local maxLen = GRIP:Clamp(CfgNum("ghostModeMaxQueue", 50), QUEUE_MIN, QUEUE_MAX)
  if #state.ghost.queue >= maxLen then
    Dbg("Ghost: queue full, dropping:", tostring(actionType))
    return false, "queue_full"
  end

  -- Dedup: skip if same actionType + target already queued
  if meta and meta.target and meta.target ~= "" then
    for _, entry in ipairs(state.ghost.queue) do
      if entry.actionType == actionType
        and entry.meta and entry.meta.target == meta.target then
        Dbg("Ghost: dedup skip", tostring(actionType), meta.target)
        return false, "duplicate"
      end
    end
  end

  state.ghost.queue[#state.ghost.queue + 1] = {
    action = actionFn,
    actionType = actionType or "unknown",
    meta = meta,
    queuedAt = GetTime and GetTime() or 0,
  }

  Dbg("Ghost: queued", tostring(actionType), "pending=", #state.ghost.queue)
  self:UpdateOverlay()
  return true, "queued"
end

-- ----------------------------------------------------------------
-- Queue/send API (used by SendChatMessageCompat routing)
-- ----------------------------------------------------------------

function Ghost:ShouldQueue(chatType)
  if CfgBool("ghostModeQueueAll", false) then return true end
  local t = (chatType or ""):upper()
  return (t == "SAY" or t == "YELL" or t == "CHANNEL")
end

function Ghost:Queue(chatType, msg, languageID, target, meta)
  if GRIP:IsBlank(msg) then return false, "blank" end
  state.ghost.queue = state.ghost.queue or {}

  -- If session active, use QueueAction
  if self:IsSessionActive() then
    return self:QueueAction("post", function()
      RawSend(msg, chatType, languageID, target)
    end, { chatType = chatType, target = target })
  end

  -- Legacy queue: wrap as action-based item for FlushOne compat
  local maxLen = GRIP:Clamp(CfgNum("ghostModeMaxQueue", 50), QUEUE_MIN, QUEUE_MAX)
  if #state.ghost.queue >= maxLen then
    Dbg("Ghost: queue full; dropping new item. max=", maxLen, "type=", tostring(chatType))
    return false, "queue_full"
  end

  state.ghost.queue[#state.ghost.queue + 1] = {
    action = function() RawSend(msg, chatType, languageID, target) end,
    actionType = "post",
    meta = meta or { chatType = chatType, target = target },
    queuedAt = GetTime and GetTime() or 0,
    -- Legacy fields for FlushOne compat
    msg = msg,
    chatType = chatType,
    languageID = languageID,
    target = target,
  }

  Dbg("Ghost: queued (pending=", #state.ghost.queue, "type=", tostring(chatType), ")")
  self:UpdateOverlay()
  return true, "queued"
end

function Ghost:Send(chatType, msg, languageID, target, isHardwareEvent, meta)
  if GRIP:IsBlank(msg) then return false, "blank" end

  -- If session active, queue the send as an action
  if self:IsSessionActive() then
    return self:QueueAction("post", function()
      RawSend(msg, chatType, languageID, target)
    end, { chatType = chatType, target = target })
  end

  -- Phase 1 behavior: if Ghost Mode disabled, send immediately
  if not self:IsEnabled() then
    local ok = RawSend(msg, chatType, languageID, target)
    return ok, ok and "sent" or "send_api_missing"
  end

  if InCombatLockdown and InCombatLockdown() then
    if self:ShouldQueue(chatType) then
      return self:Queue(chatType, msg, languageID, target, meta)
    end
    return false, "combat_lockdown"
  end

  if self:ShouldQueue(chatType) and not isHardwareEvent then
    return self:Queue(chatType, msg, languageID, target, meta)
  end

  if not CanSendNow() then
    if self:ShouldQueue(chatType) then
      return self:Queue(chatType, msg, languageID, target, meta)
    end
    return false, "rate_limited"
  end

  local ok = RawSend(msg, chatType, languageID, target)
  if ok then MarkSentNow() end
  return ok, ok and "sent" or "send_api_missing"
end

-- ----------------------------------------------------------------
-- Public flush API (no internal callers — retained as
-- public surface for macro/WeakAura integration)
-- ----------------------------------------------------------------
function Ghost:FlushOne(isHardwareEvent)
  if not self:IsEnabled() and not self:IsSessionActive() then return false, "disabled" end
  if not isHardwareEvent then return false, "requires_hardware" end

  if InCombatLockdown and InCombatLockdown() then
    return false, "combat_lockdown"
  end

  local q = state.ghost and state.ghost.queue
  if type(q) ~= "table" or #q == 0 then
    return false, "empty"
  end

  local item = table.remove(q, 1)
  if not item then return false, "empty" end

  -- Universal queue items have an action function
  if type(item.action) == "function" then
    local ok, err = pcall(item.action)
    if ok then
      MarkSentNow()
      return true, "sent"
    end
    Dbg("Ghost FlushOne: action error:", tostring(err))
    return false, "action_error"
  end

  -- Legacy format fallback (msg-based items without action)
  if GRIP:IsBlank(item.msg) then
    return false, "blank"
  end

  if not CanSendNow() then
    table.insert(q, 1, item)
    return false, "rate_limited"
  end

  local ok = RawSend(item.msg, item.chatType, item.languageID, item.target)
  if ok then
    MarkSentNow()
    return true, "sent"
  end

  table.insert(q, 1, item)
  return false, "send_api_missing"
end

function Ghost:FlushAll(isHardwareEvent)
  if not self:IsEnabled() and not self:IsSessionActive() then return 0, "disabled" end
  if not isHardwareEvent then return 0, "requires_hardware" end

  local sent = 0
  while self:GetNumPending() > 0 do
    local ok, reason = self:FlushOne(true)
    if not ok then
      return sent, reason
    end
    sent = sent + 1
  end

  return sent, "empty"
end
