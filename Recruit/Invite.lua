-- Rev 11
-- GRIP – Guild invite module (restricted #hwevent; one per click/keybind)
-- CHANGED: InviteNext performs Whisper+Invite immediately in the same hardware event,
-- enforces a shared 1.0s cooldown, and implements:
--   - no-response => 24h temp blacklist + remove from Potential
--   - after 7 no-responses => purgeable blacklistDays
--   - decline/blocked/etc => purgeable blacklistDays
--
-- Changed: NO_RESPONSE_TIMEOUT raised to 70s.
-- Rationale: Blizzard UI static popup default timeout is 60s; we wait +10s to avoid false "no response".
--
-- CHANGED (Rev 5):
-- - Add GRIPDB/config/potential nil-safety guards.
-- - Ensure pending tables exist before use.
-- - Clamp blacklistDays to a sane default if missing.
--
-- CHANGED (Rev 6):
-- - Reduce redundant UpdateUI() calls (single refresh per action; avoid extra churn in common paths).
-- - Skip whisper send if template resolves to blank/whitespace (avoid empty whisper attempts).
-- - Minor hardening: clear pendingWhisper on blank-skip in InviteNext whisper path.
--
-- CHANGED (Rev 7):
-- - Blacklist execution gate (last-line defense): if target is blacklisted, never whisper/invite.
-- - Purge/skip blacklisted names found in pending states (handles bad SavedVariables state after /reload).
-- - Enforce InCombatLockdown() guard for the invite hardware-event call path.
--
-- CHANGED (Rev 8):
-- - Deduplicate blacklist gating: route all invite-pipeline blacklist decisions through GRIP:BL_ExecutionGate().
--
-- CHANGED (Rev 9):
-- - Gate Trace Mode plumbing: pass structured context tables to BL_ExecutionGate() so trace logs
--   show action + phase + module when trace is enabled (default trace remains off).
--
-- CHANGED (Rev 10):
-- - Fix GateCtx argument order bug in InviteBlacklistGate(): phase should be the invite/whisper phase,
--   not the literal string "gate". (Improves Gate Trace Mode diagnostics; behavior unchanged.)
--
-- CHANGED (Rev 11):
-- - Ensure BL_ExecutionGate coverage is "immediately before" execution:
--   move Debug logging AFTER the whisper send and AFTER the GuildInvite protected call,
--   so the last-line InviteBlacklistGate() check is the final step before execution.

local ADDON_NAME, GRIP = ...
local state = GRIP.state

local ACTION_COOLDOWN = 1.0
local NO_RESPONSE_TIMEOUT = 70
local NO_RESPONSE_SECONDS = 24 * 60 * 60
local NO_RESPONSE_ESCALATE_COUNT = 7

local function GetCfg()
  return (_G.GRIPDB and GRIPDB.config) or nil
end

local function GetPotential()
  return (_G.GRIPDB and GRIPDB.potential) or nil
end

local function GetBlacklistDays(cfg)
  local n = tonumber(cfg and cfg.blacklistDays) or 0
  if n <= 0 then n = 1 end
  if n > 365 then n = 365 end
  return n
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

  -- Prefer exact short-name unique match
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
    action = "invite",
    phase = tostring(phase or ""),
    module = "Recruit/Invite",
  }
  if extra ~= nil then
    ctx.extra = extra
  end
  return ctx
end

local function IsInviteBlocked(self, name, context)
  local ok = self:BL_ExecutionGate(name, context or GateCtx("unspecified"))
  return not ok
end

local function PickNextInviteTarget()
  local pot = GetPotential()
  if not pot then return nil end

  local names = GRIP:SortPotentialNames()
  for _, name in ipairs(names) do
    local entry = pot[name]
    if entry and not entry.inviteAttempted and not entry.invitePending and not IsInviteBlocked(GRIP, name, GateCtx("pick")) then
      return name
    end
  end
  return nil
end

local function CooldownReady()
  local now = GetTime()
  local untilT = tonumber(state.actionCooldownUntil) or 0
  if now < untilT then
    local left = untilT - now
    GRIP:Print(("Please wait %.1fs before the next action."):format(left))
    return false
  end
  return true
end

local function ConsumeCooldown()
  local untilT = GetTime() + ACTION_COOLDOWN
  state.actionCooldownUntil = untilT
  if state.ui then
    state.ui._actionCooldownUntil = untilT
  end
end

local function StartWhisperConfirmTimeout(name)
  C_Timer.After(8, function()
    if state.pendingWhisper and state.pendingWhisper[name] then
      state.pendingWhisper[name] = nil
      GRIP:Debug("Whisper confirm timeout:", name)
      GRIP:UpdateUI()
    end
  end)
end

local function IncNoResponseCounter(fullName)
  if not (_G.GRIPDB and GRIPDB.counters and GRIPDB.counters.noResponse) then
    return nil
  end
  local c = tonumber(GRIPDB.counters.noResponse[fullName]) or 0
  c = c + 1
  GRIPDB.counters.noResponse[fullName] = c
  return c
end

-- Last-line execution gate for invite pipeline (whisper+invite).
-- Returns true if target is blocked and we should stop/clean up.
local function InviteBlacklistGate(self, name, pot, cfg, phase, ctx)
  if not name or name == "" then return true end
  -- Rev 10: fix GateCtx argument order (phase should be the real phase)
  local context = ctx or GateCtx(phase, "gate")

  if not IsInviteBlocked(self, name, context) then return false end

  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingInvite  = state.pendingInvite or {}

  state.pendingWhisper[name] = nil
  state.pendingInvite[name]  = nil

  local entry = pot and pot[name] or nil
  if entry then
    -- Ensure we don't re-target from Potential due to bad state.
    if phase == "whisper" then
      entry.whisperAttempted = true
      entry.whisperSuccess = false
      entry.whisperLastAt = self:Now()
    elseif phase == "invite" then
      entry.inviteAttempted = true
      entry.invitePending = false
      entry.inviteSuccess = false
      entry.inviteLastAt = self:Now()
    else
      -- generic cleanup
      entry.invitePending = false
    end
  end

  self:Debug("Blacklist gate (invite pipeline): blocked", tostring(phase or "?"), "for", name)
  self:MaybeFinalize(name)

  return true
end

local function PurgeBlacklistedPending(self, pot, cfg)
  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingInvite  = state.pendingInvite or {}

  local blockedWhispers = {}
  for name in pairs(state.pendingWhisper) do
    if IsInviteBlocked(self, name, GateCtx("pending:whisper")) then
      blockedWhispers[#blockedWhispers + 1] = name
    end
  end
  for _, name in ipairs(blockedWhispers) do
    InviteBlacklistGate(self, name, pot, cfg, "whisper", GateCtx("pending:whisper"))
  end

  local blockedInvites = {}
  for name in pairs(state.pendingInvite) do
    if IsInviteBlocked(self, name, GateCtx("pending:invite")) then
      blockedInvites[#blockedInvites + 1] = name
    end
  end
  for _, name in ipairs(blockedInvites) do
    InviteBlacklistGate(self, name, pot, cfg, "invite", GateCtx("pending:invite"))
  end
end

function GRIP:InviteNext()
  local cfg = GetCfg()
  local pot = GetPotential()
  if not cfg or not pot then
    self:Print("Cannot invite: GRIPDB not initialized yet.")
    return
  end

  state.pendingWhisper = state.pendingWhisper or {}
  state.pendingInvite = state.pendingInvite or {}

  -- Bad-state safety: purge any blocked targets sitting in pending state (SV tamper /reload).
  PurgeBlacklistedPending(self, pot, cfg)

  if not cfg.inviteEnabled then
    self:Print("Guild invites are disabled in config.")
    return
  end

  if InCombatLockdown and InCombatLockdown() then
    self:Print("Cannot send guild invite while in combat.")
    return
  end

  if not IsInGuild or not IsInGuild() then
    self:Print("You are not in a guild.")
    return
  end

  if CanGuildInvite and not CanGuildInvite() then
    self:Print("You don't have permission to invite to the guild.")
    return
  end

  local name = PickNextInviteTarget()
  if not name then
    self:Print("No candidates in Potential list need invites.")
    return
  end

  -- Last-line defense even though PickNextInviteTarget filters.
  if InviteBlacklistGate(self, name, pot, cfg, "pick", GateCtx("pick")) then
    self:UpdateUI()
    return
  end

  if not CooldownReady() then
    return
  end
  ConsumeCooldown()

  local entry = pot[name]
  if not entry then return end

  local didUIChange = false

  -- Whisper (not #hwevent restricted, but we do it here so one click = one candidate)
  if cfg.whisperEnabled and not entry.whisperAttempted then
    -- Gate before whisper execution.
    if InviteBlacklistGate(self, name, pot, cfg, "whisper", GateCtx("whisper:pre")) then
      didUIChange = true
      if didUIChange then self:UpdateUI() end
      return
    end

    local msg = self:ApplyTemplate(cfg.whisperMessage, name)

    entry.whisperAttempted = true
    entry.whisperSuccess = nil
    entry.whisperLastAt = self:Now()

    if IsBlank(msg) then
      -- Treat blank as a failed attempt to avoid repeated targeting.
      entry.whisperSuccess = false
      state.pendingWhisper[name] = nil
      self:Debug("Whisper blank; skipping send:", name)
    else
      state.pendingWhisper[name] = true

      -- LAST-LINE DEFENSE for whisper execution (blacklist could change between template and send).
      -- Rev 11: keep this as the final step immediately before the send.
      if InviteBlacklistGate(self, name, pot, cfg, "whisper", GateCtx("whisper:pre-exec")) then
        didUIChange = true
        if didUIChange then self:UpdateUI() end
        return
      end

      self:SendChatMessageCompat(msg, "WHISPER", nil, name)
      self:Debug("Whisper ->", name, msg)
      StartWhisperConfirmTimeout(name)
    end

    didUIChange = true
  end

  -- Invite (#hwevent restricted) – must be called from a click/keybind/slash.
  entry.inviteAttempted = true
  entry.invitePending = true
  entry.inviteSuccess = nil
  entry.inviteLastAt = self:Now()

  state.pendingInvite[name] = true
  didUIChange = true

  -- LAST-LINE DEFENSE: do not attempt protected call if blocked.
  -- Rev 11: keep this as the final step immediately before GuildInvite.
  if InviteBlacklistGate(self, name, pot, cfg, "invite", GateCtx("invite:pre-exec")) then
    entry.invitePending = false
    state.pendingInvite[name] = nil
    didUIChange = true
    if didUIChange then self:UpdateUI() end
    return
  end

  GuildInvite(name)
  self:Debug("GuildInvite ->", name)

  C_Timer.After(NO_RESPONSE_TIMEOUT, function()
    if state.pendingInvite and state.pendingInvite[name] then
      state.pendingInvite[name] = nil

      if _G.GRIPDB and GRIPDB.potential and GRIPDB.potential[name] then
        GRIPDB.potential[name].invitePending = false
      end

      -- If they were blocked after the attempt, just finalize safely (no more pipeline actions).
      if GRIP:BL_ExecutionGate(name, GateCtx("no-response-timeout")) == false then
        GRIP:MaybeFinalize(name)
        GRIP:UpdateUI()
        return
      end

      local count = IncNoResponseCounter(name)
      if count and count >= NO_RESPONSE_ESCALATE_COUNT then
        GRIP:Blacklist(name, GetBlacklistDays(cfg))
        GRIP:Debug("Invite no response:", name, "count=", count, "-> blacklistDays")
      else
        GRIP:BlacklistForSeconds(name, NO_RESPONSE_SECONDS)
        GRIP:Debug("Invite no response:", name, "count=", tostring(count or "?"), "-> 24h temp blacklist")
      end

      GRIP:RemovePotential(name)
      GRIP:UpdateUI()
    end
  end)

  if cfg.whisperEnabled then
    self:Print(("Whispered+Invited (attempt): %s"):format(name))
  else
    self:Print(("Invited (attempt): %s"):format(name))
  end

  if didUIChange then
    self:UpdateUI()
  end
end

function GRIP:OnInviteSystemSuccess(targetName)
  local cfg = GetCfg()
  local pot = GetPotential()
  if not cfg or not pot then return end

  local full = ResolvePotentialName(targetName)
  if not full then return end

  state.pendingInvite = state.pendingInvite or {}

  -- If blocked, ensure pending is cleared and exit (no further pipeline side effects).
  if InviteBlacklistGate(self, full, pot, cfg, "invite_success", GateCtx("system:success", targetName)) then
    self:UpdateUI()
    return
  end

  local entry = pot[full]
  if not entry then return end

  state.pendingInvite[full] = nil
  entry.invitePending = false
  entry.inviteSuccess = true

  -- Processed => purgeable blacklist (anti-spam)
  self:Blacklist(full, GetBlacklistDays(cfg))

  self:Debug("Invite success:", full)
  self:MaybeFinalize(full)
  self:UpdateUI()
end

function GRIP:OnInviteSystemFail(targetName, reason)
  local cfg = GetCfg()
  local pot = GetPotential()
  if not cfg or not pot then return end

  local full = ResolvePotentialName(targetName)
  if not full then return end

  reason = tostring(reason or "fail")

  state.pendingInvite = state.pendingInvite or {}

  -- If blocked, ensure pending is cleared and exit (no further pipeline side effects).
  if InviteBlacklistGate(self, full, pot, cfg, "invite_fail", GateCtx("system:fail", { target = targetName, reason = reason })) then
    self:UpdateUI()
    return
  end

  local entry = pot[full]
  if not entry then return end

  state.pendingInvite[full] = nil
  entry.invitePending = false
  entry.inviteSuccess = false

  -- If they were "not found", do NOT blacklist (so they can be rediscovered later).
  -- Otherwise treat as processed (declined/blocked/etc) => purgeable blacklist.
  if reason ~= "player_not_found" then
    self:Blacklist(full, GetBlacklistDays(cfg))
  end

  self:Debug("Invite failed:", full, "reason=", reason)
  self:MaybeFinalize(full)
  self:UpdateUI()
end