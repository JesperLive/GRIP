-- GRIP: Core
-- Bootstrap, version, shared state, logger wrapper, keybind entry points.

local ADDON_NAME, GRIP = ...
GRIP.ADDON_NAME = ADDON_NAME
GRIP.VERSION = "0.7.0"

-- Optional global for debugging in /run
_G.GRIP = GRIP

-- Shared constants (referenced by multiple modules)
GRIP.MAX_CHAT_MSG_LEN    = 250   -- WoW chat message hard limit
GRIP.MAX_SCAN_LEVEL      = 90    -- Midnight level cap
GRIP.MIN_SCAN_LEVEL      = 1

-- Lua
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, pcall, wipe = pairs, pcall, wipe
local concat = table.concat
local floor, max = math.floor, math.max
local time, date = time, date

-- Local constants
local DEBUG_LOG_MIN       = 50
local DEBUG_LOG_MAX       = 5000
local DEBUG_LOG_DEFAULT   = 800
local SOUNDKIT_FALLBACK   = 8959   -- SOUNDKIT.RAID_WARNING fallback ID

-- Keybinding labels (shown in Key Bindings UI)
BINDING_HEADER_GRIP = "GRIP"
BINDING_HEADER_GRIP_BINDINGS = "GRIP"
BINDING_NAME_GRIP_TOGGLE = "Toggle GRIP window"
BINDING_NAME_GRIP_WHO_NEXT = "Send next /who scan"
BINDING_NAME_GRIP_INVITE_NEXT = "Send next guild invite"
BINDING_NAME_GRIP_POST_NEXT = "Send next Trade/General post"

-- Binding entry points (called from Bindings.xml)
function GRIP_ToggleUI()
  if GRIP and GRIP.ToggleUI then GRIP:ToggleUI() end
end
function GRIP_WhoNext()
  if GRIP and GRIP.SendNextWho then GRIP:SendNextWho() end
end
function GRIP_InviteNext()
  if GRIP and GRIP.InviteNext then GRIP:InviteNext() end
end
function GRIP_PostNext()
  if GRIP and GRIP.PostNext then GRIP:PostNext() end
end

GRIP.state = GRIP.state or {
  -- /who scanning
  whoQueue = {},
  whoIndex = 1,
  pendingWho = nil, -- { filter=string, sentAt=GetTime() }
  lastWhoSentAt = 0,

  -- whispering
  whisperTicker = nil,
  whisperQueue = {},     -- array of names
  pendingWhisper = {},   -- [name]=true while awaiting confirmation/timeout

  -- invites
  pendingInvite = {},    -- [name]=true while awaiting system msg/timeout

  -- posts
  postTicker = nil,      -- scheduler (queues messages; does not send automatically)
  postQueue = {},        -- array of {channelToken,msg,queuedAt,reason}
  lastPostSentAt = 0,

  -- UI
  ui = nil,

  -- Debug chat window cache (used by logger)
  debugFrame = nil,
  debugFrameIndex = nil,

  -- Campaign cooldown
  campaignActivityStart = nil,
  campaignActionCount = 0,
  campaignLastActionAt = nil,
  campaignSoftWarned = false,
  campaignHardPaused = false,
}

local function Join(...)
  local n = select("#", ...)
  if n == 0 then return "" end
  local t = {}
  for i = 1, n do
    t[i] = tostring(select(i, ...))
  end
  return table.concat(t, " ")
end

-- ------------------------------------------------------------
-- Startup reconciliation (zombie pending states after reload)
-- ------------------------------------------------------------

-- Grace window (seconds): if we reloaded very quickly after clicking Invite,
-- avoid instantly turning it into a retry-eligible entry.
local INVITE_RETRY_GRACE_SECONDS = 90

function GRIP:ReconcileAfterReload()
  -- Runtime-only pending state is always invalid after a reload.
  local st = GRIP.state
  if st then
    st.pendingWho = nil
    st.whisperTicker = nil
    st.postTicker = nil

    st.pendingWhisper = {}
    st.pendingInvite = {}

    -- Cooldowns are runtime-only; clear them so UI doesn't “stick”.
    st.actionCooldownUntil = 0

    -- Campaign cooldown
    st.campaignActivityStart = nil
    st.campaignActionCount = 0
    st.campaignLastActionAt = nil
    st.campaignSoftWarned = false
    st.campaignHardPaused = false

    -- Ghost Mode session (runtime only; ghostCooldownUntil persists in GRIPDB_CHAR.config)
    st.ghost = st.ghost or {}
    st.ghost.queue = {}
    st.ghost.sessionActive = false
    st.ghost.sessionStartedAt = nil
    st.ghost.sessionActionCount = 0
  end

  if not _G.GRIPDB_CHAR or type(GRIPDB_CHAR.potential) ~= "table" then
    return
  end

  local now = time and time() or 0
  local changed = 0
  local retryEnabled = 0

  for _, entry in pairs(GRIPDB_CHAR.potential) do
    if type(entry) == "table" and entry.invitePending then
      -- If we were mid-invite and reloaded, that pending cannot complete reliably.
      -- Convert “pending” -> “unknown outcome” and (optionally) allow retry if it’s stale.
      if entry.inviteSuccess == nil then
        entry.invitePending = false
        changed = changed + 1

        local lastAt = tonumber(entry.inviteLastAt) or 0
        if lastAt > 0 and now > 0 and (now - lastAt) >= INVITE_RETRY_GRACE_SECONDS then
          -- Allow a user to retry after reload without needing to clear lists manually.
          -- This may cause a harmless “already invited/in guild” failure in rare cases,
          -- but prevents permanent “stuck” candidates.
          entry.inviteAttempted = false
          retryEnabled = retryEnabled + 1
        end
      else
        -- If inviteSuccess is known, pending should not remain true.
        entry.invitePending = false
        changed = changed + 1
      end
    end
  end

  if (changed > 0 or retryEnabled > 0) and self.Debug then
    self:Debug("ReconcileAfterReload:",
      "normalizedPending=", changed,
      "retryEnabled=", retryEnabled
    )
  end
end

-- ------------------------------------------------------------
-- Campaign cooldown — session fatigue protection
-- ------------------------------------------------------------

function GRIP:RecordCampaignAction(actionType)
  local cfg = (_G.GRIPDB_CHAR and GRIPDB_CHAR.config) or nil
  if not cfg or not cfg.campaignCooldownEnabled then return end

  local now = time()
  local st = self.state
  local gap = self:Clamp(tonumber(cfg.campaignGapResetMinutes) or 5, 1, 30) * 60
  local threshold = self:Clamp(tonumber(cfg.campaignCooldownMinutes) or 30, 5, 120) * 60

  -- Gap reset: if idle longer than gap, reset window
  if st.campaignLastActionAt and (now - st.campaignLastActionAt) > gap then
    st.campaignActivityStart = nil
    st.campaignActionCount = 0
    st.campaignSoftWarned = false
    st.campaignHardPaused = false
  end

  -- Start new window if needed
  if not st.campaignActivityStart then
    st.campaignActivityStart = now
    st.campaignActionCount = 0
    st.campaignSoftWarned = false
    st.campaignHardPaused = false
  end

  st.campaignLastActionAt = now
  st.campaignActionCount = (st.campaignActionCount or 0) + 1

  local elapsed = now - st.campaignActivityStart

  -- Hard pause at 2x threshold
  if cfg.campaignHardPauseEnabled and elapsed >= (threshold * 2) and not st.campaignHardPaused then
    st.campaignHardPaused = true
    self:Print(("Whisper queue auto-paused after %d minutes of continuous recruiting. Take a break, then /grip whisper to resume."):format(math.floor(elapsed / 60)))
    if cfg.soundCapWarning ~= false then
      self:PlayAlertSound(SOUNDKIT and SOUNDKIT.RAID_WARNING or SOUNDKIT_FALLBACK)
    end
    self:StopWhispers()
    -- Reset window so resuming starts fresh
    st.campaignActivityStart = nil
    st.campaignActionCount = 0
    st.campaignSoftWarned = false
    st.campaignHardPaused = false
    return
  end

  -- Soft warning at 1x threshold
  if elapsed >= threshold and not st.campaignSoftWarned then
    st.campaignSoftWarned = true
    self:Print(("You've been recruiting for %d minutes (%d actions). Consider taking a 5-minute break to reduce Silence risk."):format(math.floor(elapsed / 60), st.campaignActionCount))
    if cfg.soundCapWarning ~= false then
      self:PlayAlertSound(SOUNDKIT and SOUNDKIT.RAID_WARNING or SOUNDKIT_FALLBACK)
    end
  end
end

-- ------------------------------------------------------------
-- Logger wrapper
-- ------------------------------------------------------------
GRIP.Logger = GRIP.Logger or {}
local Logger = GRIP.Logger

-- Fallback logger implementation (Debug.lua can override these later).
if not Logger._gripFallbackInstalled then
  Logger._gripFallbackInstalled = true

  local LEVEL_NAME = {
    [1] = "INFO",
    [2] = "DEBUG",
    [3] = "TRACE",
  }

  function Logger:GetConfig()
    if not _G.GRIPDB_CHAR or not GRIPDB_CHAR.config then return nil end
    return GRIPDB_CHAR.config
  end

  function Logger:IsEnabled(level)
    local cfg = self:GetConfig()
    if not cfg or not cfg.debug then return false end
    local v = tonumber(cfg.debugVerbosity) or 2
    level = tonumber(level) or 2
    return v >= level
  end

  function Logger:ResolveFrame(force)
    local cfg = self:GetConfig()
    local desired = (cfg and cfg.debugWindowName) or "Debug"

    if not force and GRIP.state.debugFrame and GRIP.state.debugFrameIndex then
      local name = GetChatWindowInfo(GRIP.state.debugFrameIndex)
      if name == desired then
        return GRIP.state.debugFrame
      end
    end

    GRIP.state.debugFrame = nil
    GRIP.state.debugFrameIndex = nil

    if type(NUM_CHAT_WINDOWS) ~= "number" then
      return nil
    end

    for i = 1, NUM_CHAT_WINDOWS do
      local name = GetChatWindowInfo(i)
      if name == desired then
        local frame = _G["ChatFrame" .. i]
        if frame and frame.AddMessage then
          GRIP.state.debugFrame = frame
          GRIP.state.debugFrameIndex = i
          return frame
        end
      end
    end

    return nil
  end

  local function AddToFrame(frame, text)
    if frame and frame.AddMessage then
      frame:AddMessage(text)
      return true
    end
    return false
  end

  -- ----------------------------
  -- Fallback debug capture (SavedVariables)
  -- ----------------------------
  local function EnsureDebugLog()
    if not _G.GRIPDB_CHAR then return nil end
    GRIPDB_CHAR.debugLog = GRIPDB_CHAR.debugLog or {}
    GRIPDB_CHAR.debugLog.lines = GRIPDB_CHAR.debugLog.lines or {}
    GRIPDB_CHAR.debugLog.dropped = tonumber(GRIPDB_CHAR.debugLog.dropped) or 0
    GRIPDB_CHAR.debugLog.lastAt = GRIPDB_CHAR.debugLog.lastAt or ""
    return GRIPDB_CHAR.debugLog
  end

  local function CaptureEnabled(cfg)
    if not cfg then return false end
    -- Primary flag used by your Slash.lua
    if cfg.debugCapture == true then return true end
    -- Back-compat in case older builds used debugPersist
    if cfg.debugPersist == true then return true end
    return false
  end

  local function CaptureMax(cfg)
    local n = tonumber(cfg and (cfg.debugCaptureMax or cfg.debugPersistMax)) or DEBUG_LOG_DEFAULT
    if n < DEBUG_LOG_MIN then n = DEBUG_LOG_MIN end
    if n > DEBUG_LOG_MAX then n = DEBUG_LOG_MAX end
    return n
  end

  -- Provide a default Capture hook IF none exists.
  -- Debug.lua can replace Logger.Capture later.
  if Logger.Capture == nil then
    function Logger:Capture(level, ts, formatted, ...)
      local cfg = self:GetConfig()
      if not CaptureEnabled(cfg) then return end

      local log = EnsureDebugLog()
      if not log then return end

      local lines = log.lines
      local maxN = CaptureMax(cfg)

      lines[#lines + 1] = tostring(formatted or "")

      if #lines > maxN then
        local over = #lines - maxN
        local newLines = {}
        for i = over + 1, #lines do
          newLines[#newLines + 1] = lines[i]
        end
        wipe(lines)
        for i = 1, #newLines do
          lines[i] = newLines[i]
        end
        log.dropped = (tonumber(log.dropped) or 0) + over
      end

      log.lastAt = tostring(ts or "")
    end
  end

  function Logger:Log(level, ...)
    if not self:IsEnabled(level) then return end

    local cfg = self:GetConfig()
    local frame = self:ResolveFrame(false)

    local ts = date("%H:%M:%S")
    local lvl = LEVEL_NAME[level] or tostring(level)

    -- Plain text for persistence
    local plainMsg = ("GRIP %s [%s] %s"):format(lvl, ts, Join(...))
    -- Colored output for chat windows
    local chatMsg = ("|cff66ccffGRIP %s|r [%s] %s"):format(lvl, ts, Join(...))

    -- Optional capture hook (fallback above, or Debug.lua can implement/override).
    -- Persist plain text to keep SavedVariables clean/readable.
    if self.Capture then
      pcall(self.Capture, self, level, ts, plainMsg, ...)
    end

    if frame and AddToFrame(frame, chatMsg) then
      return
    end
    -- No fallback to DEFAULT_CHAT_FRAME. Debug messages stay silent
    -- if the Debug window doesn't exist. The ring buffer capture above
    -- already preserves the message for /grip debug dump/copy.
  end
end

-- Convenience wrappers used across the addon:
function GRIP:GetDebugConfig()
  return Logger:GetConfig()
end

function GRIP:IsDebugEnabled(level)
  return Logger:IsEnabled(level)
end

function GRIP:ResolveDebugFrame(force)
  return Logger:ResolveFrame(force)
end

function GRIP:Log(level, ...)
  return Logger:Log(level, ...)
end

function GRIP:Info(...)  self:Log(1, ...) end
function GRIP:Debug(...) self:Log(2, ...) end
function GRIP:Trace(...) self:Log(3, ...) end

-- ------------------------------------------------------------
-- Gate Trace Mode helper (prints even if debug is OFF)
-- ------------------------------------------------------------
function GRIP:GateTrace(...)
  if not (_G.GRIPDB_CHAR and type(GRIPDB_CHAR.config) == "table" and GRIPDB_CHAR.config.traceExecutionGate == true) then
    return
  end

  local ts = date("%H:%M:%S")
  local msg = ("|cffffcc00GRIP GATE|r [%s] %s"):format(ts, Join(...))

  -- Gate trace only goes to the Debug window; no fallback to main chat.
  local frame = (Logger and Logger.ResolveFrame and Logger:ResolveFrame(false)) or nil
  if frame and frame.AddMessage then
    frame:AddMessage(msg)
  end
end

function GRIP:Print(msg)
  msg = tostring(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff99GRIP:|r " .. msg)
  end

  local cfg = self:GetDebugConfig()
  if cfg and cfg.debug and cfg.debugMirrorPrint then
    self:Info("PRINT:", msg)
  end
end

-- ------------------------------------------------------------
-- Auto-create Debug chat window
-- ------------------------------------------------------------
function GRIP:EnsureDebugChatWindow()
  local cfg = self:GetDebugConfig()
  local desired = (cfg and cfg.debugWindowName) or "Debug"

  -- Check if it already exists
  if type(NUM_CHAT_WINDOWS) == "number" then
    for i = 1, NUM_CHAT_WINDOWS do
      local name = GetChatWindowInfo(i)
      if name == desired then
        return true  -- already exists
      end
    end
  end

  -- Create it
  if FCF_OpenNewWindow then
    local frame = FCF_OpenNewWindow(desired)
    if frame then
      -- Remove default message groups so only GRIP output appears
      if ChatFrame_RemoveAllMessageGroups then
        ChatFrame_RemoveAllMessageGroups(frame)
      end
      -- Resolve into logger cache
      if Logger and Logger.ResolveFrame then
        Logger:ResolveFrame(true)
      end
      return true
    end
  end

  return false
end

-- ------------------------------------------------------------
-- Fallback Debug helpers used by Slash.lua
-- (Debug.lua overrides Logger.Capture at load time.)
-- ------------------------------------------------------------
function GRIP:UpdateDebugCapture()
  -- Ensure SavedVariables tables exist if capture is enabled.
  local cfg = self:GetDebugConfig()
  if not (_G.GRIPDB_CHAR and cfg) then return end
  if cfg.debugCapture or cfg.debugPersist then
    GRIPDB_CHAR.debugLog = GRIPDB_CHAR.debugLog or { lines = {}, dropped = 0, lastAt = "" }
    GRIPDB_CHAR.debugLog.lines = GRIPDB_CHAR.debugLog.lines or {}
    GRIPDB_CHAR.debugLog.dropped = tonumber(GRIPDB_CHAR.debugLog.dropped) or 0
    GRIPDB_CHAR.debugLog.lastAt = GRIPDB_CHAR.debugLog.lastAt or ""
  end
end

function GRIP:ClearDebugLog()
  if not _G.GRIPDB_CHAR or not GRIPDB_CHAR.debugLog then return end
  if type(GRIPDB_CHAR.debugLog.lines) == "table" then
    wipe(GRIPDB_CHAR.debugLog.lines)
  else
    GRIPDB_CHAR.debugLog.lines = {}
  end
  GRIPDB_CHAR.debugLog.dropped = 0
  GRIPDB_CHAR.debugLog.lastAt = ""
end

function GRIP:DumpDebugLog(n)
  n = tonumber(n) or 200
  if n < 1 then n = 1 end
  if n > 500 then n = 500 end

  if not _G.GRIPDB_CHAR or not GRIPDB_CHAR.debugLog or type(GRIPDB_CHAR.debugLog.lines) ~= "table" then
    self:Print("Debug dump: no captured log. Enable with: /grip debug capture on")
    return
  end

  local lines = GRIPDB_CHAR.debugLog.lines
  local total = #lines
  local start = math.max(1, total - n + 1)

  self:Print(("Debug dump: showing %d/%d (dropped=%d). Full log is in WTF/SavedVariables/GRIP.lua under GRIPDB_CHAR.debugLog.lines"):format(
    (total - start + 1),
    total,
    tonumber(GRIPDB_CHAR.debugLog.dropped) or 0
  ))

  for i = start, total do
    -- Use DEFAULT_CHAT_FRAME directly to avoid recursive debug mirroring.
    if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage(lines[i])
    end
  end
end

function GRIP:UpdateUI() end