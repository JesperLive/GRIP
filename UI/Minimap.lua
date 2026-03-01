-- Rev 9
-- GRIP – Minimap Button (no external libraries)
--
-- CHANGED (Rev 9):
-- - Fix ring/chrome visual offset: anchor MiniMap-TrackingBorder like LibDBIcon (TOPLEFT + 53x53), not CENTER.
-- - Drag math uses Minimap:GetEffectiveScale() (more accurate when Minimap/cluster is scaled).
-- - Prefer parenting the button to Minimap (reduces scale/anchor weirdness from MinimapCluster).

local ADDON_NAME, GRIP = ...
local btn

local function EnsureMinimapDB()
  _G.GRIPDB = _G.GRIPDB or {}
  GRIPDB.minimap = GRIPDB.minimap or { hide = false, angle = 225 }
end

local function SetButtonPosition()
  if not btn or not Minimap then return end
  EnsureMinimapDB()

  local angle = tonumber(GRIPDB.minimap.angle) or 225
  local rad = math.rad(angle)

  local radius = 80
  local x = math.cos(rad) * radius
  local y = math.sin(rad) * radius

  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CursorAngleDegrees()
  if not Minimap or not Minimap.GetCenter then return 225 end
  if not GetCursorPosition then return 225 end

  local mx, my = Minimap:GetCenter()
  if not mx or not my then return 225 end

  local cx, cy = GetCursorPosition()
  if not cx or not cy then return 225 end

  local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
  if not scale or scale == 0 then scale = 1 end

  cx, cy = cx / scale, cy / scale
  local dx, dy = cx - mx, cy - my

  local a = math.deg(math.atan(dy, dx))
  if a < 0 then a = a + 360 end
  return a
end

local function EnsureUI()
  if not GRIP or not GRIP.CreateUI then return nil end
  GRIP:CreateUI()
  return GRIP.state and GRIP.state.ui
end

local function ShowPage(page)
  local f = EnsureUI()
  if not f then return end

  if (not f:IsShown()) and InCombatLockdown and InCombatLockdown() then
    GRIP:Print("Cannot open GRIP window in combat.")
    return
  end

  if not f:IsShown() then
    f:Show()
  end
  if GRIP.ShowPage then
    GRIP:ShowPage(page or "home")
  end
end

local function ToggleHome()
  local f = EnsureUI()
  if not f then return end

  if f:IsShown() then
    f:Hide()
    return
  end

  if InCombatLockdown and InCombatLockdown() then
    GRIP:Print("Cannot open GRIP window in combat.")
    return
  end

  f:Show()
  if GRIP.ShowPage then
    GRIP:ShowPage("home")
  end
end

local function CreateMinimapButtonFrame()
  local parent = Minimap or UIParent
  local ok, b = pcall(CreateFrame, "Button", "GRIP_MinimapButton", parent, "MinimapButtonTemplate")
  if ok and b then return b, true end
  b = CreateFrame("Button", "GRIP_MinimapButton", parent)
  return b, false
end

local function EnsureFallbackHighlightAndPushed(b)
  if not b then return end
  if b.GetHighlightTexture and b:GetHighlightTexture() then
    return
  end

  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  hl:SetBlendMode("ADD")
  hl:SetAllPoints(b)
  b:SetHighlightTexture(hl)

  local pushed = b:CreateTexture(nil, "ARTWORK")
  pushed:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  pushed:SetBlendMode("ADD")
  pushed:SetAllPoints(b)
  pushed:SetAlpha(0.35)
  b:SetPushedTexture(pushed)
end

-- Our ring: anchored like LibDBIcon (TOPLEFT), because the bitmap is not visually centered when CENTER-anchored.
local function EnsureOurRing(b)
  if not b or b._gripRing then return end
  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(53, 53)
  ring:ClearAllPoints()
  ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  if ring.SetDrawLayer then
    ring:SetDrawLayer("OVERLAY", 7)
  end
  b._gripRing = ring
end

local function HideTexture(t)
  if not t then return end
  t:Hide()
  t:SetAlpha(0)
end

-- Hide template/skin chrome that is likely the mis-centered ring.
-- (We keep highlight/pushed behavior; we only remove chrome.)
local function HideTemplateRings(b)
  if not b then return end

  -- Template normal texture is often the ring/chrome.
  if b.GetNormalTexture then
    HideTexture(b:GetNormalTexture())
  end

  if not b.GetRegions then return end
  local ht = b.GetHighlightTexture and b:GetHighlightTexture() or nil
  local pt = b.GetPushedTexture and b:GetPushedTexture() or nil

  local regions = { b:GetRegions() }
  for i = 1, #regions do
    local r = regions[i]
    if r
      and r.GetObjectType
      and r:GetObjectType() == "Texture"
      and r ~= b._gripRing
      and r ~= b.icon
      and r ~= b.Icon
      and r ~= ht
      and r ~= pt
    then
      local w, h = r:GetSize()
      if w and h and w >= 40 and h >= 40 then
        r:Hide()
        r:SetAlpha(0)
      end
    end
  end
end

local function SetupIcon(b, isTemplate)
  local icon = b and (b.Icon or b.icon)
  if not icon then
    icon = b:CreateTexture(nil, "ARTWORK")
    b.icon = icon
  end

  icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  icon:ClearAllPoints()
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6)
  icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -7, 6)

  -- If we're not using the template, add our own circular mask.
  if not isTemplate then
    if not b._gripIconMask then
      local m = b:CreateMaskTexture()
      m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
      m:SetAllPoints(icon)
      icon:AddMaskTexture(m)
      b._gripIconMask = m
    end
  end
end

local function ApplyVisuals(b, isTemplate)
  if not b then return end

  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  if b.SetFrameLevel then b:SetFrameLevel(8) end
  b:SetMovable(true)
  b:EnableMouse(true)

  if isTemplate then
    -- Kill unreliable template/skin ring, then use our own ring (anchored correctly).
    HideTemplateRings(b)
    SetupIcon(b, true)
    EnsureOurRing(b)

    -- Some skins re-apply anchors/textures on show; re-hide and re-assert our ring.
    if not b._gripRehideOnShow then
      b._gripRehideOnShow = true
      b:HookScript("OnShow", function(self)
        HideTemplateRings(self)
        EnsureOurRing(self)
        if self._gripRing then
          self._gripRing:ClearAllPoints()
          self._gripRing:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
          self._gripRing:Show()
          self._gripRing:SetAlpha(1)
        end
      end)
    end
  else
    EnsureFallbackHighlightAndPushed(b)
    SetupIcon(b, false)
    EnsureOurRing(b)
  end
end

function GRIP:CreateMinimapButton()
  EnsureMinimapDB()
  if btn then return end
  if not Minimap then return end

  local isTemplate
  btn, isTemplate = CreateMinimapButtonFrame()
  ApplyVisuals(btn, isTemplate)

  btn:RegisterForDrag("LeftButton")
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")

  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("GRIP", 1, 1, 1)
    GameTooltip:AddLine("Left-click: Toggle window (Home)", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Middle-click: Settings", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: Ads", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: Move button", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("/grip minimap off  (hide)", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  btn:SetScript("OnClick", function(self, button)
    if button == "MiddleButton" then
      ShowPage("settings")
      return
    end
    if button == "RightButton" then
      ShowPage("ads")
      return
    end
    ToggleHome()
  end)

  btn._dragAngle = nil
  btn._dragNextAt = 0

  btn:SetScript("OnDragStart", function(self)
    self._dragAngle = CursorAngleDegrees()
    self._dragNextAt = 0

    self:SetScript("OnUpdate", function()
      local now = GetTime and GetTime() or 0
      if now < (self._dragNextAt or 0) then return end
      self._dragNextAt = now + 0.02

      local a = CursorAngleDegrees()
      self._dragAngle = a

      local rad = math.rad(a)
      local radius = 80
      local x = math.cos(rad) * radius
      local y = math.sin(rad) * radius

      self:ClearAllPoints()
      self:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end)
  end)

  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    EnsureMinimapDB()

    if type(self._dragAngle) == "number" then
      GRIPDB.minimap.angle = self._dragAngle
    end
    self._dragAngle = nil

    SetButtonPosition()
  end)

  SetButtonPosition()
  self:UpdateMinimapButton()
end

function GRIP:UpdateMinimapButton()
  EnsureMinimapDB()
  if not btn then return end
  if GRIPDB.minimap.hide then
    btn:Hide()
  else
    btn:Show()
    SetButtonPosition()
  end
end

function GRIP:ToggleMinimapButton(force)
  EnsureMinimapDB()
  if force == true then
    GRIPDB.minimap.hide = false
  elseif force == false then
    GRIPDB.minimap.hide = true
  else
    GRIPDB.minimap.hide = not GRIPDB.minimap.hide
  end
  if not btn then
    self:CreateMinimapButton()
  else
    self:UpdateMinimapButton()
  end
  self:Print("Minimap button: " .. (GRIPDB.minimap.hide and "OFF" or "ON"))
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, name)
  if name ~= ADDON_NAME then return end
  EnsureMinimapDB()
  GRIP:CreateMinimapButton()
end)