-- Rev 2
-- GRIP – Ghost Mode (hardware-event gated chat send)
--
-- Clean-room module.
--
-- Goal:
--   Queue restricted chat sends (notably SAY/YELL/CHANNEL) when invoked from non-hardware contexts,
--   and flush only when explicitly triggered from a real hardware event (click/keybind/slash).
--
-- IMPORTANT:
-- - OFF by default. Inert unless GRIPDB.config.ghostModeEnabled == true.
-- - Does NOT attempt to “detect” hardware events (WoW doesn’t expose a reliable detector).
--   Instead, callers must only call FlushOne/FlushAll from known hardware events.
-- - Avoid combat restrictions: if InCombatLockdown() then do not send; fail gracefully.
--
-- API (minimal):
--   GRIP.Ghost:IsEnabled() -> bool
--   GRIP.Ghost:Queue(chatType, msg, languageID, target, meta) -> ok, reason
--   GRIP.Ghost:Send(chatType, msg, languageID, target, isHardwareEvent, meta) -> ok, reason
--   GRIP.Ghost:FlushOne(isHardwareEvent) -> ok, reason
--   GRIP.Ghost:FlushAll(isHardwareEvent) -> sentCount, reason
--   GRIP.Ghost:GetNumPending() -> number
--
-- Config keys (optional):
--   ghostModeEnabled        (bool)   default false
--   ghostModeQueueAll       (bool)   default false (if true, queue all chatTypes)
--   ghostModeMaxQueue       (number) default 10    (clamped 1..50)
--   ghostModeMinInterval    (number) default 0.5   (seconds between actual sends; clamped 0..10)

local ADDON_NAME, GRIP = ...
local state = GRIP.state

GRIP.Ghost = GRIP.Ghost or {}
local Ghost = GRIP.Ghost

-- Back-compat alias if older code references GRIP.GhostMode
GRIP.GhostMode = GRIP.GhostMode or Ghost

state.ghost = state.ghost or {
  queue = {},
  lastSentAt = 0,
}

local function GetCfg()
  return (_G.GRIPDB and GRIPDB.config) or nil
end

local function CfgBool(key, default)
  local cfg = GetCfg()
  if not cfg then return default end
  local v = cfg[key]
  if v == nil then return default end
  return v and true or false
end

local function CfgNum(key, default)
  local cfg = GetCfg()
  if not cfg then return default end
  local v = tonumber(cfg[key])
  if v == nil then return default end
  return v
end

local function Clamp(n, lo, hi)
  n = tonumber(n) or lo
  if n < lo then n = lo end
  if n > hi then n = hi end
  return n
end

local function IsBlank(s)
  if type(s) ~= "string" then return true end
  return s:gsub("%s+", "") == ""
end

local function DebugEnabled()
  local cfg = GetCfg()
  return cfg and cfg.debug and true or false
end

local function Dbg(...)
  if DebugEnabled() and GRIP and GRIP.Debug then
    GRIP:Debug(...)
  end
end

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

function Ghost:IsEnabled()
  return CfgBool("ghostModeEnabled", false)
end

function Ghost:GetNumPending()
  local q = state.ghost and state.ghost.queue
  return (type(q) == "table" and #q) or 0
end

function Ghost:ShouldQueue(chatType)
  if CfgBool("ghostModeQueueAll", false) then return true end
  local t = (chatType or ""):upper()
  return (t == "SAY" or t == "YELL" or t == "CHANNEL")
end

local function CanSendNow()
  local minI = Clamp(CfgNum("ghostModeMinInterval", 0.5), 0, 10)
  if minI <= 0 then return true end
  local now = GetTime and GetTime() or 0
  local last = tonumber(state.ghost and state.ghost.lastSentAt) or 0
  return (now - last) >= minI
end

local function MarkSentNow()
  local now = GetTime and GetTime() or 0
  state.ghost.lastSentAt = now
end

local function QueueMax()
  return Clamp(CfgNum("ghostModeMaxQueue", 10), 1, 50)
end

function Ghost:Queue(chatType, msg, languageID, target, meta)
  if IsBlank(msg) then return false, "blank" end
  if not state.ghost then state.ghost = { queue = {}, lastSentAt = 0 } end
  state.ghost.queue = state.ghost.queue or {}

  local maxLen = QueueMax()
  if #state.ghost.queue >= maxLen then
    Dbg("Ghost: queue full; dropping new item. max=", maxLen, "type=", tostring(chatType))
    return false, "queue_full"
  end

  state.ghost.queue[#state.ghost.queue + 1] = {
    msg = msg,
    chatType = chatType,
    languageID = languageID,
    target = target,
    queuedAt = GetTime and GetTime() or 0,
    meta = meta,
  }

  if DebugEnabled() then
    Dbg("Ghost: queued (pending=", #state.ghost.queue, "type=", tostring(chatType), ")")
  end

  return true, "queued"
end

-- Send:
-- - If Ghost Mode disabled => sends immediately.
-- - If enabled and chatType is restricted => sends only when isHardwareEvent==true; otherwise queues.
-- - If enabled but chatType not restricted => sends immediately (still rate-limited when called via Flush).
function Ghost:Send(chatType, msg, languageID, target, isHardwareEvent, meta)
  if IsBlank(msg) then return false, "blank" end

  if not self:IsEnabled() then
    local ok = RawSend(msg, chatType, languageID, target)
    return ok, ok and "sent" or "send_api_missing"
  end

  if InCombatLockdown and InCombatLockdown() then
    -- Do not attempt protected work or UI trickery in combat. Queue and exit.
    if self:ShouldQueue(chatType) then
      return self:Queue(chatType, msg, languageID, target, meta)
    end
    return false, "combat_lockdown"
  end

  if self:ShouldQueue(chatType) and not isHardwareEvent then
    return self:Queue(chatType, msg, languageID, target, meta)
  end

  -- Hardware event path (or non-restricted type while enabled)
  if not CanSendNow() then
    -- If restricted, better to queue than hard-fail (prevents button mash).
    if self:ShouldQueue(chatType) then
      return self:Queue(chatType, msg, languageID, target, meta)
    end
    return false, "rate_limited"
  end

  local ok = RawSend(msg, chatType, languageID, target)
  if ok then MarkSentNow() end
  return ok, ok and "sent" or "send_api_missing"
end

function Ghost:FlushOne(isHardwareEvent)
  if not self:IsEnabled() then return false, "disabled" end
  if not isHardwareEvent then return false, "requires_hardware" end

  if InCombatLockdown and InCombatLockdown() then
    return false, "combat_lockdown"
  end

  local q = state.ghost and state.ghost.queue
  if type(q) ~= "table" or #q == 0 then
    return false, "empty"
  end

  if not CanSendNow() then
    return false, "rate_limited"
  end

  local item = table.remove(q, 1)
  if not item or IsBlank(item.msg) then
    return false, "blank"
  end

  local ok = RawSend(item.msg, item.chatType, item.languageID, item.target)
  if ok then
    MarkSentNow()
    return true, "sent"
  end

  -- If we couldn't send, put it back at the front to avoid silent loss.
  table.insert(q, 1, item)
  return false, "send_api_missing"
end

function Ghost:FlushAll(isHardwareEvent)
  if not self:IsEnabled() then return 0, "disabled" end
  if not isHardwareEvent then return 0, "requires_hardware" end

  local sent = 0
  while self:GetNumPending() > 0 do
    local ok, reason = self:FlushOne(true)
    if not ok then
      return sent, reason
    end
    sent = sent + 1

    -- One-per-input by default is handled by the caller (hardware event).
    -- If someone intentionally calls FlushAll from a click, we still respect rate limiting.
    if not CanSendNow() then
      return sent, "rate_limited"
    end
  end

  return sent, "empty"
end