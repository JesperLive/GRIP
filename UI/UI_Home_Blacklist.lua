-- GRIP: UI Home Page — Blacklist Panel
-- Permanent blacklist display panel with ScrollBox rows.

local ADDON_NAME, GRIP = ...

local type, pairs, pcall = type, pairs, pcall
local tsort = table.sort

local HasDB = function() return GRIP:HomeHasDB() end
local L = LibStub("AceLocale-3.0"):GetLocale("GRIP")

-- Constants
local HEADER_H = 38
local BL_ROW_H = 18

-- ----------------------------
-- ClampFontString (promoted)
-- ----------------------------

function GRIP:ClampFontString(fs, w)
  if not fs then return end
  if fs.SetWidth then fs:SetWidth(w) end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
end

local ClampFontString = function(fs, w) GRIP:ClampFontString(fs, w) end

-- ----------------------------
-- Data helpers
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
  tsort(t, function(a, b) return tostring(a) < tostring(b) end)
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

-- ----------------------------
-- Shell + ScrollBox
-- ----------------------------

function GRIP:EnsureBlacklistShell(home)
  if not home or home._blReady then return end
  home._blReady = true

  local bl = CreateFrame("Frame", nil, home, "BackdropTemplate")
  bl:Hide()
  bl:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  bl:SetBackdropColor(1, 1, 1, 0.02)
  bl:SetBackdropBorderColor(1, 1, 1, 0.08)
  home.blFrame = bl

  local header = CreateFrame("Frame", nil, bl)
  header:SetHeight(HEADER_H)
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

  -- Title row (top half)
  header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header.title:SetPoint("TOPLEFT", header, "TOPLEFT", 6, -4)
  header.title:SetJustifyH("LEFT")
  header.title:SetText(L["Blacklist"])

  -- Export button (right side of title row)
  local btnExport = CreateFrame("Button", nil, header, "BackdropTemplate")
  btnExport:SetSize(45, 16)
  btnExport:SetPoint("TOPRIGHT", header, "TOPRIGHT", -4, -2)
  btnExport:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  btnExport:SetBackdropColor(1, 1, 1, 0.06)
  btnExport:SetBackdropBorderColor(1, 1, 1, 0.15)
  btnExport.label = btnExport:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  btnExport.label:SetPoint("CENTER")
  btnExport.label:SetText(L["Export"])
  btnExport:SetScript("OnClick", function()
    if not GRIP.ExportBlacklist then
      GRIP:Print(L["Export module not loaded."])
      return
    end
    local str = GRIP:ExportBlacklist()
    if not str then
      GRIP:Print(L["Export failed (empty blacklist or codec error)."])
      return
    end
    if StaticPopupDialogs and not StaticPopupDialogs["GRIP_EXPORT"] then
      -- Popup registered by Slash.lua; trigger it via slash as fallback
      GRIP:HandleSlash("export bl")
      return
    end
    if StaticPopup_Show then
      StaticPopup_Show("GRIP_EXPORT", nil, nil, str)
    end
    local count = GRIP.Count and GRIP:Count(GRIPDB.blacklistPerm) or 0
    GRIP:Print((L["Exported %d blacklist entries."]):format(count))
  end)
  btnExport:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Export permanent blacklist"])
    GameTooltip:AddLine(L["Copies a shareable string to a popup for Ctrl+C."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  btnExport:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Import button (left of export)
  local btnImport = CreateFrame("Button", nil, header, "BackdropTemplate")
  btnImport:SetSize(45, 16)
  btnImport:SetPoint("RIGHT", btnExport, "LEFT", -4, 0)
  btnImport:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  btnImport:SetBackdropColor(1, 1, 1, 0.06)
  btnImport:SetBackdropBorderColor(1, 1, 1, 0.15)
  btnImport.label = btnImport:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  btnImport.label:SetPoint("CENTER")
  btnImport.label:SetText(L["Import"])
  btnImport:SetScript("OnClick", function()
    if StaticPopupDialogs and not StaticPopupDialogs["GRIP_IMPORT"] then
      GRIP:HandleSlash("import")
      return
    end
    if StaticPopup_Show then
      StaticPopup_Show("GRIP_IMPORT")
    end
  end)
  btnImport:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Import blacklist or templates"])
    GameTooltip:AddLine(L["Paste a GRIP export string to import data."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  btnImport:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Mid separator between title and column labels
  header.midLine = header:CreateTexture(nil, "BORDER")
  header.midLine:SetPoint("LEFT", header, "LEFT", 4, 0)
  header.midLine:SetPoint("RIGHT", header, "RIGHT", -4, 0)
  header.midLine:SetPoint("TOP", header, "TOP", 0, -18)
  header.midLine:SetHeight(1)
  header.midLine:SetColorTexture(1, 1, 1, 0.06)

  -- Divider between header and scroll body
  header.divider = bl:CreateTexture(nil, "ARTWORK")
  header.divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  header.divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  header.divider:SetHeight(1)
  header.divider:SetColorTexture(1, 1, 1, 0.08)

  -- Column labels (bottom half)
  local function H(text)
    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
  end
  bl.hName = H(L["Name"])
  bl.hReason = H(L["Reason"])

  -- Body background (subtle)
  bl.bg = bl:CreateTexture(nil, "BACKGROUND")
  bl.bg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  bl.bg:SetPoint("BOTTOMRIGHT", bl, "BOTTOMRIGHT", 0, 0)
  bl.bg:SetColorTexture(1, 1, 1, 0.02)

  -- ScrollBox
  local scrollBox = CreateFrame("Frame", nil, bl, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", bl, "BOTTOMRIGHT", -16, 0)
  bl.scrollBox = scrollBox

  -- ScrollBar
  local scrollBar = CreateFrame("EventFrame", nil, bl, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
  scrollBar:SetHideIfUnscrollable(true)

  -- View
  local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 0)
  view:SetElementExtent(BL_ROW_H)

  -- Element initializer
  view:SetElementInitializer("Button", function(row, elementData)
    if not row._initialized then
      row._initialized = true
      row:SetHeight(BL_ROW_H)

      row.stripe = row:CreateTexture(nil, "BACKGROUND")
      row.stripe:SetAllPoints(row)
      row.stripe:SetColorTexture(1, 1, 1, 0.07)
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
        GRIP:ConfirmUnblacklist(n)
      end)

      row:SetScript("OnEnter", function(self)
        local n = self._nameKey
        if not n or not _G.GRIPDB or not GRIPDB.blacklistPerm then return end
        local e = GRIPDB.blacklistPerm[n]
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(n, 1, 1, 1)
        if type(e) == "table" then
          if e.reason and e.reason ~= "" then
            GameTooltip:AddLine(L["Reason: "] .. e.reason, 0.8, 0.8, 0.6, true)
          end
          if e.at and type(e.at) == "number" and e.at > 0 then
            GameTooltip:AddLine(L["Added: "] .. date("%Y-%m-%d", e.at), 0.6, 0.6, 0.6)
          end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to remove from blacklist"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
      end)
    end

    -- Populate (runs every display pass)
    local cw = bl._blColWidths
    local pad = cw and cw.pad or 6
    local wName = cw and cw.name or 110
    local wReason = cw and cw.reason or 60

    row._nameKey = elementData.key

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", pad, 0)
    ClampFontString(row.name, wName)
    row.name:SetText(elementData.key)

    row.reason:ClearAllPoints()
    row.reason:SetPoint("LEFT", row, "LEFT", pad + wName + pad, 0)
    ClampFontString(row.reason, wReason)

    local reason = GetBlacklistReason(elementData.entry)
    if reason == "" then
      row.reason:SetText(L["Click to remove"])
    else
      row.reason:SetText(reason)
    end

    if elementData.index % 2 == 0 then
      row.stripe:Show()
    else
      row.stripe:Hide()
    end
  end)

  -- Wire ScrollBox + ScrollBar + View
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  -- Empty state
  bl.empty = bl:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  bl.empty:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 6, -10)
  bl.empty:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -6, -10)
  bl.empty:SetJustifyH("LEFT")
  bl.empty:SetJustifyV("TOP")
  bl.empty:SetText(L["Permanent blacklist is empty.\nTip: right-click a Potential entry to add it."])
  bl.empty:Hide()
end

-- ----------------------------
-- Layout
-- ----------------------------

function GRIP:LayoutBlacklistPanel(home)
  if not home or not home.blFrame or not home.blFrame.scrollBox then return end
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
  bl.hName:SetPoint("LEFT", bl.header, "LEFT", x, -9)
  ClampFontString(bl.hName, wName)
  x = x + wName + pad

  bl.hReason:ClearAllPoints()
  bl.hReason:SetPoint("LEFT", bl.header, "LEFT", x, -9)
  ClampFontString(bl.hReason, wReason)

  bl._blColWidths = { name = wName, reason = wReason, pad = pad }
end

-- ----------------------------
-- Update rows
-- ----------------------------

function GRIP:UpdateBlacklistRows(home)
  if not home or not home.blFrame or not home.blFrame.scrollBox then return end
  if not HasDB() then return end

  local bl = home.blFrame
  local names = BuildBlacklistNameList()
  bl._names = names

  local total = #names

  local tempCount = (GRIP and GRIP.Count and GRIP:Count(GRIPDB.blacklist)) or 0
  if total == 0 then
    if bl.empty then
      if tempCount > 0 then
        bl.empty:SetText((L["No permanent blacklist entries.\nTemp blacklist active: %d.\nTip: right-click a Potential entry to add a permanent entry."]):format(tempCount))
      else
        bl.empty:SetText(L["Permanent blacklist is empty.\nTip: right-click a Potential entry to add it."])
      end
      bl.empty:Show()
    end
  else
    if bl.empty then bl.empty:Hide() end
  end

  local data = {}
  for i, name in ipairs(names) do
    local e = GRIPDB.blacklistPerm[name]
    data[i] = { key = name, entry = e, index = i }
  end
  local provider = CreateDataProvider()
  provider:InsertTable(data)
  bl.scrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
end
