-- Rev 7
-- GRIP – Whisper module
--
-- CHANGED (Rev 3):
-- - Add GRIPDB/config/potential nil-safety guards.
-- - Ensure pending tables exist before use.
-- - Skip sending if whisper template resolves to blank/whitespace.
-- - Stop ticker cleanly if whisperEnabled is turned off while running.
--
-- CHANGED (Rev 4):
-- - Reduce redundant UpdateUI() calls (coalesce per action/tick; avoid multiple refreshes in early-return paths).
-- - Avoid extra UI churn in inform/failed handlers (single refresh at end).
--
-- CHANGED (Rev 5):
-- - Blacklist execution gate (last-line defense): if target is blacklisted, never attempt whisper send.
-- - Purge/skip blacklisted names found in pending/queue (handles bad SavedVariables state after /reload).
-- - Inform/failed handlers hard-stop on blacklisted targets (clear pending + finalize; no further processing).
--
-- CHANGED (Rev 6):
-- - Deduplicate blacklist gating: route all whisper-path blacklist decisions through GRIP:BL_ExecutionGate().
--
-- CHANGED (Rev 7):
-- - Gate Trace Mode plumbing: pass structured context tables to BL_ExecutionGate() so trace logs
--   show action + phase + module when trace is enabled (default trace remains off).

local ADDON_NAME, GRIP = ...
local state = GRIP.state

local function GetCfg()
  return (_G.GRIPDB and GRIPDB.config) or nil
end

local function GetPotential()
  return (_G.GRIPDB and GRIPDB.potential) or nil
end

local function IsBlank(s)
  if type(s) ~= "string" then return true end
  return s:gsub("%s+", "") == ""
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
  for name in pairs(state.pendingWhisper) do
    if IsWhisperBlocked(self, name, GateCtx("pending")) then
      WhisperBlacklistGate(self, name, pot, cfg, GateCtx("pending"))
    end
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

function GRIP:BuildWhisperQueue()
  state.whisperQueue = state.whisperQueue or {}
  wipe(state.whisperQueue)

  local cfg = GetCfg()
  local pot = GetPotential()
  if not cfg or not pot then return end
  if not cfg.whisperEnabled then return end

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
    self:StopWhispers()
    return
  end

  local didUIChange = false

  local name = table.remove(state.whisperQueue, 1)
  local entry = pot[name]
  if not entry then return end
  if entry.whisperAttempted then return end

  -- Gate early (queue already popped).
  if WhisperBlacklistGate(self, name, pot, cfg, GateCtx("tick-early")) then
    didUIChange = true
    if didUIChange then self:UpdateUI() end
    return
  end

  local msg = self:ApplyTemplate(cfg.whisperMessage, name)
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

  self:Debug("Whisper ->", name, msg)
  -- Whisper is not #hwevent restricted, but is server rate-limited.
  self:SendChatMessageCompat(msg, "WHISPER", nil, name)

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
    self:Debug("Whisper success:", full)
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