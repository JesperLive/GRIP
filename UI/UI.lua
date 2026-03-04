-- GRIP: UI Controller
-- Main frame, tabs, page routing, resize handling, UpdateUI coalescing.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring = type, tostring
local pairs, ipairs, pcall = pairs, ipairs, pcall
local tinsert = table.insert
local floor, max = math.floor, math.max

-- WoW API
local GetTime = GetTime
local C_Timer = C_Timer

local state = GRIP.state
local W = GRIP.UIW

local function HasDB()
  return (_G.GRIPDB_CHAR and GRIPDB_CHAR.config and GRIPDB_CHAR.lists and GRIPDB_CHAR.filters) and true or false
end

local function EnsureDBSafe()
  if HasDB() then return true end
  if GRIP and GRIP.EnsureDB then
    pcall(function() GRIP:EnsureDB() end)
  end
  return HasDB()
end

local function TabStyle(btn, active)
  if not btn then return end
  if active then
    if btn.Disable then btn:Disable() end
  else
    if btn.Enable then btn:Enable() end
  end
end

local function SafeCreatePage(methodName, parent)
  if not GRIP or type(GRIP[methodName]) ~= "function" then
    if GRIP and GRIP.Print then
      GRIP:Print(("UI page missing: %s (file not loaded?)"):format(tostring(methodName)))
    end
    local stub = CreateFrame("Frame", nil, parent)
    stub:SetAllPoints(true)
    local t = stub:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t:SetPoint("TOPLEFT", stub, "TOPLEFT", 4, -4)
    t:SetJustifyH("LEFT")
    t:SetText(("Page unavailable (%s)"):format(tostring(methodName)))
    return stub
  end

  local ok, page = pcall(function()
    return GRIP[methodName](GRIP, parent)
  end)

  if ok and page then
    return page
  end

  if GRIP and GRIP.Print then
    GRIP:Print(("Failed to create UI page: %s"):format(tostring(methodName)))
  end

  local stub = CreateFrame("Frame", nil, parent)
  stub:SetAllPoints(true)
  local t = stub:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  t:SetPoint("TOPLEFT", stub, "TOPLEFT", 4, -4)
  t:SetJustifyH("LEFT")
  t:SetText(("Page failed to load (%s)"):format(tostring(methodName)))
  return stub
end

-- ----------------------------
-- Resizing + persisted geometry
-- ----------------------------

local DEFAULT_W, DEFAULT_H = 560, 420
local MIN_W, MIN_H = DEFAULT_W, DEFAULT_H

local SCREEN_MARGIN = 0
local function GetMaxBounds()
  local sw = GetScreenWidth and GetScreenWidth() or 1920
  local sh = GetScreenHeight and GetScreenHeight() or 1080
  return max(MIN_W, sw - SCREEN_MARGIN), max(MIN_H, sh - SCREEN_MARGIN)
end
local function ClampFrameSize(w, h)
  local maxW, maxH = GetMaxBounds()
  if w < MIN_W then w = MIN_W end
  if h < MIN_H then h = MIN_H end
  if w > maxW then w = maxW end
  if h > maxH then h = maxH end
  return w, h
end

local function GetConfig()
  return (_G.GRIPDB_CHAR and GRIPDB_CHAR.config) or nil
end

local function GetUIParentCenter()
  if not UIParent or not UIParent.GetCenter then return 0, 0 end
  local cx, cy = UIParent:GetCenter()
  return cx or 0, cy or 0
end

local function RestoreFrameGeometry(f)
  local cfg = GetConfig()
  if not (f and cfg) then return end

  local w = tonumber(cfg.uiW) or DEFAULT_W
  local h = tonumber(cfg.uiH) or DEFAULT_H
  w, h = ClampFrameSize(w, h)

  f:SetSize(w, h)

  local dx = tonumber(cfg.uiDX) or 0
  local dy = tonumber(cfg.uiDY) or 0

  local sw = GetScreenWidth and GetScreenWidth() or 1920
  local sh = GetScreenHeight and GetScreenHeight() or 1080
  local maxDX = (sw / 2) - 50
  local maxDY = (sh / 2) - 50
  if dx > maxDX then dx = maxDX end
  if dx < -maxDX then dx = -maxDX end
  if dy > maxDY then dy = maxDY end
  if dy < -maxDY then dy = -maxDY end

  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", dx, dy)
end

local function ResetFrameGeometry(f)
  local cfg = GetConfig()
  if cfg then
    cfg.uiW = nil
    cfg.uiH = nil
    cfg.uiDX = nil
    cfg.uiDY = nil
  end
  if f then
    f:SetSize(DEFAULT_W, DEFAULT_H)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function SaveFrameGeometry(f)
  local cfg = GetConfig()
  if not (f and cfg and f.GetSize and f.GetCenter) then return end

  local w, h = f:GetSize()
  w, h = ClampFrameSize(w or DEFAULT_W, h or DEFAULT_H)
  cfg.uiW = math.floor(w + 0.5)
  cfg.uiH = math.floor(h + 0.5)

  local fx, fy = f:GetCenter()
  local px, py = GetUIParentCenter()
  cfg.uiDX = math.floor(((fx or px) - px) + 0.5)
  cfg.uiDY = math.floor(((fy or py) - py) + 0.5)
end

local function ThrottledSaveGeometry(f)
  if not f then return end
  if f._gripGeomSavePending then return end
  f._gripGeomSavePending = true

  if C_Timer and C_Timer.After then
    C_Timer.After(0.25, function()
      if f and f._gripGeomSavePending then
        f._gripGeomSavePending = nil
        SaveFrameGeometry(f)
      end
    end)
  else
    f._gripGeomSavePending = nil
    SaveFrameGeometry(f)
  end
end

local function CallActiveLayoutHook(f)
  if not (GRIP and f) then return end

  local which = f._activePage
  if which == "settings" then
    if GRIP.UI_LayoutSettings then pcall(GRIP.UI_LayoutSettings, GRIP) end
    return
  elseif which == "ads" then
    if GRIP.UI_LayoutAds then pcall(GRIP.UI_LayoutAds, GRIP) end
    return
  elseif which == "home" then
    if GRIP.UI_LayoutHome then pcall(GRIP.UI_LayoutHome, GRIP) end
    return
  end

  -- Fallback if _activePage is missing/invalid.
  if f.home and f.home.IsShown and f.home:IsShown() then
    if GRIP.UI_LayoutHome then pcall(GRIP.UI_LayoutHome, GRIP) end
  elseif f.settings and f.settings.IsShown and f.settings:IsShown() then
    if GRIP.UI_LayoutSettings then pcall(GRIP.UI_LayoutSettings, GRIP) end
  elseif f.ads and f.ads.IsShown and f.ads:IsShown() then
    if GRIP.UI_LayoutAds then pcall(GRIP.UI_LayoutAds, GRIP) end
  end
end

local function ThrottledLayout(f)
  if not f then return end
  if f._gripLayoutPending then return end
  f._gripLayoutPending = true

  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if not f then return end
      f._gripLayoutPending = nil
      if f.IsShown and f:IsShown() then
        CallActiveLayoutHook(f)
      end
    end)
  else
    f._gripLayoutPending = nil
    if f.IsShown and f:IsShown() then
      CallActiveLayoutHook(f)
    end
  end
end

-- ----------------------------
-- UpdateUI coalescing
-- ----------------------------

local function DispatchUpdateUI(self)
  if not state.ui or not state.ui:IsShown() then return end

  if state.ui.home and state.ui.home.IsShown and state.ui.home:IsShown() then
    if self.UI_UpdateHome then pcall(self.UI_UpdateHome, self) end
  elseif state.ui.settings and state.ui.settings.IsShown and state.ui.settings:IsShown() then
    if self.UI_UpdateSettings then pcall(self.UI_UpdateSettings, self) end
  elseif state.ui.ads and state.ui.ads.IsShown and state.ui.ads:IsShown() then
    if self.UI_UpdateAds then pcall(self.UI_UpdateAds, self) end
  end
end

local function RequestUpdateUI(self, forceNow)
  if forceNow then
    if state.ui then state.ui._gripUpdatePending = nil end
    DispatchUpdateUI(self)
    return
  end

  if not state.ui or not state.ui:IsShown() then return end
  if state.ui._gripUpdatePending then return end
  state.ui._gripUpdatePending = true

  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if not state.ui then return end
      state.ui._gripUpdatePending = nil
      DispatchUpdateUI(self)
    end)
  else
    state.ui._gripUpdatePending = nil
    DispatchUpdateUI(self)
  end
end

local DRAG_THRESHOLD = 3
local function AttachResizeGrip(f)
  if not f or f._gripResizeGrip then return end

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
  grip:EnableMouse(true)

  if grip.SetNormalTexture then
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  end

  local startX, startY, startW, startH
  local dragging = false

  local updater = CreateFrame("Frame")
  updater:Hide()
  updater:SetScript("OnUpdate", function()
    if not startX then updater:Hide(); return end
    local cx, cy = GetCursorPosition()
    local scale = f:GetEffectiveScale()
    cx = cx / scale
    cy = cy / scale
    local sx = startX / scale
    local sy = startY / scale
    local dx = cx - sx
    local dy = sy - cy  -- Y inverted: dragging down = smaller Y = increase height
    if not dragging then
      if math.abs(dx) > DRAG_THRESHOLD or math.abs(dy) > DRAG_THRESHOLD then
        dragging = true
      else
        return
      end
    end
    local newW = startW + dx
    local newH = startH + dy
    newW, newH = ClampFrameSize(newW, newH)
    f:SetSize(newW, newH)
  end)

  grip:SetScript("OnMouseDown", function(_, btn)
    if btn ~= "LeftButton" then return end
    -- Refresh max bounds for current screen size
    if f.SetResizeBounds then
      local maxW2, maxH2 = GetMaxBounds()
      f:SetResizeBounds(MIN_W, MIN_H, maxW2, maxH2)
    end
    startX, startY = GetCursorPosition()
    startW, startH = f:GetSize()
    dragging = false
    updater:Show()
  end)

  grip:SetScript("OnMouseUp", function(_, btn)
    if btn ~= "LeftButton" then return end
    updater:Hide()
    if dragging then
      local w, h = f:GetSize()
      w, h = ClampFrameSize(w, h)
      f:SetSize(w, h)
      ThrottledLayout(f)
      ThrottledSaveGeometry(f)
    end
    startX, startY, startW, startH = nil, nil, nil, nil
    dragging = false
  end)

  f._gripResizeGrip = grip
end

-- ----------------------------
-- Modal keyboard + ESC handling (no Game Menu)
-- ----------------------------

local function ConsumeEscAndHide()
  if state.ui and state.ui.IsShown and state.ui:IsShown() then
    state.ui:Hide()
  end
end

local function HookAllEditBoxesForEsc(root)
  if not root then return end

  local function HookOne(eb)
    if not eb or eb._gripEscHooked then return end
    eb._gripEscHooked = true

    if eb.HookScript then
      eb:HookScript("OnEscapePressed", function(self)
        if self.ClearFocus then pcall(self.ClearFocus, self) end
        ConsumeEscAndHide()
      end)
    else
      eb:SetScript("OnEscapePressed", function(self)
        if self.ClearFocus then pcall(self.ClearFocus, self) end
        ConsumeEscAndHide()
      end)
    end
  end

  local function Walk(frame)
    if not frame or not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
      local ot = child.GetObjectType and child:GetObjectType()
      if ot == "EditBox" then
        HookOne(child)
      end
      Walk(child)
    end
  end

  Walk(root)
end

local function MakeFrameTopmost(f)
  if not f then return end

  if f.SetFrameStrata then
    f:SetFrameStrata("DIALOG")
  end
  if f.SetToplevel then
    f:SetToplevel(true)
  end

  -- Keep standard Blizzard escape-to-close behavior as a backstop.
  if f.GetName then
    local name = f:GetName()
    if name and _G.UISpecialFrames then
      local dominated = false
      for _, v in ipairs(_G.UISpecialFrames) do
        if v == name then dominated = true; break end
      end
      if not dominated then
        tinsert(_G.UISpecialFrames, name)
      end
    end
  end
end

function GRIP:CreateUI()
  if state.ui then return end

  local f = CreateFrame("Frame", "GRIPFrame", UIParent, "BasicFrameTemplateWithInset")

  EnsureDBSafe()

  f:SetSize(DEFAULT_W, DEFAULT_H)
  f:SetPoint("CENTER")

  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function()
    if f.StopMovingOrSizing then f:StopMovingOrSizing() end
    ThrottledSaveGeometry(f)
  end)

  f:SetResizable(true)
  local maxW, maxH = GetMaxBounds()
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, maxW, maxH)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, MIN_H)
    if f.SetMaxResize then f:SetMaxResize(maxW, maxH) end
  end

  f:SetClampedToScreen(true)
  f:Hide()

  MakeFrameTopmost(f)

  RestoreFrameGeometry(f)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 8, 0)
  f.title:SetText("GRIP")

  f.btnHome = W.CreateUIButton(f, "Home", 70, 20, function() GRIP:ShowPage("home") end)
  f.btnHome:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)

  f.btnSettings = W.CreateUIButton(f, "Settings", 80, 20, function() GRIP:ShowPage("settings") end)
  f.btnSettings:SetPoint("LEFT", f.btnHome, "RIGHT", 6, 0)

  f.btnAds = W.CreateUIButton(f, "Ads", 70, 20, function() GRIP:ShowPage("ads") end)
  f.btnAds:SetPoint("LEFT", f.btnSettings, "RIGHT", 6, 0)

  -- Active tab underline (gold accent)
  f.tabUnderline = f:CreateTexture(nil, "ARTWORK")
  f.tabUnderline:SetHeight(2)
  f.tabUnderline:SetColorTexture(1, 0.82, 0, 0.9)

  f.page = CreateFrame("Frame", nil, f)
  f.page:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -56)
  f.page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)

  -- Content accent line (subtle gold divider below tabs)
  f.contentAccent = f:CreateTexture(nil, "ARTWORK")
  f.contentAccent:SetHeight(1)
  f.contentAccent:SetPoint("TOPLEFT", f.page, "TOPLEFT", 0, 1)
  f.contentAccent:SetPoint("TOPRIGHT", f.page, "TOPRIGHT", 0, 1)
  f.contentAccent:SetColorTexture(1, 0.82, 0, 0.15)

  f.home = SafeCreatePage("UI_CreateHome", f.page)
  f.settings = SafeCreatePage("UI_CreateSettings", f.page)
  f.ads = SafeCreatePage("UI_CreateAds", f.page)

  f._activePage = "home"
  f._scanCooldownUntil = 0
  f._actionCooldownUntil = 0
  f._postCooldownUntil = 0

  AttachResizeGrip(f)

  -- Hook ESC (and swallow keys) in editboxes too.
  HookAllEditBoxesForEsc(f)

  f:SetScript("OnSizeChanged", function()
    ThrottledLayout(f)
    ThrottledSaveGeometry(f)
  end)

  f:SetScript("OnShow", function()
    EnsureDBSafe()
    RestoreFrameGeometry(f)

    -- Re-scan for editboxes on show (safe + catches late-created widgets)
    HookAllEditBoxesForEsc(f)

    if not f._ticker and C_Timer and C_Timer.NewTicker then
      f._ticker = C_Timer.NewTicker(0.5, function()
        if f:IsShown() then GRIP:UpdateUI() end
      end)
    end

    ThrottledLayout(f)
    GRIP:UpdateUI(true) -- force immediate on open
  end)

  f:SetScript("OnHide", function()
    if f._ticker then
      f._ticker:Cancel()
      f._ticker = nil
    end

    SaveFrameGeometry(f)

    -- B1: Clear dirty flags on all edit boxes when UI closes
    local function ClearAllEditBoxDirty(frame)
      if not frame or not frame.GetChildren then return end
      for _, child in ipairs({ frame:GetChildren() }) do
        local ot = child.GetObjectType and child:GetObjectType()
        if ot == "EditBox" then
          W.ClearDirty(child)
        end
        ClearAllEditBoxDirty(child)
      end
    end
    ClearAllEditBoxDirty(f)
  end)

  state.ui = f
  self:ShowPage("home")
end

function GRIP:ShowPage(which)
  self:CreateUI()
  local f = state.ui
  if not f then return end

  which = which or "home"
  f._activePage = which

  if f.home and f.home.Hide then f.home:Hide() end
  if f.settings and f.settings.Hide then f.settings:Hide() end
  if f.ads and f.ads.Hide then f.ads:Hide() end

  if which == "settings" then
    if f.settings and f.settings.Show then f.settings:Show() end
  elseif which == "ads" then
    if f.ads and f.ads.Show then f.ads:Show() end
  else
    if f.home and f.home.Show then f.home:Show() end
    which = "home"
    f._activePage = which
  end

  TabStyle(f.btnHome, which == "home")
  TabStyle(f.btnSettings, which == "settings")
  TabStyle(f.btnAds, which == "ads")

  -- Position tab underline under the active tab
  if f.tabUnderline then
    local activeBtn = (which == "settings") and f.btnSettings or (which == "ads") and f.btnAds or f.btnHome
    f.tabUnderline:ClearAllPoints()
    f.tabUnderline:SetPoint("BOTTOMLEFT", activeBtn, "BOTTOMLEFT", 0, -1)
    f.tabUnderline:SetPoint("BOTTOMRIGHT", activeBtn, "BOTTOMRIGHT", 0, -1)
  end

  -- Cheap + safe: re-scan for editboxes on tab switch
  HookAllEditBoxesForEsc(f)

  ThrottledLayout(f)
  self:UpdateUI(true) -- force immediate after switching pages
end

function GRIP:ToggleUI()
  self:CreateUI()
  if not state.ui then return end

  if state.ui:IsShown() then
    state.ui:Hide()
  else
    EnsureDBSafe()
    state.ui:Show()
  end
end

function GRIP:ResetUI()
  self:CreateUI()
  local f = state.ui
  ResetFrameGeometry(f)
  if f and f:IsShown() then
    ThrottledLayout(f)
    self:UpdateUI(true)
  end
  self:Print("UI position and size reset to defaults.")
end

-- Coalesced UpdateUI:
-- - default: request a same-tick update (collapses bursts)
-- - forceNow=true: run immediately
function GRIP:UpdateUI(forceNow)
  RequestUpdateUI(self, forceNow and true or false)
end