-- Rev 19
-- GRIP – UI: Home page
--
-- CHANGED (Rev 17):
-- - Add “Blacklist…” action to Potential row right-click menu:
--   - Prompts for an optional reason (StaticPopup edit box).
--   - Adds/updates GRIPDB.blacklist[name] (string reason, may be empty).
--   - Removes the name from Potential and clears any queued/pending actions for that name.
-- - Keeps Rev 16 blacklist list + remove flow intact.
--
-- CHANGED (Rev 18):
-- - Harden “Blacklist…” pipeline cleanup:
--   - Remove blacklisted name from Potential using multiple key variants (Name-Realm, Name, lowercase, etc.).
--   - Clear queued/pending whisper/invite/recruit/action state using best-effort removal across common containers.
--   - Avoid touching whoQueue filters (was never correct to remove a player name from whoQueue).
--
-- CHANGED (Rev 19):
-- - SV schema alignment for manual blacklist UI:
--   - “Blacklist…” now adds/updates GRIPDB.blacklistPerm[name] = {at, reason} (perm), not GRIPDB.blacklist.
--   - Blacklist panel now displays permanent blacklist entries; header shows perm + temp counts.
--   - Unblacklist confirm now removes from blacklistPerm.
--   - Defense-in-depth: right-click “Invite to Guild” calls GRIP:BL_ExecutionGate(...) immediately
--     before GuildInvite(), and refuses execution if the gate helper is missing.

local ADDON_NAME, GRIP = ...
local state = GRIP.state
local W = GRIP.UIW

-- Extra right inset for UIPanelScrollFrameTemplate so the scrollbar/art never clips outside the page.
-- (Matches the same "give it room" approach used in scroll pages.)
local HOME_SCROLL_RIGHT_INSET = 34

-- FauxScrollFrame padding constants
local POT_HEADER_H = 20
local POT_ROW_H    = 18
local POT_ROWS_MIN = 10

-- Blacklist panel shell/constants
local BL_PANEL_WIDE_WIDTH = 320
local BL_PANEL_STACK_H    = 160
local BL_GAP              = 10

-- Blacklist list constants
local BL_ROW_H    = 18
local BL_ROWS_MAX = 12

-- Minimum width for the Potential panel when in two-column mode.
-- This is sized so the header can always fit through Zone + W + I without crossing into the Blacklist region.
local POT_MIN_TWO_COL_W = 500

local function EnsureHomeDBTables()
  if not _G.GRIPDB then return false end

  if type(GRIPDB.config) ~= "table" then GRIPDB.config = {} end
  if type(GRIPDB.potential) ~= "table" then GRIPDB.potential = {} end
  if type(GRIPDB.blacklist) ~= "table" then GRIPDB.blacklist = {} end
  if type(GRIPDB.blacklistPerm) ~= "table" then GRIPDB.blacklistPerm = {} end

  return true
end

local function HasDB()
  if not EnsureHomeDBTables() then return false end
  return (type(GRIPDB.config) == "table") and true or false
end

local function SecondsLeft(untilT)
  local now = GetTime()
  local left = (untilT or 0) - now
  if left < 0 then left = 0 end
  return left
end

local function GetScanCooldown()
  local cfg = (GRIPDB and GRIPDB.config) or nil
  local v = tonumber(cfg and cfg.minWhoInterval) or 15
  if v < 15 then v = 15 end
  return v
end

-- Unified recruit (whisper+invite) cooldown comes from shared state + UI mirror.
local function GetRecruitCooldownUntil()
  local uiUntil = (state.ui and state.ui._actionCooldownUntil) or 0
  local sharedUntil = tonumber(state.actionCooldownUntil) or 0
  if sharedUntil > uiUntil then return sharedUntil end
  return uiUntil
end

-- Post cooldown is UI-local only (so recruiting doesn't lock posting and vice versa).
local function GetPostCooldownUntil()
  return (state.ui and state.ui._postCooldownUntil) or 0
end

local function SetEnabledSafe(widget, enabled)
  if not widget then return end
  enabled = enabled and true or false

  if widget.SetEnabled then
    widget:SetEnabled(enabled)
  elseif enabled and widget.Enable then
    widget:Enable()
  elseif (not enabled) and widget.Disable then
    widget:Disable()
  end

  if widget.SetAlpha then
    widget:SetAlpha(enabled and 1 or 0.6)
  end
end

-- ----------------------------
-- Potential table helpers
-- ----------------------------

local function SafeUpper(s)
  if type(s) ~= "string" then return "" end
  return string.upper(s)
end

local function ClassTokenFromEntryClass(cls)
  if type(cls) ~= "string" then return nil end
  local u = SafeUpper(cls)
  if u == "" then return nil end

  if _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[u] then
    return u
  end

  if _G.LOCALIZED_CLASS_NAMES_MALE then
    for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do
      if SafeUpper(loc) == u then return token end
    end
  end
  if _G.LOCALIZED_CLASS_NAMES_FEMALE then
    for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
      if SafeUpper(loc) == u then return token end
    end
  end

  return nil
end

local function ClassShort(tokenOrName)
  local t = ClassTokenFromEntryClass(tokenOrName) or tokenOrName
  if type(t) ~= "string" then return "?" end
  local u = SafeUpper(t)
  if #u >= 3 then return string.sub(u, 1, 3) end
  return u
end

local function SetStatusIcon(tex, attempted, success, pending)
  if not tex then return end

  if not attempted then
    tex:Hide()
    return
  end

  tex:Show()

  if pending then
    tex:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Waiting")
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetAlpha(1)
    return
  end

  if success == true then
    tex:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetAlpha(1)
  elseif success == false then
    tex:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetAlpha(1)
  else
    tex:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Waiting")
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetAlpha(1)
  end
end

local function GetEntryTimestamp(e)
  if type(e) ~= "table" then return 0 end
  local candidates = { e.foundAt, e.seenAt, e.addedAt, e.firstSeen, e.createdAt, e.ts, e.t }
  for i = 1, #candidates do
    local v = tonumber(candidates[i])
    if v and v > 0 then return v end
  end
  return 0
end

local function SortPotentialNewestFirst(names)
  if type(names) ~= "table" then return names end
  table.sort(names, function(a, b)
    if a == b then return false end
    local ea = GRIPDB.potential and GRIPDB.potential[a] or nil
    local eb = GRIPDB.potential and GRIPDB.potential[b] or nil
    local ta = GetEntryTimestamp(ea)
    local tb = GetEntryTimestamp(eb)
    if ta ~= tb then return ta > tb end
    return tostring(a) < tostring(b)
  end)
  return names
end

local function BuildPotentialNameList()
  local t = {}
  if not (GRIPDB and GRIPDB.potential) then return t end
  for name, _ in pairs(GRIPDB.potential) do
    if type(name) == "string" and name ~= "" then
      t[#t + 1] = name
    end
  end
  return SortPotentialNewestFirst(t)
end

local function ClampFontString(fs, w)
  if not fs then return end
  if fs.SetWidth then fs:SetWidth(w) end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
end

-- ----------------------------
-- Blacklist helpers
-- ----------------------------

local function BuildBlacklistNameList()
  local t = {}
  if not (GRIPDB and GRIPDB.blacklistPerm) then return t end

  -- Prefer canonical helper (also normalizes legacy boolean entries)
  if GRIP and type(GRIP.GetPermanentBlacklistNames) == "function" then
    local ok, names = pcall(function() return GRIP:GetPermanentBlacklistNames() end)
    if ok and type(names) == "table" then
      return names
    end
  end

  for name, v in pairs(GRIPDB.blacklistPerm) do
    if type(name) == "string" and name ~= "" then
      if v == true or type(v) == "table" or type(v) == "string" then
        t[#t + 1] = name
      end
    end
  end
  table.sort(t, function(a, b) return tostring(a) < tostring(b) end)
  return t
end

local function GetBlacklistReason(e)
  if type(e) == "string" then return e end
  if e == true then return "" end
  if type(e) ~= "table" then return "" end
  local r = e.reason or e.note or e.msg or e.text
  if type(r) ~= "string" then return "" end
  return r
end

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

local function ConfirmUnblacklist(name)
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

local function Trim(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Lower(s)
  if type(s) ~= "string" then return "" end
  return s:lower()
end

local function GetRealmToken()
  local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
  r = Trim(r)
  r = r:gsub("%s+", "")
  return r
end

local function BuildNameKeyVariants(fullName)
  fullName = Trim(fullName)
  if fullName == "" then return {} end

  local out = {}
  local function add(k)
    k = Trim(k)
    if k == "" then return end
    out[#out + 1] = k
  end

  add(fullName)

  local base, realm = fullName:match("^([^%-]+)%-(.+)$")
  if base and realm then
    add(base)
  else
    base = fullName
    local r = GetRealmToken()
    if r ~= "" then
      add(("%s-%s"):format(base, r))
    end
  end

  local n = #out
  for i = 1, n do
    add(Lower(out[i]))
  end

  return out
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
    if type(n) == "string" and Lower(Trim(n)) == nameLower then
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
    if type(k) == "string" and Lower(Trim(k)) == nameLower then
      map[k] = nil
      changed = true
    else
      local n = EntryNameOf(v)
      if type(n) == "string" and Lower(Trim(n)) == nameLower then
        map[k] = nil
        changed = true
      end
    end
  end
  return changed
end

local function ClearNameFromQueues(name)
  if type(name) ~= "string" or name == "" then return end

  local variants = BuildNameKeyVariants(name)
  if #variants == 0 then variants = { name, Lower(name) } end

  -- Clear from Potential using variants (direct + API if present)
  if type(GRIP.RemovePotential) == "function" then
    for _, k in ipairs(variants) do
      pcall(function() GRIP:RemovePotential(k) end)
    end
  end
  if GRIPDB and type(GRIPDB.potential) == "table" then
    for _, k in ipairs(variants) do
      if GRIPDB.potential[k] ~= nil then
        GRIPDB.potential[k] = nil
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
    local dbt = GRIPDB and GRIPDB[key]

    for _, k in ipairs(variants) do
      local kl = Lower(Trim(k))

      if type(t) == "table" then
        RemoveFromArray(t, kl)
        RemoveFromMapByName(t, kl)
        -- If it's a "pending" record table that stores a single target field, nuke it if it matches.
        local tn = EntryNameOf(t)
        if type(tn) == "string" and Lower(Trim(tn)) == kl then
          state[key] = {}
        end
      elseif type(t) == "string" then
        if Lower(Trim(t)) == kl then state[key] = nil end
      end

      if type(dbt) == "table" then
        RemoveFromArray(dbt, kl)
        RemoveFromMapByName(dbt, kl)
      elseif type(dbt) == "string" then
        if Lower(Trim(dbt)) == kl then GRIPDB[key] = nil end
      end
    end
  end
end

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
        reason = Trim(self.editBox:GetText() or "")
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

      -- Remove from potential and any action queues/pending (Rev 18 hardened)
      ClearNameFromQueues(n)

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

local function PromptBlacklistAdd(name)
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
    ClearNameFromQueues(name)
    GRIP:Print(("Blacklisted %s."):format(name))
    GRIP:UpdateUI()
  end
end

local function IsCurrentlyBlacklisted(name)
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
-- Row context menu (right-click)
-- ----------------------------

local function EnsureRowMenu(home)
  if home and home._potMenu then return end
  local menu = CreateFrame("Frame", "GRIP_PotentialRowMenu", UIParent, "UIDropDownMenuTemplate")
  if home then home._potMenu = menu end
  return menu
end

local function ShowRowMenu(home, anchor, name)
  if type(name) ~= "string" or name == "" then return end
  if not (UIDropDownMenu_Initialize and ToggleDropDownMenu) then return end

  local menu = EnsureRowMenu(home)
  if not menu then return end

  menu._name = name

  UIDropDownMenu_Initialize(menu, function(self, level)
    if not level then return end

    local n = self._name
    if type(n) ~= "string" or n == "" then return end

    local info

    info = UIDropDownMenu_CreateInfo()
    info.isTitle = true
    info.notCheckable = true
    info.text = n
    UIDropDownMenu_AddButton(info, level)

    -- Blacklist action (perm)
    local alreadyBL = IsCurrentlyBlacklisted(n)
    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = alreadyBL and "Blacklist… (already blacklisted)" or "Blacklist…"
    info.disabled = alreadyBL
    info.func = function()
      if not HasDB() then return end
      PromptBlacklistAdd(n)
    end
    UIDropDownMenu_AddButton(info, level)

    local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
    local canInvite = (not inCombat) and (GuildInvite ~= nil)

    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = inCombat and "Invite to Guild (disabled in combat)" or "Invite to Guild"
    info.disabled = not canInvite
    info.func = function()
      if not HasDB() then return end
      if InCombatLockdown and InCombatLockdown() then
        GRIP:Print("Cannot invite in combat.")
        return
      end
      if GuildInvite then
        -- Defense-in-depth: gate immediately before protected invite call.
        local okGate, why = false, "missing-gate"
        if GRIP and type(GRIP.BL_ExecutionGate) == "function" then
          okGate, why = GRIP:BL_ExecutionGate(n, { op = "ui_menu_invite", src = "home" })
        end
        if not okGate then
          GRIP:Print(("Invite blocked (%s): %s"):format(tostring(why or "blocked"), n))
          return
        end

        GRIP:Debug("UI: Menu invite " .. n)
        pcall(GuildInvite, n)
      end
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.disabled = true
    info.notCheckable = true
    info.text = " "
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = "Cancel"
    info.func = function() CloseDropDownMenus() end
    UIDropDownMenu_AddButton(info, level)
  end, "MENU")

  ToggleDropDownMenu(1, nil, menu, anchor, 0, 0)
end

-- ----------------------------
-- Blacklist panel (real)
-- ----------------------------

local function EnsureBlacklistShell(home)
  if not home or home._blReady then return end
  home._blReady = true

  local bl = CreateFrame("Frame", nil, home)
  bl:Hide()
  home.blFrame = bl

  local header = CreateFrame("Frame", nil, bl)
  header:SetHeight(POT_HEADER_H)
  header:SetPoint("TOPLEFT", bl, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", bl, "TOPRIGHT", 0, 0)
  bl.header = header

  header.bg = header:CreateTexture(nil, "BACKGROUND")
  header.bg:SetAllPoints(header)
  header.bg:SetColorTexture(1, 1, 1, 0.06)

  header.line = header:CreateTexture(nil, "BORDER")
  header.line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  header.line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  header.line:SetHeight(1)
  header.line:SetColorTexture(1, 1, 1, 0.10)

  header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header.title:SetPoint("LEFT", header, "LEFT", 6, 0)
  header.title:SetJustifyH("LEFT")
  header.title:SetText("Blacklist")

  -- Column labels
  local function H(text)
    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
  end
  bl.hName = H("Name")
  bl.hReason = H("Reason")

  -- Body background (subtle)
  bl.bg = bl:CreateTexture(nil, "BACKGROUND")
  bl.bg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  bl.bg:SetPoint("BOTTOMRIGHT", bl, "BOTTOMRIGHT", 0, 0)
  bl.bg:SetColorTexture(1, 1, 1, 0.02)

  -- FauxScrollFrame
  local sf = CreateFrame("ScrollFrame", nil, bl, "FauxScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  sf:SetPoint("BOTTOMRIGHT", bl, "BOTTOMRIGHT", -2, 0)
  bl.scroll = sf

  -- Empty state
  bl.empty = bl:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  bl.empty:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 6, -10)
  bl.empty:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -6, -10)
  bl.empty:SetJustifyH("LEFT")
  bl.empty:SetJustifyV("TOP")
  bl.empty:SetText("Permanent blacklist is empty.\nTip: right-click a Potential entry to add it.")
  bl.empty:Hide()

  -- Rows
  bl.rows = {}
  for i = 1, BL_ROWS_MAX do
    local row = CreateFrame("Button", nil, bl)
    row:SetHeight(BL_ROW_H)
    row:Hide()

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints(row)
    row.stripe:SetColorTexture(1, 1, 1, 0.035)
    row.stripe:Hide()

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:RegisterForClicks("LeftButtonUp")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end

    row.reason = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.reason:SetJustifyH("LEFT")
    if row.reason.SetWordWrap then row.reason:SetWordWrap(false) end

    row._nameKey = nil

    row:SetScript("OnClick", function(self)
      if not HasDB() then return end
      local n = self._nameKey
      if type(n) ~= "string" or n == "" then return end
      ConfirmUnblacklist(n)
    end)

    bl.rows[i] = row
  end

  local function OnScroll()
    GRIP:UI_UpdateHome()
  end
  sf:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, BL_ROW_H, OnScroll)
  end)
end

local function LayoutBlacklistPanel(home)
  if not home or not home.blFrame or not home.blFrame.header then return end
  local bl = home.blFrame
  local w = tonumber(bl:GetWidth()) or 0
  if w <= 0 then return end

  local usable = w - 12
  if usable < 140 then usable = 140 end

  local pad = 6
  local wName = 110
  local minReason = 60
  local wReason = usable - (pad + wName + pad)
  if wReason < minReason then
    wReason = minReason
    wName = math.max(80, usable - (pad + wReason + pad))
  end

  local x = pad
  bl.hName:ClearAllPoints()
  bl.hName:SetPoint("LEFT", bl.header, "LEFT", x, 0)
  ClampFontString(bl.hName, wName)
  x = x + wName + pad

  bl.hReason:ClearAllPoints()
  bl.hReason:SetPoint("LEFT", bl.header, "LEFT", x, 0)
  ClampFontString(bl.hReason, wReason)

  for i = 1, #(bl.rows or {}) do
    local row = bl.rows[i]
    row:ClearAllPoints()
    if i == 1 then
      row:SetPoint("TOPLEFT", bl.scroll, "TOPLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", bl.scroll, "TOPRIGHT", 0, 0)
    else
      row:SetPoint("TOPLEFT", bl.rows[i - 1], "BOTTOMLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", bl.rows[i - 1], "BOTTOMRIGHT", 0, 0)
    end

    local rx = pad
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.name, wName)
    rx = rx + wName + pad

    row.reason:ClearAllPoints()
    row.reason:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.reason, wReason)
  end
end

local function UpdateBlacklistRows(home)
  if not home or not home.blFrame or not home.blFrame.scroll or not home.blFrame.rows then return end
  if not HasDB() then return end

  local bl = home.blFrame
  local names = BuildBlacklistNameList()
  bl._names = names

  local total = #names
  local scroll = bl.scroll
  local offset = FauxScrollFrame_GetOffset(scroll) or 0

  FauxScrollFrame_Update(scroll, total, #bl.rows, BL_ROW_H)

  local tempCount = (GRIP and GRIP.Count and GRIP:Count(GRIPDB.blacklist)) or 0
  if total == 0 then
    if bl.empty then
      if tempCount > 0 then
        bl.empty:SetText(("No permanent blacklist entries.\nTemp blacklist active: %d.\nTip: right-click a Potential entry to add a permanent entry."):format(tempCount))
      else
        bl.empty:SetText("Permanent blacklist is empty.\nTip: right-click a Potential entry to add it.")
      end
      bl.empty:Show()
    end
  else
    if bl.empty then bl.empty:Hide() end
  end

  for i = 1, #bl.rows do
    local row = bl.rows[i]
    local idx = i + offset
    local name = names[idx]
    if name then
      local e = GRIPDB.blacklistPerm[name]
      row._nameKey = name
      row.name:SetText(name)

      local reason = GetBlacklistReason(e)
      if reason == "" then
        row.reason:SetText("Click to remove")
      else
        row.reason:SetText(reason)
      end

      if row.stripe then
        if (idx % 2) == 0 then row.stripe:Show() else row.stripe:Hide() end
      end

      row:Show()
    else
      row._nameKey = nil
      if row.stripe then row.stripe:Hide() end
      row:Hide()
    end
  end
end

-- ----------------------------
-- Layout
-- ----------------------------

local function LayoutButtons(home)
  if not home then return end

  local w = tonumber(home:GetWidth()) or 0
  if w <= 0 then return end

  local padL = 4
  local padR = 4
  local usable = w - padL - padR
  if usable < 160 then usable = 160 end

  local yTop = -24

  home.btnScan:ClearAllPoints()
  home.btnWhisperInvite:ClearAllPoints()
  home.btnPostNext:ClearAllPoints()
  home.btnClear:ClearAllPoints()

  home.btnScan:SetPoint("TOPLEFT", home, "TOPLEFT", padL, yTop)

  local narrow = usable < 420

  if narrow then
    home.btnClear:SetPoint("TOPRIGHT", home, "TOPRIGHT", -padR, yTop)

    home.btnWhisperInvite:SetPoint("TOPLEFT", home.btnScan, "BOTTOMLEFT", 0, -6)
    home.btnPostNext:SetPoint("LEFT", home.btnWhisperInvite, "RIGHT", 8, 0)

    home.hint:ClearAllPoints()
    home.hint:SetPoint("TOPLEFT", home.btnWhisperInvite, "BOTTOMLEFT", 0, -6)
  else
    home.btnWhisperInvite:SetPoint("LEFT", home.btnScan, "RIGHT", 8, 0)
    home.btnPostNext:SetPoint("LEFT", home.btnWhisperInvite, "RIGHT", 8, 0)
    home.btnClear:SetPoint("TOPRIGHT", home, "TOPRIGHT", -padR, yTop)

    home.hint:ClearAllPoints()
    home.hint:SetPoint("TOPLEFT", home.btnScan, "BOTTOMLEFT", 0, -6)
  end
end

local function LayoutHomePanels(home)
  if not home or not home.potFrame then return end
  EnsureBlacklistShell(home)

  local topY = -74
  local bottomY = 4
  local leftX = 4
  local rightX = -HOME_SCROLL_RIGHT_INSET

  if home.btnWhisperInvite and home.btnWhisperInvite:GetPoint(1) == "TOPLEFT" then
    topY = -96
  end

  local w = tonumber(home:GetWidth()) or 0

  -- Compute actual content width available between leftX and right inset.
  local contentW = w - leftX - HOME_SCROLL_RIGHT_INSET
  if contentW < 0 then contentW = 0 end

  -- Two-column is only allowed if the Potential panel can still be at least POT_MIN_TWO_COL_W wide.
  local potWIfTwo = contentW - BL_PANEL_WIDE_WIDTH - BL_GAP
  local wideEnoughForTwo = (potWIfTwo >= POT_MIN_TWO_COL_W)

  home.potFrame:ClearAllPoints()
  home.blFrame:ClearAllPoints()

  if wideEnoughForTwo then
    -- Right column (Blacklist) stays pinned to the right.
    home.blFrame:SetPoint("TOPRIGHT", home, "TOPRIGHT", rightX, topY)
    home.blFrame:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", rightX, bottomY)
    home.blFrame:SetWidth(BL_PANEL_WIDE_WIDTH)
    home.blFrame:Show()

    -- Left column (Potential) gets an explicit width to avoid any overlap at the seam.
    home.potFrame:SetPoint("TOPLEFT", home, "TOPLEFT", leftX, topY)
    home.potFrame:SetPoint("BOTTOMLEFT", home, "BOTTOMLEFT", leftX, bottomY)
    home.potFrame:SetWidth(potWIfTwo)
  else
    home.blFrame:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", rightX, bottomY)
    home.blFrame:SetPoint("BOTTOMLEFT", home, "BOTTOMLEFT", leftX, bottomY)
    home.blFrame:SetHeight(BL_PANEL_STACK_H)
    home.blFrame:Show()

    home.potFrame:SetPoint("TOPLEFT", home, "TOPLEFT", leftX, topY)
    home.potFrame:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", rightX, bottomY + BL_PANEL_STACK_H + BL_GAP)
  end
end

local function EnsurePotentialTable(home)
  if not home or home._potReady then return end
  home._potReady = true

  local pot = CreateFrame("Frame", nil, home)
  pot:SetPoint("TOPLEFT", home, "TOPLEFT", 4, -74)
  pot:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", -HOME_SCROLL_RIGHT_INSET, 4)
  home.potFrame = pot

  local header = CreateFrame("Frame", nil, pot)
  header:SetPoint("TOPLEFT", pot, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", pot, "TOPRIGHT", 0, 0)
  header:SetHeight(POT_HEADER_H)
  header:SetClipsChildren(true) -- prevent header text from drawing outside
  home.potHeader = header

  header.bg = header:CreateTexture(nil, "BACKGROUND")
  header.bg:SetAllPoints(header)
  header.bg:SetColorTexture(1, 1, 1, 0.06)

  header.line = header:CreateTexture(nil, "BORDER")
  header.line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  header.line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  header.line:SetHeight(1)
  header.line:SetColorTexture(1, 1, 1, 0.10)

  local function H(text)
    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
  end

  home.hName   = H("Name")
  home.hLvl    = H("Lvl")
  home.hClass  = H("Class")
  home.hRace   = H("Race")
  home.hZone   = H("Zone")
  home.hW      = H("W")
  home.hI      = H("I")

  local sf = CreateFrame("ScrollFrame", nil, pot, "FauxScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  sf:SetPoint("BOTTOMRIGHT", pot, "BOTTOMRIGHT", -2, 0)
  home.potScroll = sf

  local empty = pot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("CENTER", pot, "CENTER", 0, 0)
  empty:SetText("No potential candidates yet. Click Scan to begin.")
  empty:Hide()
  home.potEmpty = empty

  EnsureRowMenu(home)

  home.potRows = {}
  for i = 1, 30 do
    local row = CreateFrame("Button", nil, pot)
    row:SetHeight(POT_ROW_H)

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints(row)
    row.stripe:SetColorTexture(1, 1, 1, 0.045)
    row.stripe:Hide()

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:Hide()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end

    row.lvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.lvl:SetJustifyH("LEFT")
    if row.lvl.SetWordWrap then row.lvl:SetWordWrap(false) end

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(14, 14)
    row.classIcon:Hide()

    row.classTxt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.classTxt:SetJustifyH("LEFT")
    if row.classTxt.SetWordWrap then row.classTxt:SetWordWrap(false) end

    row.race = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.race:SetJustifyH("LEFT")
    if row.race.SetWordWrap then row.race:SetWordWrap(false) end

    row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.zone:SetJustifyH("LEFT")
    if row.zone.SetWordWrap then row.zone:SetWordWrap(false) end

    row.wIcon = row:CreateTexture(nil, "OVERLAY")
    row.wIcon:SetSize(14, 14)
    row.wIcon:Hide()

    row.iIcon = row:CreateTexture(nil, "OVERLAY")
    row.iIcon:SetSize(14, 14)
    row.iIcon:Hide()

    row._nameKey = nil

    row:SetScript("OnClick", function(self, button)
      if button ~= "RightButton" then return end
      if not HasDB() then return end
      local n = self._nameKey
      if type(n) ~= "string" or n == "" then return end
      ShowRowMenu(home, self, n)
    end)

    home.potRows[i] = row
  end

  local function OnScroll()
    GRIP:UI_UpdateHome()
  end
  sf:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, POT_ROW_H, OnScroll)
  end)

  EnsureBlacklistShell(home)
end

local function LayoutPotentialTable(home)
  if not home or not home.potFrame then return end

  local pot = home.potFrame
  local w = tonumber(pot:GetWidth()) or 0
  if w <= 0 then return end

  local usable = w - 18
  if usable < 300 then usable = 300 end

  local pad = 6
  local wLvl   = 36
  local wClass = 70
  local wRace  = 78
  local wWI    = 22
  local wName  = 140

  local fixed = pad + wName + wLvl + wClass + wRace + wWI + wWI + (pad * 6)
  local wZone = usable - fixed

  if wZone < 80 then
    local deficit = 80 - wZone
    wZone = 80
    wName = math.max(100, wName - deficit)
  end

  local seamPad = 4

  local x = pad
  home.hName:ClearAllPoints()
  home.hName:SetPoint("LEFT", home.potHeader, "LEFT", x, 0)
  ClampFontString(home.hName, wName)
  x = x + wName + pad

  home.hLvl:ClearAllPoints()
  home.hLvl:SetPoint("LEFT", home.potHeader, "LEFT", x, 0)
  ClampFontString(home.hLvl, wLvl)
  x = x + wLvl + pad

  home.hClass:ClearAllPoints()
  home.hClass:SetPoint("LEFT", home.potHeader, "LEFT", x, 0)
  ClampFontString(home.hClass, wClass)
  x = x + wClass + pad

  home.hRace:ClearAllPoints()
  home.hRace:SetPoint("LEFT", home.potHeader, "LEFT", x, 0)
  ClampFontString(home.hRace, wRace)
  x = x + wRace + pad

  home.hZone:ClearAllPoints()
  home.hZone:SetPoint("LEFT", home.potHeader, "LEFT", x, 0)
  ClampFontString(home.hZone, wZone)
  x = x + wZone + pad

  home.hW:ClearAllPoints()
  home.hW:SetPoint("LEFT", home.potHeader, "LEFT", x + seamPad, 0)
  ClampFontString(home.hW, wWI)
  x = x + wWI + pad

  home.hI:ClearAllPoints()
  home.hI:SetPoint("LEFT", home.potHeader, "LEFT", x + seamPad, 0)
  ClampFontString(home.hI, wWI)

  for i = 1, #home.potRows do
    local row = home.potRows[i]
    row:ClearAllPoints()
    if i == 1 then
      row:SetPoint("TOPLEFT", home.potScroll, "TOPLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", home.potScroll, "TOPRIGHT", 0, 0)
    else
      row:SetPoint("TOPLEFT", home.potRows[i - 1], "BOTTOMLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", home.potRows[i - 1], "BOTTOMRIGHT", 0, 0)
    end

    local rx = pad

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.name, wName)
    rx = rx + wName + pad

    row.lvl:ClearAllPoints()
    row.lvl:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.lvl, wLvl)
    rx = rx + wLvl + pad

    row.classIcon:ClearAllPoints()
    row.classIcon:SetPoint("LEFT", row, "LEFT", rx, 0)

    row.classTxt:ClearAllPoints()
    row.classTxt:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)
    ClampFontString(row.classTxt, wClass - 18)
    rx = rx + wClass + pad

    row.race:ClearAllPoints()
    row.race:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.race, wRace)
    rx = rx + wRace + pad

    row.zone:ClearAllPoints()
    row.zone:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.zone, wZone)
    rx = rx + wZone + pad

    row.wIcon:ClearAllPoints()
    row.wIcon:SetPoint("LEFT", row, "LEFT", rx + 2 + seamPad, 0)
    rx = rx + wWI + pad

    row.iIcon:ClearAllPoints()
    row.iIcon:SetPoint("LEFT", row, "LEFT", rx + 2 + seamPad, 0)
  end

  local minH = POT_HEADER_H + 2 + (POT_ROWS_MIN * POT_ROW_H)
  local ph = tonumber(pot:GetHeight()) or 0
  if ph > 0 and ph < minH then
    -- tolerant
  end
end

local function UpdatePotentialRows(home)
  if not home or not home.potScroll or not home.potRows then return end
  if not HasDB() then return end

  local names = BuildPotentialNameList()
  home._potNames = names

  local total = #names
  local scroll = home.potScroll
  local offset = FauxScrollFrame_GetOffset(scroll) or 0

  FauxScrollFrame_Update(scroll, total, #home.potRows, POT_ROW_H)

  if total == 0 then
    if home.potEmpty then home.potEmpty:Show() end
  else
    if home.potEmpty then home.potEmpty:Hide() end
  end

  for i = 1, #home.potRows do
    local row = home.potRows[i]
    local idx = i + offset
    local name = names[idx]
    if name then
      local e = GRIPDB.potential[name] or {}

      row._nameKey = name
      row.name:SetText(name)

      local lvl = e.level and tostring(e.level) or "?"
      row.lvl:SetText(lvl)

      local token = ClassTokenFromEntryClass(e.class)
      if token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token] then
        row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        local tc = CLASS_ICON_TCOORDS[token]
        row.classIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        row.classIcon:Show()
        row.classTxt:SetText(ClassShort(token))
      else
        row.classIcon:Hide()
        row.classTxt:SetText(ClassShort(e.class))
      end

      row.race:SetText(e.race or "?")
      row.zone:SetText(e.zone or e.area or "")

      SetStatusIcon(row.wIcon, e.whisperAttempted, e.whisperSuccess, false)
      SetStatusIcon(row.iIcon, e.inviteAttempted, e.inviteSuccess, e.invitePending)

      if row.stripe then
        if (idx % 2) == 0 then row.stripe:Show() else row.stripe:Hide() end
      end

      row:Show()
    else
      row._nameKey = nil
      if row.stripe then row.stripe:Hide() end
      row:Hide()
    end
  end
end

function GRIP:UI_LayoutHome()
  if not state.ui or not state.ui.home then return end
  local home = state.ui.home
  EnsurePotentialTable(home)
  LayoutButtons(home)
  LayoutHomePanels(home)
  LayoutPotentialTable(home)
  LayoutBlacklistPanel(home)
end

function GRIP:UI_CreateHome(parent)
  local home = CreateFrame("Frame", nil, parent)
  home:SetAllPoints(true)

  home.status = home:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  home.status:SetPoint("TOPLEFT", home, "TOPLEFT", 4, -2)
  home.status:SetJustifyH("LEFT")
  home.status:SetText("…")

  home.btnScan = W.CreateUIButton(home, "Scan", 90, 24, function()
    if not HasDB() then
      GRIP:Print("Home unavailable yet (DB not initialized).")
      return
    end

    GRIP:Debug("UI: Scan pressed")
    local did = GRIP:SendNextWho()
    if did and state.ui then
      state.ui._scanCooldownUntil = GetTime() + GetScanCooldown()
    end
    GRIP:UpdateUI()
  end)
  home.btnScan:SetPoint("TOPLEFT", home, "TOPLEFT", 4, -24)

  home.btnWhisperInvite = W.CreateUIButton(home, "Whisper+Invite Next", 160, 24, function()
    if not HasDB() then
      GRIP:Print("Home unavailable yet (DB not initialized).")
      return
    end

    GRIP:Debug("UI: Whisper+Invite Next pressed")
    GRIP:InviteNext()
    GRIP:UpdateUI()
  end)
  home.btnWhisperInvite:SetPoint("LEFT", home.btnScan, "RIGHT", 8, 0)

  home.btnPostNext = W.CreateUIButton(home, "Post Next", 90, 24, function()
    if not HasDB() then
      GRIP:Print("Home unavailable yet (DB not initialized).")
      return
    end

    GRIP:Debug("UI: PostNext pressed")
    GRIP:PostNext()
    if state.ui then
      state.ui._postCooldownUntil = GetTime() + 0.5
    end
    GRIP:UpdateUI()
  end)
  home.btnPostNext:SetPoint("LEFT", home.btnWhisperInvite, "RIGHT", 8, 0)

  home.btnClear = W.CreateUIButton(home, "Clear", 70, 20, function()
    if not HasDB() then
      GRIP:Print("Home unavailable yet (DB not initialized).")
      return
    end

    wipe(GRIPDB.potential)
    wipe(state.whisperQueue)
    wipe(state.pendingWhisper)
    wipe(state.pendingInvite)
    GRIP:Print("Cleared Potential list.")
    GRIP:UpdateUI()
  end)
  home.btnClear:SetPoint("TOPRIGHT", home, "TOPRIGHT", -4, -24)

  home.hint = home:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  home.hint:SetPoint("TOPLEFT", home.btnScan, "BOTTOMLEFT", 0, -6)
  home.hint:SetText("Tip: /grip help  •  None selected in filters = allow all")

  EnsurePotentialTable(home)

  LayoutButtons(home)
  LayoutHomePanels(home)
  LayoutPotentialTable(home)
  LayoutBlacklistPanel(home)

  return home
end

function GRIP:UI_UpdateHome()
  if not state.ui or not state.ui.home or not state.ui.home:IsShown() then return end
  local f = state.ui
  local home = f.home

  EnsurePotentialTable(home)
  LayoutButtons(home)
  LayoutHomePanels(home)
  LayoutPotentialTable(home)
  LayoutBlacklistPanel(home)

  if not HasDB() then
    if home._initHint then
      home._initHint:Show()
    else
      home._initHint = home:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      home._initHint:SetPoint("TOPLEFT", home.status, "BOTTOMLEFT", 0, -2)
      home._initHint:SetText("Initializing… (database not ready yet)")
      home._initHint:Show()
    end

    home.status:SetText("…")

    SetEnabledSafe(home.btnScan, false)
    SetEnabledSafe(home.btnWhisperInvite, false)
    SetEnabledSafe(home.btnPostNext, false)
    SetEnabledSafe(home.btnClear, false)

    if home.potEmpty then
      home.potEmpty:SetText("Initializing…")
      home.potEmpty:Show()
    end
    for i = 1, #(home.potRows or {}) do
      local r = home.potRows[i]
      if r.stripe then r.stripe:Hide() end
      r:Hide()
    end

    if home.blFrame and home.blFrame.header and home.blFrame.header.title then
      home.blFrame.header.title:SetText("Blacklist")
    end
    if home.blFrame and home.blFrame.empty then
      home.blFrame.empty:Show()
    end
    if home.blFrame and home.blFrame.rows then
      for i = 1, #home.blFrame.rows do
        local r = home.blFrame.rows[i]
        if r.stripe then r.stripe:Hide() end
        r:Hide()
      end
    end

    return
  end

  if home._initHint then home._initHint:Hide() end

  SetEnabledSafe(home.btnScan, true)
  SetEnabledSafe(home.btnWhisperInvite, true)
  SetEnabledSafe(home.btnPostNext, true)
  SetEnabledSafe(home.btnClear, true)

  local pot = self:Count(GRIPDB.potential)
  local blPerm = self:Count(GRIPDB.blacklistPerm)
  local blTemp = self:Count(GRIPDB.blacklist)

  local whoPos = math.max(0, (state.whoIndex - 1))
  local whoTotal = #state.whoQueue
  local wq = #state.whisperQueue
  local pq = #state.postQueue
  local whisperOn = state.whisperTicker and "ON" or "OFF"
  local whoPending = state.pendingWho and " (waiting…)" or ""

  home.status:SetText(
    ("Potential: %d   Blacklist: perm %d, temp %d\nWho: %d/%d%s   WhisperQ: %d (%s)   PostQ: %d"):format(
      pot, blPerm, blTemp, whoPos, whoTotal, whoPending, wq, whisperOn, pq
    )
  )

  if home.blFrame and home.blFrame.header and home.blFrame.header.title then
    home.blFrame.header.title:SetText(("Blacklist (perm %d; temp %d)"):format(blPerm or 0, blTemp or 0))
  end

  local scanLeft = SecondsLeft(f._scanCooldownUntil)
  if scanLeft > 0 then
    home.btnScan:Disable()
    home.btnScan:SetText(("Scan (%.0fs)"):format(math.ceil(scanLeft)))
  else
    home.btnScan:Enable()
    home.btnScan:SetText("Scan")
  end

  local recruitLeft = SecondsLeft(GetRecruitCooldownUntil())
  if recruitLeft > 0 then
    home.btnWhisperInvite:Disable()
  else
    home.btnWhisperInvite:Enable()
  end

  local postLeft = SecondsLeft(GetPostCooldownUntil())
  if postLeft > 0 then
    home.btnPostNext:Disable()
  else
    home.btnPostNext:Enable()
  end

  UpdatePotentialRows(home)
  UpdateBlacklistRows(home)
end