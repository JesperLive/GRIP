-- GRIP: UI Widgets
-- Reusable constructors: checkboxes, multiline edits, checklists, scroll pages.

local ADDON_NAME, GRIP = ...
local L = LibStub("AceLocale-3.0"):GetLocale("GRIP")

-- Lua
local type, tostring = type, tostring
local ipairs = ipairs
local floor = math.floor

GRIP.UIW = GRIP.UIW or {}
local W = GRIP.UIW

-- Shared UI color palette (use unpack() when passing to SetTextColor etc.)
GRIP.COLORS = {
  -- Backgrounds
  bgDeep        = { 0.051, 0.051, 0.102, 1 },    -- #0d0d1a  (deepest bg)
  bgMain        = { 0.102, 0.102, 0.180, 1 },    -- #1a1a2e  (main panels)
  bgPanel       = { 0.086, 0.129, 0.243, 1 },    -- #16213e  (raised panels)
  bgInput       = { 0.059, 0.090, 0.161, 1 },    -- #0f1729  (edit boxes)
  bgRowHover    = { 0.059, 0.204, 0.376, 1 },    -- #0f3460  (list hover)
  bgRowSelected = { 0.325, 0.204, 0.514, 1 },    -- #533483  (list selected)
  bgButton      = { 0.118, 0.176, 0.290, 1 },    -- #1e2d4a  (button face)
  bgButtonHover = { 0.059, 0.204, 0.376, 1 },    -- #0f3460  (button hover)
  -- Accent & branding
  accent        = { 0.914, 0.271, 0.376, 1 },    -- #e94560  (GRIP red)
  gripGreen     = { 0.000, 0.800, 0.400, 1 },    -- #00cc66
  gripGold      = { 1.000, 0.820, 0.000, 1 },    -- #ffd100  (GRIP gold)
  -- Text
  textPrimary   = { 0.933, 0.933, 1.000, 1 },    -- #eeeeff
  textSecondary = { 0.533, 0.533, 0.667, 1 },    -- #8888aa
  textMuted     = { 0.333, 0.333, 0.467, 1 },    -- #555577
  textWarning   = { 1.000, 0.800, 0.000, 1 },    -- #ffcc00
  textError     = { 1.000, 0.267, 0.267, 1 },    -- #ff4444
  textSuccess   = { 0.000, 0.800, 0.400, 1 },    -- #00cc66
  -- Borders
  border        = { 0.200, 0.200, 0.333, 1 },    -- #333355
  borderFocus   = { 0.333, 0.333, 0.667, 1 },    -- #5555aa
  -- Legacy aliases (keep backward compat for any existing references)
  GOLD       = { 1, 0.82, 0, 1 },
  LIGHT_GREY = { 0.8, 0.8, 0.8, 1 },
  DANGER_RED = { 1, 0.6, 0.6, 1 },
  GREEN      = { 0.4, 1, 0.4, 1 },
  LIGHT_BLUE = { 0.6, 0.8, 1, 1 },
}

GRIP.BACKDROPS = {
  panel = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  },
  panelNoBorder = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
  },
}

-- UIPanelScrollFrameTemplate’s scrollbar is anchored to the RIGHT of the scrollframe (outside it).
-- This inset ensures the scrollbar stays visually inside the window border.
local PAGE_SCROLL_RIGHT_INSET = 32

-- ---------------------------
-- CheckBox label compatibility
-- ---------------------------
function W.EnsureCheckLabel(cb, fontObject)
  if not cb then return nil end

  local label = cb.Text or cb.text or cb.Label or cb.label
  if not label then
    label = cb:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  else
    if fontObject and label.SetFontObject then
      label:SetFontObject(fontObject)
    end
  end

  cb._gripLabel = label
  return label
end

function W.SetCheckLabelText(cb, text)
  local label = cb and (cb._gripLabel or cb.Text or cb.text)
  if not (label and label.SetText) then
    label = W.EnsureCheckLabel(cb, "GameFontHighlightSmall")
  end
  if label then
    label:SetText(tostring(text or ""))
  end
  return label
end

-- ---------------------------------------------
-- Dirty-aware set text helper (prevents stomping)
-- ---------------------------------------------
function W.SetTextIfUnfocused(editBox, text)
  if not editBox or not editBox.SetText then return end
  if editBox._gripDirty then return end
  if editBox.HasFocus and editBox:HasFocus() then return end

  text = tostring(text or "")
  if editBox.GetText and editBox:GetText() == text then return end

  editBox._gripProgrammatic = true
  editBox:SetText(text)
  editBox._gripProgrammatic = false
end

-- ---------------------------
-- Basic widgets
-- ---------------------------
function W.CreateUIButton(parent, label, w, h, onClick)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(w, h)
  btn:SetBackdrop(GRIP.BACKDROPS.panel)
  btn:SetBackdropColor(unpack(GRIP.COLORS.bgButton))
  btn:SetBackdropBorderColor(unpack(GRIP.COLORS.border))
  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER")
  fs:SetTextColor(unpack(GRIP.COLORS.textPrimary))
  btn:SetFontString(fs)
  btn:SetText(label or "")
  btn:SetScript("OnEnter", function(self)
    if not self:IsEnabled() then return end
    self:SetBackdropColor(unpack(GRIP.COLORS.bgButtonHover))
    self:SetBackdropBorderColor(unpack(GRIP.COLORS.borderFocus))
  end)
  btn:SetScript("OnLeave", function(self)
    if not self:IsEnabled() then return end
    self:SetBackdropColor(unpack(GRIP.COLORS.bgButton))
    self:SetBackdropBorderColor(unpack(GRIP.COLORS.border))
  end)
  btn:SetScript("OnMouseDown", function(self)
    if not self:IsEnabled() then return end
    self:SetBackdropColor(unpack(GRIP.COLORS.accent))
  end)
  btn:SetScript("OnMouseUp", function(self)
    if not self:IsEnabled() then return end
    self:SetBackdropColor(unpack(GRIP.COLORS.bgButtonHover))
  end)
  if onClick then
    btn:SetScript("OnClick", onClick)
  end
  return btn
end

function W.CreateCheckbox(parent, label, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  W.EnsureCheckLabel(cb, "GameFontHighlightSmall")
  W.SetCheckLabelText(cb, label)
  cb:SetScript("OnClick", onClick)
  return cb
end

local function HookDirtyTracking(editBox)
  if not editBox or not editBox.HookScript then return end
  editBox._gripDirty = false
  editBox._gripProgrammatic = false

  editBox:HookScript("OnTextChanged", function(self, userInput)
    if self._gripProgrammatic then return end
    if userInput then
      self._gripDirty = true
    end
  end)

  -- Helpful defaults for single-line edits
  if editBox.SetScript then
    editBox:HookScript("OnEscapePressed", editBox.ClearFocus)
    editBox:HookScript("OnEnterPressed", editBox.ClearFocus)
  end
end

function W.CreateLabeledEdit(parent, label, width)
  local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  t:SetText(label)

  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width or 120, 20)
  e:SetAutoFocus(false)

  HookDirtyTracking(e)
  return t, e
end

-- ---------------------------
-- Multiline edit (resize-aware)
-- ---------------------------
local function AttachResizeAwareMultiline(sf, eb, child)
  if not (sf and eb) then return end

  local function Recalc()
    local w = (sf.GetWidth and sf:GetWidth()) or 0
    local h = (sf.GetHeight and sf:GetHeight()) or 0

    -- InputScrollFrameTemplate uses a scrollbar; 28 is the safe padding used previously.
    local cw = w - 28
    if cw < 1 then cw = 1 end

    if eb.SetWidth then eb:SetWidth(cw) end
    if child and child.SetWidth then child:SetWidth(cw) end

    -- For fallback frames, keeping the EditBox height aligned with the visible area helps scrolling feel right.
    if eb.SetHeight and h and h > 0 then
      eb:SetHeight(h)
    end
  end

  if sf.HookScript then
    sf:HookScript("OnSizeChanged", function() Recalc() end)
  else
    sf:SetScript("OnSizeChanged", function() Recalc() end)
  end

  -- Initial pass
  Recalc()
end

function W.CreateMultilineEdit(parent, w, h)
  local sf = CreateFrame("ScrollFrame", nil, parent, "InputScrollFrameTemplate")
  if w and h then
    sf:SetSize(w, h)
  end

  local eb = sf.EditBox
  local child

  if not eb then
    -- fallback
    sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    if w and h then
      sf:SetSize(w, h)
    end

    child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)

    eb = CreateFrame("EditBox", nil, child)
    eb:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    eb:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", 0, 0)
  end

  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject("ChatFontNormal")
  eb:SetTextInsets(6, 6, 6, 6)

  eb:SetScript("OnEscapePressed", eb.ClearFocus)

  -- Do NOT clear focus on Enter (ticker + focus changes caused "revert").
  -- Insert newline.
  eb:SetScript("OnEnterPressed", function(self)
    if self.Insert then
      self:Insert("\n")
    end
  end)

  eb:EnableMouse(true)
  if eb.HookScript then
    eb:HookScript("OnMouseDown", function(self) self:SetFocus() end)
  else
    eb:SetScript("OnMouseDown", function(self) self:SetFocus() end)
  end

  HookDirtyTracking(eb)

  -- Resize-aware width/height adjustments (critical for the new resizable main frame).
  AttachResizeAwareMultiline(sf, eb, child)

  return sf, eb
end

-- ---------------------------
-- Scroll page container (for Settings/Ads)
-- ---------------------------
function W.CreateScrollPage(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

  -- IMPORTANT:
  -- UIPanelScrollFrameTemplate’s scrollbar is OUTSIDE the scrollframe.
  -- Inset enough so the scrollbar never hangs off the right edge of the main window.
  sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PAGE_SCROLL_RIGHT_INSET, 0)

  local content = CreateFrame("Frame", nil, sf)
  content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
  content:SetHeight(1)
  sf:SetScrollChild(content)

  local function ApplyWidth(w)
    -- Content width should track the visible scroll area.
    -- Keep a small safety margin so widgets don’t touch the edge.
    local cw = (w or 0) - 4
    if cw < 1 then cw = 1 end
    content:SetWidth(cw)
  end

  sf:SetScript("OnSizeChanged", function(self, w, h)
    ApplyWidth(w)
  end)

  -- Initial width pass (helps first render before the next resize tick).
  ApplyWidth((sf.GetWidth and sf:GetWidth()) or 0)

  sf.content = content
  return sf, content
end

-- ---------------------------
-- Checklist widget (resize-aware)
-- ---------------------------
local function CreateChecklistFrame(parent, titleText, w, h)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(w, h)
  box:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = false, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  box:SetBackdropColor(0, 0, 0, 0.25)

  local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
  title:SetText(titleText)

  local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -22)
  sf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6)

  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(1, 1)
  sf:SetScrollChild(child)

  box._sf = sf
  box._child = child
  box._title = title
  box._checks = {}

  local function ComputeLabelWidth()
    local sw = (sf.GetWidth and sf:GetWidth()) or 0
    local labelW = sw - 36 -- checkbox + padding
    if labelW < 60 then labelW = 60 end
    return labelW
  end

  local function RecalcChildWidthAndLabels()
    local sw = (sf.GetWidth and sf:GetWidth()) or 0
    local cw = sw
    if cw < 1 then cw = 1 end
    child:SetWidth(cw)

    local labelW = ComputeLabelWidth()
    for _, cb in ipairs(box._checks) do
      if cb and cb.IsShown and cb:IsShown() then
        local lbl = cb._gripLabel or cb.Text or cb.text
        if lbl and lbl.SetWidth then
          lbl:SetWidth(labelW)
        end
      end
    end
  end

  if sf.HookScript then
    sf:HookScript("OnSizeChanged", function() RecalcChildWidthAndLabels() end)
  else
    sf:SetScript("OnSizeChanged", function() RecalcChildWidthAndLabels() end)
  end
  RecalcChildWidthAndLabels()

  box._gripComputeLabelWidth = ComputeLabelWidth
  box._gripRecalc = RecalcChildWidthAndLabels

  return box
end

function W.CreateChecklist(parent, titleText, w, h)
  local box = CreateChecklistFrame(parent, titleText, w, h)

  function box:Render(items, selectedTbl, onToggle)
    items = items or {}
    selectedTbl = selectedTbl or {}

    for _, cb in ipairs(self._checks) do
      cb:Hide()
    end

    local labelW = (self._gripComputeLabelWidth and self._gripComputeLabelWidth()) or 120

    local y = -2
    local idx = 0
    for _, name in ipairs(items) do
      local key = name -- avoid closure capture bug
      idx = idx + 1

      local cb = self._checks[idx]
      if not cb then
        cb = CreateFrame("CheckButton", nil, self._child, "UICheckButtonTemplate")
        local lbl = W.EnsureCheckLabel(cb, "GameFontHighlightSmall")
        if lbl then
          lbl:SetJustifyH("LEFT")
        end
        self._checks[idx] = cb
      end

      cb:ClearAllPoints()
      cb:SetPoint("TOPLEFT", self._child, "TOPLEFT", 0, y)

      local lbl = W.SetCheckLabelText(cb, key)
      if lbl and lbl.SetWidth then
        lbl:SetWidth(labelW)
      end

      cb:SetChecked(selectedTbl[key] == true)
      cb:Show()

      cb:SetScript("OnClick", function(btn)
        local checked = btn:GetChecked()
        if checked then
          selectedTbl[key] = true
        else
          selectedTbl[key] = nil
        end
        if onToggle then onToggle(key, checked) end
        GRIP:UpdateUI()
      end)

      y = y - 20
    end

    self._child:SetHeight(math.max(1, idx * 20 + 8))

    -- One more sizing pass after render (covers first render before layout settles).
    if self._gripRecalc then
      self._gripRecalc()
    end
  end

  return box
end

-- ---------------------------
-- Grouped checklist widget (expansion-grouped zones)
-- ---------------------------

function W.CreateGroupedChecklist(parent, titleText, w, h)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(w, h)
  box:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = false, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  box:SetBackdropColor(0, 0, 0, 0.25)

  local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
  title:SetText(titleText)

  local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -22)
  sf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6)

  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(1, 1)
  sf:SetScrollChild(child)

  box._sf = sf
  box._child = child
  box._title = title
  box._checks = {}
  box._headers = {}
  box._groupBtns = {}

  local INDENT = 12
  local CB_HEIGHT = 20
  local HDR_HEIGHT = 20
  local GROUP_GAP = 6

  local function ComputeLabelWidth()
    local sw = (sf.GetWidth and sf:GetWidth()) or 0
    local labelW = sw - 36 - INDENT
    if labelW < 40 then labelW = 40 end
    return labelW
  end

  local function RecalcWidths()
    local sw = (sf.GetWidth and sf:GetWidth()) or 0
    local cw = sw
    if cw < 1 then cw = 1 end
    child:SetWidth(cw)
    local labelW = ComputeLabelWidth()
    for _, cb in ipairs(box._checks) do
      if cb and cb.IsShown and cb:IsShown() then
        local lbl = cb._gripLabel or cb.Text or cb.text
        if lbl and lbl.SetWidth then
          lbl:SetWidth(labelW)
        end
      end
    end
  end

  if sf.HookScript then
    sf:HookScript("OnSizeChanged", function() RecalcWidths() end)
  else
    sf:SetScript("OnSizeChanged", function() RecalcWidths() end)
  end
  RecalcWidths()
  box._gripRecalc = RecalcWidths

  function box:Render(groups, selectedTbl, onToggle)
    groups = groups or {}
    selectedTbl = selectedTbl or {}

    -- Hide all existing elements
    for _, cb in ipairs(self._checks) do cb:Hide() end
    for _, h in ipairs(self._headers) do h:Hide() end
    for _, btns in ipairs(self._groupBtns) do
      if btns.all then btns.all:Hide() end
      if btns.none then btns.none:Hide() end
    end

    local labelW = ComputeLabelWidth()
    local y = -2
    local cbIdx = 0
    local hdrIdx = 0

    for _, group in ipairs(groups) do
      hdrIdx = hdrIdx + 1

      -- Group header (gold text)
      local hdr = self._headers[hdrIdx]
      if not hdr then
        hdr = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetJustifyH("LEFT")
        self._headers[hdrIdx] = hdr
      end
      hdr:ClearAllPoints()
      hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y)
      hdr:SetText(group.name or "")
      hdr:SetTextColor(unpack(GRIP.COLORS.GOLD))
      hdr:Show()

      -- Per-group All / None buttons (small, inside scrollable area)
      local btns = self._groupBtns[hdrIdx]
      if not btns then
        btns = {}
        btns.all = W.CreateUIButton(child, L["All"], 32, 18)
        btns.none = W.CreateUIButton(child, L["None"], 38, 18)
        self._groupBtns[hdrIdx] = btns
      end

      -- Wire click handlers (fresh closure for this group's zones)
      local groupZones = group.zones
      btns.all:SetScript("OnClick", function()
        for _, z in ipairs(groupZones) do selectedTbl[z] = true end
        if onToggle then onToggle(nil, true) end
        GRIP:UpdateUI()
      end)
      btns.none:SetScript("OnClick", function()
        for _, z in ipairs(groupZones) do selectedTbl[z] = nil end
        if onToggle then onToggle(nil, false) end
        GRIP:UpdateUI()
      end)

      btns.all:ClearAllPoints()
      btns.none:ClearAllPoints()
      btns.all:SetPoint("TOPRIGHT", child, "TOPRIGHT", -40, y - 1)
      btns.none:SetPoint("LEFT", btns.all, "RIGHT", 2, 0)
      btns.all:Show()
      btns.none:Show()

      y = y - HDR_HEIGHT

      -- Zone checkboxes (indented under group header)
      for _, zoneName in ipairs(group.zones) do
        cbIdx = cbIdx + 1
        local key = zoneName
        local cb = self._checks[cbIdx]
        if not cb then
          cb = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
          local lbl = W.EnsureCheckLabel(cb, "GameFontHighlightSmall")
          if lbl then lbl:SetJustifyH("LEFT") end
          self._checks[cbIdx] = cb
        end

        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", child, "TOPLEFT", INDENT, y)

        local lbl = W.SetCheckLabelText(cb, key)
        if lbl and lbl.SetWidth then
          lbl:SetWidth(labelW)
        end

        cb:SetChecked(selectedTbl[key] == true)
        cb:Show()

        cb:SetScript("OnClick", function(btn)
          local checked = btn:GetChecked()
          if checked then
            selectedTbl[key] = true
          else
            selectedTbl[key] = nil
          end
          if onToggle then onToggle(key, checked) end
          GRIP:UpdateUI()
        end)

        y = y - CB_HEIGHT
      end

      y = y - GROUP_GAP
    end

    child:SetHeight(math.max(1, math.abs(y) + 8))
    RecalcWidths()
  end

  return box
end

-- ---------------------------
-- Slider widget
-- ---------------------------
function W.CreateSlider(parent, label, minVal, maxVal, step, default, width, onChanged)
  width = width or 160

  local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  slider:SetSize(width, 17)
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  slider:SetValue(default or minVal)

  -- Hide the built-in Low/High labels — we show our own value label instead.
  if slider.Low  then slider.Low:SetText("")  end
  if slider.High then slider.High:SetText("") end

  -- Label above the slider
  local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lbl:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
  lbl:SetText(label or "")
  slider._gripLabel = lbl

  -- Value readout to the right
  local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  val:SetPoint("LEFT", slider, "RIGHT", 8, 0)
  val:SetText((L["%d min"]):format(floor(default or minVal)))
  slider._gripValue = val

  slider:SetScript("OnValueChanged", function(self, v)
    v = floor(v + 0.5)
    val:SetText((L["%d min"]):format(v))
    if onChanged then onChanged(v) end
  end)

  return slider
end

-- ── Shared UI helpers (centralized from per-file locals) ───────────────

function W.SetEnabledSafe(widget, enabled)
  if not widget then return end
  if enabled then
    if widget.Enable  then widget:Enable()  end
    if widget.SetAlpha then widget:SetAlpha(1.0) end
  else
    if widget.Disable then widget:Disable() end
    if widget.SetAlpha then widget:SetAlpha(0.45) end
  end
end

function W.ClearDirty(...)
  for i = 1, select("#", ...) do
    local eb = select(i, ...)
    if eb then eb._gripDirty = false end
  end
end

function W.ProgrammaticSet(eb, text)
  if not eb then return end
  eb._gripProgrammatic = true
  eb:SetText(text or "")
  eb._gripProgrammatic = false
end

function W.SafeTop(frame)
  if not frame then return 0 end
  return select(5, frame:GetPoint(1)) or 0
end

function W.SafeBottom(frame)
  if not frame then return 0 end
  return (frame:GetBottom() or 0) - (frame:GetParent() and frame:GetParent():GetBottom() or 0)
end

function W.BuildInsertedTextAtCursor(eb, token)
  if not eb then return "" end
  local fullText = eb:GetText() or ""
  local cursorPos = eb:GetCursorPosition() or #fullText

  local bytePos = 0
  local charCount = 0
  while charCount < cursorPos and bytePos < #fullText do
    bytePos = bytePos + 1
    local b = fullText:byte(bytePos)
    if b and b >= 0xC0 then
      if     b >= 0xF0 then bytePos = bytePos + 3
      elseif b >= 0xE0 then bytePos = bytePos + 2
      elseif b >= 0xC0 then bytePos = bytePos + 1
      end
    end
    charCount = charCount + 1
  end

  local before = fullText:sub(1, bytePos)
  local after  = fullText:sub(bytePos + 1)
  local newText = before .. token .. after
  local newCursorByte = bytePos + #token
  return newText, newCursorByte
end

-- ---------------------------
-- Tooltip helper
-- ---------------------------

function GRIP:AttachTooltip(frame, titleOrFunc, bodyOrFunc)
    if not frame then return end
    if not frame.EnableMouse then return end
    if not frame:IsObjectType("Button") then
        frame:EnableMouse(true)
    end
    local function OnEnter(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local t = (type(titleOrFunc) == "function") and titleOrFunc() or titleOrFunc
        if type(t) == "string" and t ~= "" then
            GameTooltip:AddLine(t, 1, 1, 1, true)
        end
        local b = (type(bodyOrFunc) == "function") and bodyOrFunc() or bodyOrFunc
        if type(b) == "string" and b ~= "" then
            for line in b:gmatch("[^\n]+") do
                GameTooltip:AddLine(line, 0.8, 0.8, 0.6, true)
            end
        end
        GameTooltip:Show()
    end
    local function OnLeave(self)
        GameTooltip:Hide()
    end
    if frame:GetScript("OnEnter") then
        frame:HookScript("OnEnter", OnEnter)
        frame:HookScript("OnLeave", OnLeave)
    else
        frame:SetScript("OnEnter", OnEnter)
        frame:SetScript("OnLeave", OnLeave)
    end
end

-- ---------------------------
-- Themed widget factories (dark-theme)
-- ---------------------------

function W.CreateThemedButton(parent, label, w, h, onClick)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(w, h)
  btn:SetBackdrop(GRIP.BACKDROPS.panel)
  btn:SetBackdropColor(unpack(GRIP.COLORS.bgButton))
  btn:SetBackdropBorderColor(unpack(GRIP.COLORS.border))

  local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("CENTER")
  text:SetTextColor(unpack(GRIP.COLORS.textPrimary))
  text:SetText(label or "")
  btn._gripLabel = text

  btn:SetScript("OnEnter", function(self)
    if self._gripTabActive then return end
    self:SetBackdropColor(unpack(GRIP.COLORS.bgButtonHover))
    self:SetBackdropBorderColor(unpack(GRIP.COLORS.borderFocus))
  end)
  btn:SetScript("OnLeave", function(self)
    if self._gripTabActive then return end
    self:SetBackdropColor(unpack(GRIP.COLORS.bgButton))
    self:SetBackdropBorderColor(unpack(GRIP.COLORS.border))
  end)
  btn:SetScript("OnMouseDown", function(self)
    if self._gripTabActive then return end
    self:SetBackdropColor(unpack(GRIP.COLORS.accent))
  end)
  btn:SetScript("OnMouseUp", function(self)
    if self._gripTabActive then return end
    self:SetBackdropColor(unpack(GRIP.COLORS.bgButtonHover))
  end)

  if onClick then
    btn:SetScript("OnClick", onClick)
  end

  return btn
end

function W.CreateThemedPanel(parent, title)
  local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  panel:SetBackdrop(GRIP.BACKDROPS.panel)
  panel:SetBackdropColor(unpack(GRIP.COLORS.bgPanel))
  panel:SetBackdropBorderColor(unpack(GRIP.COLORS.border))

  if title then
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    t:SetTextColor(unpack(GRIP.COLORS.gripGold))
    t:SetText(title)
    panel._gripTitle = t
  end

  return panel
end

function W.CreateSectionHeader(parent, text)
  local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetTextColor(unpack(GRIP.COLORS.gripGold))
  header:SetText(text or "")

  local divider = parent:CreateTexture(nil, "ARTWORK")
  divider:SetHeight(1)
  divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  divider:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
  divider:SetColorTexture(GRIP.COLORS.gripGold[1], GRIP.COLORS.gripGold[2],
    GRIP.COLORS.gripGold[3], 0.3)

  return header, divider
end

function W.CreateThemedCheckbox(parent, label, tooltip, onClick)
  local cb = W.CreateCheckbox(parent, label, onClick)
  if tooltip and GRIP.AttachTooltip then
    GRIP:AttachTooltip(cb, label, tooltip)
  end
  return cb
end

function W.AddButtonAccent(btn, r, g, b)
  if not btn then return end
  local accent = btn:CreateTexture(nil, "ARTWORK")
  accent:SetHeight(2)
  accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, -1)
  accent:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, -1)
  accent:SetColorTexture(r, g, b, 0.6)
  btn._accent = accent
end

-- End shared UI helpers