-- Rev 8
-- GRIP – Core
-- Retail (Midnight) 12.0.1+ / Interface 120001
--
-- NOTE: Some actions are restricted (#hwevent):
-- - C_FriendList.SendWho()
-- - C_GuildInfo.Invite() (compat: GuildInvite deprecated 10.2.6)
-- - SendChatMessage(..., "CHANNEL", ...)
-- This addon queues/organizes, and uses click/keybind/slash for restricted calls.
--
-- CHANGED (Rev 2):
-- - Debug/logging code is now wrapped behind GRIP.Logger (so we can fully move it into Debug.lua later).
-- - Core keeps only thin wrappers + a fallback Logger implementation (Debug.lua can override/extend).
--
-- CHANGED (Rev 3):
-- - Fallback Logger now supports "debug capture" to SavedVariables:
--     GRIPDB.config.debugCapture = true|false
--     GRIPDB.config.debugCaptureMax = number (default 800)
--   Captured lines go to GRIPDB.debugLog (persisted in WTF/SavedVariables/GRIP.lua).
-- - Adds fallback GRIP:DumpDebugLog / GRIP:ClearDebugLog / GRIP:UpdateDebugCapture for slash command hooks.
--   (A future Debug.lua can override these and/or replace Logger.Capture.)
--
-- CHANGED (Rev 4):
-- - Persisted debug capture now stores PLAIN TEXT (no color codes) to keep SavedVariables clean/readable.
--   Chat output remains colored as before.
--
-- CHANGED (Rev 5):
-- - Add binding header string for the Bindings.xml header token "GRIP_BINDINGS"
--   (so it shows as a proper subgroup label in the Key Bindings UI).
--
-- CHANGED (Rev 6):
-- - Add startup reconciliation for “zombie pending” invite states after /reload:
--   - Clear runtime pending tables (who/whisper/invite) since they do not persist.
--   - Normalize GRIPDB.potential entries that were mid-invite:
--       * If invitePending=true and inviteSuccess is unknown, clear invitePending.
--       * If the last invite attempt is older than a short grace window, allow retry by clearing inviteAttempted too.
--   This prevents entries from getting stuck as “pending” forever after a reload/UI restart.
--
-- CHANGED (Rev 7):
-- - Remove Core.lua's internal ADDON_LOADED/PLAYER_LOGIN event hook for ReconcileAfterReload().
--   Reconciliation is still defined here, but should be invoked from Events.lua (ADDON_LOADED) to avoid
--   ordering races with scheduler startup (e.g., postTicker being cleared after StartPostScheduler()).
--
-- CHANGED (Rev 8):
-- - Add GRIP:GateTrace(...) helper: opt-in diagnostics that print when
--   GRIPDB.config.traceExecutionGate == true, even if debug logging is OFF.
--   (Default behavior unchanged when traceExecutionGate is false.)

local ADDON_NAME, GRIP = ...
GRIP.ADDON_NAME = ADDON_NAME
GRIP.VERSION = "0.4.0"

-- Optional global for debugging in /run
_G.GRIP = GRIP

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

-- Shared runtime state (safe across files via the same addon table)
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
  end

  if not _G.GRIPDB or type(GRIPDB.potential) ~= "table" then
    return
  end

  local now = time and time() or 0
  local changed = 0
  local retryEnabled = 0

  for _, entry in pairs(GRIPDB.potential) do
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
    if not _G.GRIPDB or not GRIPDB.config then return nil end
    return GRIPDB.config
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
    if not _G.GRIPDB then return nil end
    GRIPDB.debugLog = GRIPDB.debugLog or {}
    GRIPDB.debugLog.lines = GRIPDB.debugLog.lines or {}
    GRIPDB.debugLog.dropped = tonumber(GRIPDB.debugLog.dropped) or 0
    GRIPDB.debugLog.lastAt = GRIPDB.debugLog.lastAt or ""
    return GRIPDB.debugLog
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
    local n = tonumber(cfg and (cfg.debugCaptureMax or cfg.debugPersistMax)) or 800
    if n < 50 then n = 50 end
    if n > 5000 then n = 5000 end
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
        for _ = 1, over do
          table.remove(lines, 1)
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

    if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage(chatMsg)
    end

    if cfg and not cfg._warnedMissingDebugWindow then
      cfg._warnedMissingDebugWindow = true
      if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00GRIP: Debug chat window '"
          .. ((cfg and cfg.debugWindowName) or "Debug")
          .. "' not found. Create/rename a chat tab to match.|r")
      end
    end
  end
end

-- Back-compat wrappers used across the addon:
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
  if not (_G.GRIPDB and type(GRIPDB.config) == "table" and GRIPDB.config.traceExecutionGate == true) then
    return
  end

  local ts = date("%H:%M:%S")
  local msg = ("|cffffcc00GRIP GATE|r [%s] %s"):format(ts, Join(...))

  -- Prefer the Debug chat window if it exists; otherwise fall back to default chat.
  local frame = (Logger and Logger.ResolveFrame and Logger:ResolveFrame(false)) or nil
  if frame and frame.AddMessage then
    frame:AddMessage(msg)
    return
  end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(msg)
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
-- Fallback Debug helpers used by Slash.lua
-- (A future Debug.lua can override these methods.)
-- ------------------------------------------------------------
function GRIP:UpdateDebugCapture()
  -- Ensure SavedVariables tables exist if capture is enabled.
  local cfg = self:GetDebugConfig()
  if not (_G.GRIPDB and cfg) then return end
  if cfg.debugCapture or cfg.debugPersist then
    GRIPDB.debugLog = GRIPDB.debugLog or { lines = {}, dropped = 0, lastAt = "" }
    GRIPDB.debugLog.lines = GRIPDB.debugLog.lines or {}
    GRIPDB.debugLog.dropped = tonumber(GRIPDB.debugLog.dropped) or 0
    GRIPDB.debugLog.lastAt = GRIPDB.debugLog.lastAt or ""
  end
end

function GRIP:ClearDebugLog()
  if not _G.GRIPDB or not GRIPDB.debugLog then return end
  if type(GRIPDB.debugLog.lines) == "table" then
    wipe(GRIPDB.debugLog.lines)
  else
    GRIPDB.debugLog.lines = {}
  end
  GRIPDB.debugLog.dropped = 0
  GRIPDB.debugLog.lastAt = ""
end

function GRIP:DumpDebugLog(n)
  n = tonumber(n) or 200
  if n < 1 then n = 1 end
  if n > 500 then n = 500 end

  if not _G.GRIPDB or not GRIPDB.debugLog or type(GRIPDB.debugLog.lines) ~= "table" then
    self:Print("Debug dump: no captured log. Enable with: /grip debug capture on")
    return
  end

  local lines = GRIPDB.debugLog.lines
  local total = #lines
  local start = math.max(1, total - n + 1)

  self:Print(("Debug dump: showing %d/%d (dropped=%d). Full log is in WTF/SavedVariables/GRIP.lua under GRIPDB.debugLog.lines"):format(
    (total - start + 1),
    total,
    tonumber(GRIPDB.debugLog.dropped) or 0
  ))

  for i = start, total do
    -- Use DEFAULT_CHAT_FRAME directly to avoid recursive debug mirroring.
    if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage(lines[i])
    end
  end
end

function GRIP:UpdateUI() end