-- GRIP: DB Potential
-- Potential candidate list: add, remove, finalize lifecycle.

local ADDON_NAME, GRIP = ...
local state = GRIP.state

local function EnsurePotentialTable()
  if not _G.GRIPDB then return false end
  GRIPDB.potential = GRIPDB.potential or {}
  return true
end

function GRIP:AddPotential(fullName, info)
  if not fullName or fullName == "" then return false end
  if not EnsurePotentialTable() then return false end
  if self:IsBlacklisted(fullName) then return false end

  -- Enforce exclude list + user allowlists (zones/races/classes)
  if info and self.FiltersAllowWhoInfo and (not self:FiltersAllowWhoInfo(info)) then
    if self.IsDebugEnabled and self:IsDebugEnabled(2) then
      self:Debug("Potential skipped (filters):", fullName,
        "zone=", info.zone or info.area or "",
        "race=", info.race or "",
        "class=", info.class or ""
      )
    end
    return false
  end

  GRIPDB.potential[fullName] = GRIPDB.potential[fullName] or {}
  local p = GRIPDB.potential[fullName]

  if info then
    p.name = fullName
    if info.level then p.level = info.level end
    if info.class then p.class = info.class end
    if info.race then p.race = info.race end

    local area = info.area or info.zone
    if area then
      p.area = area
      -- Keep a mirror field for older code/exports if any.
      p.zone = area
    end

    if info.note then p.note = info.note end
  end

  p.firstSeen = p.firstSeen or self:Now()
  p.lastSeen = self:Now()

  if self:IsDebugEnabled(2) then
    self:Debug("Potential added/updated:", fullName,
      "lvl=", p.level,
      "class=", p.class,
      "race=", p.race,
      "area=", p.area or p.zone
    )
  end

  return true
end

function GRIP:RemovePotential(fullName)
  if not fullName or fullName == "" then return false end
  if not _G.GRIPDB or type(GRIPDB.potential) ~= "table" then return false end
  if GRIPDB.potential[fullName] then
    GRIPDB.potential[fullName] = nil
    self:Debug("Potential removed:", fullName)
    return true
  end
  return false
end

-- Decide when an entry is "done" and can be removed from Potential.
-- We remove entries when:
--  - They are blacklisted (success)
--  - Both enabled actions (whisper/invite) have been attempted
--    AND there is no pending whisper/invite outcome still in flight.
function GRIP:MaybeFinalize(fullName)
  if not fullName or fullName == "" then return false end
  if not _G.GRIPDB or type(GRIPDB.potential) ~= "table" then return false end

  local entry = GRIPDB.potential[fullName]
  if not entry then return false end

  -- If blacklisted, always finalize (but still avoid racing a pending state).
  if self:IsBlacklisted(fullName) then
    -- If something is actively pending, defer; the caller can finalize after the outcome.
    if (state and state.pendingWhisper and state.pendingWhisper[fullName]) or (state and state.pendingInvite and state.pendingInvite[fullName]) then
      if self:IsDebugEnabled(3) then
        self:Trace("Finalize deferred (blacklisted but pending):", fullName)
      end
      return false
    end
    self:Debug("Finalize:", fullName, "(blacklisted)")
    self:RemovePotential(fullName)
    return true
  end

  local cfg = GRIPDB.config or {}
  local whisperDone = (not cfg.whisperEnabled) or entry.whisperAttempted
  local inviteDone = (not cfg.inviteEnabled) or entry.inviteAttempted

  -- If whisper/invite is still pending we keep it in the list.
  if entry.invitePending then
    inviteDone = false
  end
  if state and state.pendingInvite and state.pendingInvite[fullName] then
    inviteDone = false
  end
  if state and state.pendingWhisper and state.pendingWhisper[fullName] then
    whisperDone = false
  end

  if whisperDone and inviteDone then
    self:Debug("Finalize:", fullName, "(done)",
      "whisper=", tostring(entry.whisperSuccess),
      "invite=", tostring(entry.inviteSuccess)
    )
    self:RemovePotential(fullName)
    return true
  end

  return false
end