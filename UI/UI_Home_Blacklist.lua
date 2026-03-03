-- GRIP: UI Home Page — Blacklist Panel
-- Permanent blacklist display panel with FauxScrollFrame rows.

local ADDON_NAME, GRIP = ...

local type, pairs, pcall = type, pairs, pcall
local tsort = table.sort

local HasDB = function() return GRIP:HomeHasDB() end

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
-- Shell + row pool
-- ----------------------------

function GRIP:EnsureBlacklistShell(home)
  if not home or home._blReady then return end
  home._blReady = true

  local bl = CreateFrame("Frame", nil, home)
  bl:Hide()
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
  header.title:SetText("Blacklist")

  -- Mid separator between title and column labels
  header.midLine = header:CreateTexture(nil, "BORDER")
  header.midLine:SetPoint("LEFT", header, "LEFT", 4, 0)
  header.midLine:SetPoint("RIGHT", header, "RIGHT", -4, 0)
  header.midLine:SetPoint("TOP", header, "TOP", 0, -18)
  header.midLine:SetHeight(1)
  header.midLine:SetColorTexture(1, 1, 1, 0.06)

  -- Column labels (bottom half)
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

  -- Row pool (dynamic row count based on visible height)
  local function initBlRow(frame)
    frame:SetHeight(BL_ROW_H)
    frame:Hide()

    frame.stripe = frame:CreateTexture(nil, "BACKGROUND")
    frame.stripe:SetAllPoints(frame)
    frame.stripe:SetColorTexture(1, 1, 1, 0.07)
    frame.stripe:Hide()

    frame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    frame:RegisterForClicks("LeftButtonUp")

    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.name:SetJustifyH("LEFT")
    if frame.name.SetWordWrap then frame.name:SetWordWrap(false) end

    frame.reason = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.reason:SetJustifyH("LEFT")
    if frame.reason.SetWordWrap then frame.reason:SetWordWrap(false) end

    frame._nameKey = nil

    frame:SetScript("OnClick", function(self)
      if not HasDB() then return end
      local n = self._nameKey
      if type(n) ~= "string" or n == "" then return end
      GRIP:ConfirmUnblacklist(n)
    end)

    frame:SetScript("OnEnter", function(self)
      local n = self._nameKey
      if not n or not _G.GRIPDB or not GRIPDB.blacklistPerm then return end
      local e = GRIPDB.blacklistPerm[n]
      if not e then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(n, 1, 1, 1)
      if type(e) == "table" then
        if e.reason and e.reason ~= "" then
          GameTooltip:AddLine("Reason: " .. e.reason, 0.8, 0.8, 0.6, true)
        end
        if e.at and type(e.at) == "number" and e.at > 0 then
          GameTooltip:AddLine("Added: " .. date("%Y-%m-%d", e.at), 0.6, 0.6, 0.6)
        end
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Click to remove from blacklist", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
  end

  local function resetBlRow(pool, frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame._nameKey = nil
    if frame.stripe then frame.stripe:Hide() end
  end

  bl._rowPool = CreateFramePool("Button", bl, nil, resetBlRow, false, initBlRow)
  bl.rows = {}

  local function OnScroll()
    GRIP:UI_UpdateHome()
  end
  sf:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, BL_ROW_H, OnScroll)
  end)
end

-- ----------------------------
-- Row resize
-- ----------------------------

local function ResizeBlacklistRows(home)
  if not home or not home.blFrame or not home.blFrame.scroll or not home.blFrame._rowPool then return end
  local bl = home.blFrame
  local sf = bl.scroll
  local h = tonumber(sf:GetHeight()) or 0
  if h <= 0 then return end
  local needed = math.floor(h / BL_ROW_H) + 1
  if needed < 4 then needed = 4 end
  local current = #bl.rows
  if needed == current then return end
  if needed > current then
    for i = current + 1, needed do
      local row = bl._rowPool:Acquire()
      bl.rows[i] = row
    end
  else
    for i = needed + 1, current do
      bl._rowPool:Release(bl.rows[i])
      bl.rows[i] = nil
    end
  end
end

-- ----------------------------
-- Layout
-- ----------------------------

function GRIP:LayoutBlacklistPanel(home)
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
  bl.hName:SetPoint("LEFT", bl.header, "LEFT", x, -9)
  ClampFontString(bl.hName, wName)
  x = x + wName + pad

  bl.hReason:ClearAllPoints()
  bl.hReason:SetPoint("LEFT", bl.header, "LEFT", x, -9)
  ClampFontString(bl.hReason, wReason)

  ResizeBlacklistRows(home)

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

-- ----------------------------
-- Update rows
-- ----------------------------

function GRIP:UpdateBlacklistRows(home)
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
