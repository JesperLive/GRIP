-- GRIP: UI Home Page — Popups
-- StaticPopup dialogs for blacklist add/remove confirmation.

local ADDON_NAME, GRIP = ...

local type, tostring, pairs, ipairs, pcall, wipe = type, tostring, pairs, ipairs, pcall, wipe
local time = time

local state = GRIP.state

-- ----------------------------
-- Shared DB guard (promoted)
-- ----------------------------

local function EnsureHomeDBTables()
  if not _G.GRIPDB then return false end
  if not _G.GRIPDB_CHAR then return false end

  if type(GRIPDB_CHAR.config) ~= "table" then GRIPDB_CHAR.config = {} end
  if type(GRIPDB_CHAR.potential) ~= "table" then GRIPDB_CHAR.potential = {} end
  if type(GRIPDB.blacklist) ~= "table" then GRIPDB.blacklist = {} end
  if type(GRIPDB.blacklistPerm) ~= "table" then GRIPDB.blacklistPerm = {} end

  return true
end

function GRIP:HomeHasDB()
  if not EnsureHomeDBTables() then return false end
  return (type(GRIPDB_CHAR.config) == "table") and true or false
end

local HasDB = function() return GRIP:HomeHasDB() end

-- ----------------------------
-- Name helpers
-- ----------------------------

local function Lower(s)
  if type(s) ~= "string" then return "" end
  return s:lower()
end

local function EntryNameOf(v)
  if type(v) == "string" then return v end
  if type(v) ~= "table" then return nil end
  return v.fullName or v.name or v.target or v.player
end

local function RemoveFromArray(t, nameLower)
  if type(t) ~= "table" or type(nameLower) ~= "string" or nameLower == "" then return false end
  local changed = false
  for i = #t, 1, -1 do
    local v = t[i]
    local n = EntryNameOf(v)
    if type(n) == "string" and Lower(GRIP:Trim(n)) == nameLower then
      table.remove(t, i)
      changed = true
    end
  end
  return changed
end

local function RemoveFromMapByName(map, nameLower)
  if type(map) ~= "table" or type(nameLower) ~= "string" or nameLower == "" then return false end
  local changed = false
  for k, v in pairs(map) do
    if type(k) == "string" and Lower(GRIP:Trim(k)) == nameLower then
      map[k] = nil
      changed = true
    else
      local n = EntryNameOf(v)
      if type(n) == "string" and Lower(GRIP:Trim(n)) == nameLower then
        map[k] = nil
        changed = true
      end
    end
  end
  return changed
end

-- ----------------------------
-- Queue cleanup
-- ----------------------------

function GRIP:ClearNameFromQueues(name)
  if type(name) ~= "string" or name == "" then return end

  local variants = GRIP:BuildNameKeyVariants(name)
  if #variants == 0 then variants = { name, Lower(name) } end

  -- Clear from Potential using variants (direct + API if present)
  if type(GRIP.RemovePotential) == "function" then
    for _, k in ipairs(variants) do
      pcall(function() GRIP:RemovePotential(k) end)
    end
  end
  if GRIPDB_CHAR and type(GRIPDB_CHAR.potential) == "table" then
    for _, k in ipairs(variants) do
      if GRIPDB_CHAR.potential[k] ~= nil then
        GRIPDB_CHAR.potential[k] = nil
      end
    end
  end

  -- Best-effort clear of queued/pending state (both state and db, if present)
  local queueKeys = {
    "whisperQueue", "inviteQueue", "recruitQueue", "actionQueue", "postQueue",
    "pendingWhisper", "pendingInvite", "pendingRecruit", "pendingAction",
    "lastWhisperTarget", "lastInviteTarget", "lastRecruitTarget", "lastActionTarget"
  }

  for _, key in ipairs(queueKeys) do
    local t = state and state[key]
    local dbt = GRIPDB_CHAR and GRIPDB_CHAR[key]

    for _, k in ipairs(variants) do
      local kl = Lower(GRIP:Trim(k))

      if type(t) == "table" then
        RemoveFromArray(t, kl)
        RemoveFromMapByName(t, kl)
        -- If it's a "pending" record table that stores a single target field, nuke it if it matches.
        local tn = EntryNameOf(t)
        if type(tn) == "string" and Lower(GRIP:Trim(tn)) == kl then
          state[key] = {}
        end
      elseif type(t) == "string" then
        if Lower(GRIP:Trim(t)) == kl then state[key] = nil end
      end

      if type(dbt) == "table" then
        RemoveFromArray(dbt, kl)
        RemoveFromMapByName(dbt, kl)
      elseif type(dbt) == "string" then
        if Lower(GRIP:Trim(dbt)) == kl then GRIPDB_CHAR[key] = nil end
      end
    end
  end
end

-- ----------------------------
-- Blacklist status check
-- ----------------------------

function GRIP:IsCurrentlyBlacklisted(name)
  if not (HasDB() and type(name) == "string" and name ~= "") then return false end

  if GRIP and type(GRIP.IsBlacklisted) == "function" then
    local ok, r = pcall(function() return GRIP:IsBlacklisted(name) end)
    if ok then return r and true or false end
  end

  if GRIPDB.blacklistPerm and GRIPDB.blacklistPerm[name] ~= nil then
    return true
  end

  if GRIPDB.blacklist and type(GRIPDB.blacklist[name]) == "number" then
    local now = (time and time()) or 0
    return (GRIPDB.blacklist[name] > now) and true or false
  end

  return false
end

-- ----------------------------
-- Unblacklist popup
-- ----------------------------

local function EnsureUnblacklistPopup()
  if not StaticPopupDialogs then return end
  if StaticPopupDialogs["GRIP_UNBLACKLIST_CONFIRM"] then return end

  StaticPopupDialogs["GRIP_UNBLACKLIST_CONFIRM"] = {
    text = "Remove %s from permanent blacklist?",
    button1 = "Remove",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self)
      local n = self.data
      if not n or not HasDB() then return end

      local removed = false
      if GRIP and type(GRIP.UnblacklistPermanent) == "function" then
        local ok, r = pcall(function() return GRIP:UnblacklistPermanent(n) end)
        removed = (ok and r) and true or false
      end
      if not removed and GRIPDB.blacklistPerm and GRIPDB.blacklistPerm[n] ~= nil then
        GRIPDB.blacklistPerm[n] = nil
        removed = true
      end

      if removed then
        GRIP:Print(("Removed %s from permanent blacklist."):format(n))
      end

      GRIP:UpdateUI()
    end,
  }
end

function GRIP:ConfirmUnblacklist(name)
  if not (HasDB() and type(name) == "string" and name ~= "") then return end
  EnsureUnblacklistPopup()
  if StaticPopup_Show then
    StaticPopup_Show("GRIP_UNBLACKLIST_CONFIRM", name, nil, name)
  else
    -- Fallback: no popup system available; remove directly.
    if GRIP and type(GRIP.UnblacklistPermanent) == "function" then
      pcall(function() GRIP:UnblacklistPermanent(name) end)
    end
    if GRIPDB.blacklistPerm then
      GRIPDB.blacklistPerm[name] = nil
    end
    GRIP:Print(("Removed %s from permanent blacklist."):format(name))
    GRIP:UpdateUI()
  end
end

-- ----------------------------
-- Blacklist-add popup
-- ----------------------------

local function EnsureBlacklistAddPopup()
  if not StaticPopupDialogs then return end
  if StaticPopupDialogs["GRIP_BLACKLIST_ADD"] then return end

  StaticPopupDialogs["GRIP_BLACKLIST_ADD"] = {
    text = "Add %s to permanent blacklist?\n(Optional reason)",
    button1 = "Blacklist",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    hasEditBox = true,
    editBoxWidth = 220,
    maxLetters = 120,
    OnShow = function(self)
      if self.editBox then
        self.editBox:SetText("")
        self.editBox:SetFocus()
        self.editBox:HighlightText()
      end
    end,
    OnAccept = function(self)
      local n = self.data
      if not (HasDB() and type(n) == "string" and n ~= "") then return end

      local reason = ""
      if self.editBox then
        reason = GRIP:Trim(self.editBox:GetText() or "")
      end

      -- Canonical schema: permanent entries go in blacklistPerm as {at, reason}.
      if GRIP and type(GRIP.BlacklistPermanent) == "function" then
        pcall(function() GRIP:BlacklistPermanent(n, reason) end)
      else
        GRIPDB.blacklistPerm[n] = { at = (GRIP and GRIP.Now and GRIP:Now()) or (time and time() or 0), reason = tostring(reason or "") }
      end

      -- If this name was also in temp blacklist, clear the exact key to avoid confusing counts.
      if GRIPDB.blacklist and GRIPDB.blacklist[n] ~= nil then
        GRIPDB.blacklist[n] = nil
      end

      -- Remove from potential and any action queues/pending
      GRIP:ClearNameFromQueues(n)

      GRIP:Print(reason ~= "" and ("Blacklisted %s: %s"):format(n, reason) or ("Blacklisted %s."):format(n))
      GRIP:UpdateUI()
    end,
    EditBoxOnEnterPressed = function(self)
      local parent = self:GetParent()
      if parent and parent.button1 and parent.button1.Click then
        parent.button1:Click()
      end
    end,
    EditBoxOnEscapePressed = function(self)
      local parent = self:GetParent()
      if parent and parent.button2 and parent.button2.Click then
        parent.button2:Click()
      end
    end,
  }
end

function GRIP:PromptBlacklistAdd(name)
  if not (HasDB() and type(name) == "string" and name ~= "") then return end
  EnsureBlacklistAddPopup()
  if StaticPopup_Show then
    StaticPopup_Show("GRIP_BLACKLIST_ADD", name, nil, name)
  else
    -- Fallback: no popup, blacklist directly with empty reason.
    if GRIP and type(GRIP.BlacklistPermanent) == "function" then
      pcall(function() GRIP:BlacklistPermanent(name, "") end)
    else
      GRIPDB.blacklistPerm[name] = { at = (GRIP and GRIP.Now and GRIP:Now()) or (time and time() or 0), reason = "" }
    end
    if GRIPDB.blacklist then GRIPDB.blacklist[name] = nil end
    GRIP:ClearNameFromQueues(name)
    GRIP:Print(("Blacklisted %s."):format(name))
    GRIP:UpdateUI()
  end
end

-- ----------------------------
-- Clear Potential confirmation
-- ----------------------------

local function EnsureClearConfirmPopup()
  if not StaticPopupDialogs then return end
  if StaticPopupDialogs["GRIP_CLEAR_POTENTIAL_CONFIRM"] then return end

  StaticPopupDialogs["GRIP_CLEAR_POTENTIAL_CONFIRM"] = {
    text = "Clear all %s candidates from the Potential list?",
    button1 = "Clear",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self)
      if not _G.GRIPDB_CHAR or type(GRIPDB_CHAR.potential) ~= "table" then return end
      wipe(GRIPDB_CHAR.potential)
      local st = GRIP.state
      if st then
        if type(st.whisperQueue) == "table" then wipe(st.whisperQueue) end
        if type(st.pendingWhisper) == "table" then wipe(st.pendingWhisper) end
        if type(st.pendingInvite) == "table" then wipe(st.pendingInvite) end
      end
      GRIP:Print("Cleared Potential list.")
      GRIP:UpdateUI()
    end,
  }
end

function GRIP:ConfirmClearPotential(count)
  EnsureClearConfirmPopup()
  if StaticPopup_Show then
    StaticPopup_Show("GRIP_CLEAR_POTENTIAL_CONFIRM", tostring(count or 0))
  end
end
