-- Rev 2
-- GRIP – Global right-click guild invite hook (UnitPopup / Menu API)
--
-- CHANGED (Rev 1):
-- - Adds a global unit right-click context menu option: "Invite to Guild (GRIP)".
-- - Same-realm only: hides entry for cross-realm targets.
-- - Hardware-event compliant: invite executes only on the menu click.
-- - Defense-in-depth: calls GRIP:BL_ExecutionGate(targetName, context) immediately before GuildInvite().
-- - Combat safe: blocks when InCombatLockdown() is true.
-- - Nil-safe: tolerates missing optional APIs and GRIP not fully ready without throwing.
--
-- CHANGED (Rev 2):
-- - Show the menu entry ONLY when currently valid:
--     * not in combat
--     * in a guild
--     * invite permission (if CanGuildInvite is available)
--     * GuildInvite exists
--     * GRIP + BL_ExecutionGate are available
-- - Harden realm comparisons to tolerate normalized vs display realm strings (spaces/apostrophes/hyphens).
-- - Legacy UnitPopup fallback: add best-effort disabled/isHidden guards to align with “only when valid”.

local ADDON_NAME, GRIP = ...

local MENU_TEXT = "Invite to Guild (GRIP)"
local LEGACY_VALUE = "GRIP_GUILDINVITE"

local function SafeChat(msg)
  msg = tostring(msg or "")
  if GRIP and GRIP.Print then
    GRIP:Print(msg)
    return
  end
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("GRIP: " .. msg)
    return
  end
  print("GRIP:", msg)
end

-- ------------------------------------------------------------
-- Realm/name normalization (same-realm only)
-- ------------------------------------------------------------
local function NormalizeRealmToken(r)
  if type(r) ~= "string" then return "" end
  -- Compare-friendly: remove spaces, hyphens, apostrophes.
  r = r:gsub("%s+", "")
  r = r:gsub("[%-']", "")
  return r
end

local function MyRealmToken()
  local r = ""
  if GetNormalizedRealmName then
    r = GetNormalizedRealmName() or ""
  end
  if r == "" and GetRealmName then
    r = GetRealmName() or ""
  end
  r = NormalizeRealmToken(r)
  if r == "" then return nil end
  return r
end

-- Returns base name ONLY (no realm) when same-realm; returns nil otherwise.
local function NormalizeSameRealmName(name, realmMaybe)
  if type(name) ~= "string" or name == "" then return nil end

  local base, realmInName = strsplit("-", name)
  base = base or name
  if base == "" then return nil end

  local my = MyRealmToken()

  local realmCandidate = realmMaybe
  if (not realmCandidate or realmCandidate == "") and realmInName and realmInName ~= "" then
    realmCandidate = realmInName
  end

  if realmCandidate and realmCandidate ~= "" then
    -- If realm info is present, only allow if it matches ours (conservative).
    if not my then
      return nil
    end
    if NormalizeRealmToken(realmCandidate) == my then
      return base
    end
    return nil
  end

  -- No realm info present: assume same-realm (typical for UnitFullName on same realm).
  return base
end

local function GetSameRealmNameFromUnit(unit)
  if type(unit) ~= "string" or unit == "" then return nil end
  if not UnitExists or not UnitExists(unit) then return nil end
  if UnitIsUnit and UnitIsUnit(unit, "player") then return nil end
  if UnitIsPlayer and not UnitIsPlayer(unit) then return nil end

  local name, realm
  if UnitFullName then
    name, realm = UnitFullName(unit)
  end
  if (not name or name == "") and UnitName then
    name = UnitName(unit)
  end

  return NormalizeSameRealmName(name, realm)
end

-- ------------------------------------------------------------
-- Invite validity checks (safe, non-restricted)
-- ------------------------------------------------------------
local function CanAttemptGuildInvite()
  if not IsInGuild then
    return false, "IsInGuild() is unavailable."
  end
  if not IsInGuild() then
    return false, "You are not in a guild."
  end

  -- Permission check (if available)
  if CanGuildInvite and not CanGuildInvite() then
    return false, "You don't have permission to invite to the guild."
  end

  if not (C_GuildInfo and C_GuildInfo.Invite) and not GuildInvite then
    return false, "Guild invite API is unavailable."
  end

  return true, "ok"
end

local function ShouldShowInvite(targetName)
  if type(targetName) ~= "string" or targetName == "" then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  local okInvite = CanAttemptGuildInvite()
  if not okInvite then
    return false
  end
  if not (GRIP and GRIP.BL_ExecutionGate) then
    return false
  end
  return true
end

local function BuildGateContext(source, menuId, unitOrName)
  return {
    action = "invite",
    phase  = "unitpopup",
    module = "Hooks/UnitPopupInvite",
    source = tostring(source or ""),
    menu   = tostring(menuId or ""),
    target = unitOrName,
  }
end

-- IMPORTANT: This function must call BL_ExecutionGate() immediately before GuildInvite().
local function TryGuildInvite(targetName, ctx)
  if type(targetName) ~= "string" or targetName == "" then return end

  if InCombatLockdown and InCombatLockdown() then
    SafeChat("Cannot send guild invite while in combat.")
    return
  end

  local okInvite, whyInvite = CanAttemptGuildInvite()
  if not okInvite then
    SafeChat(whyInvite)
    return
  end

  if not (GRIP and GRIP.BL_ExecutionGate) then
    SafeChat("GRIP not ready yet (missing BL_ExecutionGate).")
    return
  end

  -- Defense-in-depth: gate MUST be last line before protected call.
  local okGate, reason = GRIP:BL_ExecutionGate(targetName, ctx)
  if not okGate then
    if reason == "blacklisted" then
      SafeChat(("Invite blocked: %s is blacklisted."):format(targetName))
    else
      SafeChat(("Invite blocked (%s): %s"):format(tostring(reason), targetName))
    end
    return
  end

  GRIP:SafeGuildInvite(targetName)
end

-- ------------------------------------------------------------
-- Menu API (Retail) path
-- ------------------------------------------------------------
local function InstallMenuAPI()
  if type(Menu) ~= "table" or type(Menu.ModifyMenu) ~= "function" then
    return false
  end

  local menuIds = {
    "MENU_UNIT_PLAYER",
    "MENU_UNIT_FRIEND",
    "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_GUILD",
  }

  local function ExtractTargetFromContext(contextData)
    if type(contextData) ~= "table" then return nil end

    -- Common candidates (varies by client version / menu type)
    local unit =
      contextData.unit
      or contextData.unitToken
      or contextData.unitType -- best-effort; may be nil/unused on some builds

    local name =
      contextData.name
      or contextData.playerName
      or contextData.fullName
      or contextData.unitName

    local realm =
      contextData.realm
      or contextData.server

    -- Prefer explicit name+realm if available, else fall back to unit
    local normalized = NormalizeSameRealmName(name, realm)
    if normalized then return normalized, unit end

    if unit and UnitExists and UnitExists(unit) then
      return GetSameRealmNameFromUnit(unit), unit
    end

    return nil
  end

  for _, menuId in ipairs(menuIds) do
    pcall(function()
      Menu.ModifyMenu(menuId, function(owner, rootDescription, contextData)
        if not (rootDescription and rootDescription.CreateButton) then return end

        local targetName, unit = ExtractTargetFromContext(contextData)
        if not targetName then return end
        if not ShouldShowInvite(targetName) then return end

        if rootDescription.CreateDivider then
          rootDescription:CreateDivider()
        end

        rootDescription:CreateButton(MENU_TEXT, function()
          local ctx = BuildGateContext("MenuAPI", menuId, unit or targetName)
          TryGuildInvite(targetName, ctx)
        end)
      end)
    end)
  end

  return true
end

-- ------------------------------------------------------------
-- Legacy UnitPopup fallback (only if Menu API is unavailable)
-- ------------------------------------------------------------
local function InsertUnique(t, value)
  if type(t) ~= "table" then return end
  for i = 1, #t do
    if t[i] == value then return end
  end
  t[#t + 1] = value
end

local function InstallLegacyUnitPopup()
  if type(UnitPopupButtons) ~= "table" or type(UnitPopupMenus) ~= "table" then
    return false
  end
  if type(hooksecurefunc) ~= "function" then
    return false
  end

  -- Best-effort: UnitPopup supports per-button disabled/isHidden callbacks on many builds.
  -- If the client ignores these fields, the click path still re-checks everything safely.
  UnitPopupButtons[LEGACY_VALUE] = UnitPopupButtons[LEGACY_VALUE] or {}
  UnitPopupButtons[LEGACY_VALUE].text = MENU_TEXT
  UnitPopupButtons[LEGACY_VALUE].dist = 0
  UnitPopupButtons[LEGACY_VALUE].func = UnitPopupButtons[LEGACY_VALUE].func or function() end

  UnitPopupButtons[LEGACY_VALUE].isHidden = UnitPopupButtons[LEGACY_VALUE].isHidden or function()
    local dropdown = _G.UIDROPDOWNMENU_INIT_MENU
    if type(dropdown) ~= "table" then return true end
    local target =
      NormalizeSameRealmName(dropdown.name, dropdown.server)
      or (dropdown.unit and GetSameRealmNameFromUnit(dropdown.unit))
    if not target then return true end
    return not ShouldShowInvite(target)
  end

  UnitPopupButtons[LEGACY_VALUE].disabled = UnitPopupButtons[LEGACY_VALUE].disabled or function()
    local dropdown = _G.UIDROPDOWNMENU_INIT_MENU
    if type(dropdown) ~= "table" then return true end
    local target =
      NormalizeSameRealmName(dropdown.name, dropdown.server)
      or (dropdown.unit and GetSameRealmNameFromUnit(dropdown.unit))
    if not target then return true end
    return not ShouldShowInvite(target)
  end

  local menus = {
    "PLAYER",
    "FRIEND",
    "PARTY",
    "RAID_PLAYER",
    "GUILD",
  }

  for _, m in ipairs(menus) do
    if type(UnitPopupMenus[m]) == "table" then
      InsertUnique(UnitPopupMenus[m], LEGACY_VALUE)
    end
  end

  if type(UnitPopup_OnClick) == "function" then
    hooksecurefunc("UnitPopup_OnClick", function(btn)
      local value = btn and (btn.value or (btn.GetAttribute and btn:GetAttribute("value"))) or nil
      if value ~= LEGACY_VALUE then return end

      local dropdown = _G.UIDROPDOWNMENU_INIT_MENU
      if type(dropdown) ~= "table" then return end

      local targetName =
        NormalizeSameRealmName(dropdown.name, dropdown.server)
        or (dropdown.unit and GetSameRealmNameFromUnit(dropdown.unit))

      if not targetName then
        SafeChat("GRIP right-click invite only supports same-realm targets.")
        return
      end

      -- Re-check validity at click time (authoritative).
      local ctx = BuildGateContext("UnitPopupLegacy", dropdown.which or "?", dropdown.unit or targetName)
      TryGuildInvite(targetName, ctx)
    end)
  end

  return true
end

-- ------------------------------------------------------------
-- Bootstrap
-- ------------------------------------------------------------
local installed = false

local function TryInstall()
  if installed then return end

  -- Prefer Menu API (Retail).
  if InstallMenuAPI() then
    installed = true
    return
  end

  -- Fallback for older clients / unusual states.
  if InstallLegacyUnitPopup() then
    installed = true
    return
  end
end

do
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LOGIN")
  f:RegisterEvent("ADDON_LOADED")
  f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
      TryInstall()
      f:UnregisterEvent("PLAYER_LOGIN")
      if installed then f:UnregisterEvent("ADDON_LOADED") end
      return
    end
    if event == "ADDON_LOADED" then
      -- If Blizzard menus load late, retry once they appear.
      if not installed and (arg1 == "Blizzard_UnitPopup" or arg1 == "Blizzard_Menu") then
        TryInstall()
      end
      if installed then f:UnregisterEvent("ADDON_LOADED") end
    end
  end)
end