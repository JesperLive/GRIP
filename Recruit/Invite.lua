-- GRIP: Invite Pipeline
-- Hardware-event gated guild invite with whisper+invite combo, no-response escalation.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, ipairs, pcall, strsplit = pairs, ipairs, pcall, strsplit
local gsub = string.gsub
local tinsert, tremove = table.insert, table.remove
local min = math.min

-- WoW API
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsInGuild, CanGuildInvite = IsInGuild, CanGuildInvite
local C_Timer = C_Timer

local state = GRIP.state

local ACTION_COOLDOWN = 1.0
local NO_RESPONSE_TIMEOUT = 70
local NO_RESPONSE_SECONDS = 24 * 60 * 60
local NO_RESPONSE_ESCALATE_COUNT = 7

local function GetBlacklistDays(cfg)
  local n = tonumber(cfg and cfg.blacklistDays) or 0
  if n <= 0 then n = 1 end
  if n > 365 then n = 365 end
  return n
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
  local pot = GRIP:GetPotential()
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
  -- Fix GateCtx argument order (phase should be the real phase)
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
  local cfg = GRIP:GetCfg()
  local pot = GRIP:GetPotential()
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

    local msg = self:ApplyTemplate(self:PickWhisperTemplate(), name)

    entry.whisperAttempted = true
    entry.whisperSuccess = nil
    entry.whisperLastAt = self:Now()

    if GRIP:IsBlank(msg) then
      -- Treat blank as a failed attempt to avoid repeated targeting.
      entry.whisperSuccess = false
      state.pendingWhisper[name] = nil
      self:Debug("Whisper blank; skipping send:", name)
    else
      state.pendingWhisper[name] = true

      -- LAST-LINE DEFENSE for whisper execution (blacklist could change between template and send).
      -- Keep this as the final step immediately before the send.
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
  -- Keep this as the final step immediately before GuildInvite.
  if InviteBlacklistGate(self, name, pot, cfg, "invite", GateCtx("invite:pre-exec")) then
    entry.invitePending = false
    state.pendingInvite[name] = nil
    didUIChange = true
    if didUIChange then self:UpdateUI() end
    return
  end

  -- Ghost Mode: queue invite instead of executing directly
  if GRIP.Ghost:IsSessionActive() then
    local inviteName = name  -- capture for closure
    GRIP.Ghost:QueueAction("invite", function()
      GRIP:SafeGuildInvite(inviteName)
      GRIP:RecordCampaignAction("invite")
      GRIP:Debug("GuildInvite (ghost) ->", inviteName)
    end, { target = inviteName })
    self:Print(("Queued invite (Ghost): %s"):format(name))
    if didUIChange then self:UpdateUI() end
    return
  end

  self:SafeGuildInvite(name)
  self:RecordCampaignAction("invite")
  self:Debug("GuildInvite ->", name)

  C_Timer.After(NO_RESPONSE_TIMEOUT, function()
    if state.pendingInvite and state.pendingInvite[name] then
      state.pendingInvite[name] = nil

      if _G.GRIPDB_CHAR and GRIPDB_CHAR.potential and GRIPDB_CHAR.potential[name] then
        GRIPDB_CHAR.potential[name].invitePending = false
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

function GRIP:AutoQueueGhostInvite(name)
  local cfg = GRIP:GetCfg()
  local pot = GRIP:GetPotential()
  if not cfg or not pot then return end
  if not cfg.inviteEnabled then return end
  if not GRIP.Ghost or not GRIP.Ghost:IsSessionActive() then return end

  local entry = pot[name]
  if not entry then return end
  if entry.inviteAttempted then return end
  if entry.invitePending then return end

  state.pendingInvite = state.pendingInvite or {}
  if state.pendingInvite[name] then return end

  if not self:BL_ExecutionGate(name, GateCtx("auto-ghost")) then return end
  if not IsInGuild or not IsInGuild() then return end
  if CanGuildInvite and not CanGuildInvite() then return end

  entry.inviteAttempted = true
  entry.invitePending = true
  entry.inviteSuccess = nil
  entry.inviteLastAt = self:Now()
  state.pendingInvite[name] = true

  local inviteName = name  -- capture for closure

  GRIP.Ghost:QueueAction("invite", function()
    -- Re-check gate at execution time (time passes between queue and drain)
    if not GRIP:BL_ExecutionGate(inviteName, GateCtx("auto-ghost:exec")) then
      if state.pendingInvite then state.pendingInvite[inviteName] = nil end
      local p = GRIP:GetPotential()
      if p and p[inviteName] then
        p[inviteName].invitePending = false
        p[inviteName].inviteSuccess = false
      end
      GRIP:MaybeFinalize(inviteName)
      GRIP:UpdateUI()
      return
    end
    GRIP:SafeGuildInvite(inviteName)
    GRIP:RecordCampaignAction("invite")
    GRIP:Debug("GuildInvite (ghost-auto) ->", inviteName)
  end, { target = inviteName })

  -- 70-second no-response timeout (starts at queue time, not execution time)
  C_Timer.After(NO_RESPONSE_TIMEOUT, function()
    if state.pendingInvite and state.pendingInvite[inviteName] then
      state.pendingInvite[inviteName] = nil
      if _G.GRIPDB_CHAR and GRIPDB_CHAR.potential and GRIPDB_CHAR.potential[inviteName] then
        GRIPDB_CHAR.potential[inviteName].invitePending = false
      end
      if GRIP:BL_ExecutionGate(inviteName, GateCtx("no-response-timeout")) == false then
        GRIP:MaybeFinalize(inviteName)
        GRIP:UpdateUI()
        return
      end
      local count = IncNoResponseCounter(inviteName)
      local c = GRIP:GetCfg()
      if count and count >= NO_RESPONSE_ESCALATE_COUNT then
        GRIP:Blacklist(inviteName, GetBlacklistDays(c))
        GRIP:Debug("Invite no response (ghost-auto):", inviteName, "count=", count, "-> blacklistDays")
      else
        GRIP:BlacklistForSeconds(inviteName, NO_RESPONSE_SECONDS)
        GRIP:Debug("Invite no response (ghost-auto):", inviteName, "count=", tostring(count or "?"), "-> 24h temp blacklist")
      end
      GRIP:RemovePotential(inviteName)
      GRIP:UpdateUI()
    end
  end)

  self:Debug("Auto-queued invite (ghost):", name)
  self:UpdateUI()
end

function GRIP:OnInviteSystemSuccess(targetName)
  local cfg = GRIP:GetCfg()
  local pot = GRIP:GetPotential()
  if not cfg or not pot then return end

  local full = GRIP:ResolvePotentialName(targetName)
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
  if cfg.soundInviteAccepted ~= false then
    self:PlayAlertSound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960)
  end
  self:MaybeFinalize(full)
  self:UpdateUI()
end

function GRIP:OnInviteSystemFail(targetName, reason)
  local cfg = GRIP:GetCfg()
  local pot = GRIP:GetPotential()
  if not cfg or not pot then return end

  local full = GRIP:ResolvePotentialName(targetName)
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