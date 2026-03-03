-- GRIP: UI Home Page
-- Potential candidate list, buttons, Ghost strip, layout orchestration.
-- Popup dialogs → UI_Home_Popups.lua | Blacklist panel → UI_Home_Blacklist.lua | Context menu → UI_Home_Menu.lua

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, ipairs, wipe, strsplit = pairs, ipairs, wipe, strsplit
local tsort = table.sort
local floor, max = math.floor, math.max

-- WoW API
local GetTime = GetTime

local state = GRIP.state
local W = GRIP.UIW

-- Extra right inset for UIPanelScrollFrameTemplate so the scrollbar/art never clips outside the page.
-- (Matches the same "give it room" approach used in scroll pages.)
local HOME_SCROLL_RIGHT_INSET = 34

-- FauxScrollFrame padding constants
local POT_HEADER_H = 20
local POT_ROW_H    = 18
local POT_ROWS_MIN = 10

-- Blacklist panel layout constants (also in UI_Home_Blacklist.lua)
local BL_PANEL_WIDE_WIDTH = 320
local BL_PANEL_STACK_H    = 160
local BL_GAP              = 10

-- Minimum width for the Potential panel when in two-column mode.
-- This is sized so the header can always fit through Zone + W + I without crossing into the Blacklist region.
local POT_MIN_TWO_COL_W = 500

local HasDB = function() return GRIP:HomeHasDB() end

local ClampFontString = function(fs, w) GRIP:ClampFontString(fs, w) end

local function GetScanCooldown()
  local cfg = (GRIPDB_CHAR and GRIPDB_CHAR.config) or nil
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
    local ea = GRIPDB_CHAR.potential and GRIPDB_CHAR.potential[a] or nil
    local eb = GRIPDB_CHAR.potential and GRIPDB_CHAR.potential[b] or nil
    local ta = GetEntryTimestamp(ea)
    local tb = GetEntryTimestamp(eb)
    if ta ~= tb then return ta > tb end
    return tostring(a) < tostring(b)
  end)
  return names
end

local function BuildPotentialNameList()
  local t = {}
  if not (GRIPDB_CHAR and GRIPDB_CHAR.potential) then return t end
  for name, _ in pairs(GRIPDB_CHAR.potential) do
    if type(name) == "string" and name ~= "" then
      t[#t + 1] = name
    end
  end
  return SortPotentialNewestFirst(t)
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
  else
    home.btnWhisperInvite:SetPoint("LEFT", home.btnScan, "RIGHT", 8, 0)
    home.btnPostNext:SetPoint("LEFT", home.btnWhisperInvite, "RIGHT", 8, 0)
    home.btnClear:SetPoint("TOPRIGHT", home, "TOPRIGHT", -padR, yTop)
  end

  -- Ghost strip anchors below the button rows
  if home.ghostStrip then
    home.ghostStrip:ClearAllPoints()
    if narrow then
      home.ghostStrip:SetPoint("TOPLEFT", home.btnWhisperInvite, "BOTTOMLEFT", 0, -4)
    else
      home.ghostStrip:SetPoint("TOPLEFT", home.btnScan, "BOTTOMLEFT", 0, -4)
    end
    home.ghostStrip:SetPoint("RIGHT", home, "RIGHT", -4, 0)
  end

  -- Hint always below ghost strip (if shown) or below buttons
  home.hint:ClearAllPoints()
  if home.ghostStrip and home.ghostStrip:IsShown() then
    home.hint:SetPoint("TOPLEFT", home.ghostStrip, "BOTTOMLEFT", 0, -4)
  else
    if narrow then
      home.hint:SetPoint("TOPLEFT", home.btnWhisperInvite, "BOTTOMLEFT", 0, -6)
    else
      home.hint:SetPoint("TOPLEFT", home.btnScan, "BOTTOMLEFT", 0, -6)
    end
  end

  -- Hint separator
  if home.hintSep then
    home.hintSep:ClearAllPoints()
    home.hintSep:SetPoint("TOPLEFT", home.hint, "BOTTOMLEFT", 0, -3)
    home.hintSep:SetPoint("RIGHT", home, "RIGHT", -4, 0)
  end
end

local function LayoutHomePanels(home)
  if not home or not home.potFrame then return end
  GRIP:EnsureBlacklistShell(home)

  local topY = -74
  local bottomY = 4
  local leftX = 4
  local rightX = -HOME_SCROLL_RIGHT_INSET

  if home.btnWhisperInvite and home.btnWhisperInvite:GetPoint(1) == "TOPLEFT" then
    topY = -96
  end

  -- Add ghost strip height if visible
  if home.ghostStrip and home.ghostStrip:IsShown() then
    topY = topY - 28
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

  -- Tooltip overlays for W/I column headers
  home.hWBtn = CreateFrame("Button", nil, header)
  home.hWBtn:SetAllPoints(home.hW)
  home.hWBtn:EnableMouse(true)
  if home.hWBtn.SetPassThroughButtons then home.hWBtn:SetPassThroughButtons() end
  GRIP:AttachTooltip(home.hWBtn, "Whisper Status", "\xE2\x9C\x93 = whisper sent successfully\n\xE2\x9C\x97 = whisper failed\n\xE2\x80\x94 = not yet attempted")

  home.hIBtn = CreateFrame("Button", nil, header)
  home.hIBtn:SetAllPoints(home.hI)
  home.hIBtn:EnableMouse(true)
  if home.hIBtn.SetPassThroughButtons then home.hIBtn:SetPassThroughButtons() end
  GRIP:AttachTooltip(home.hIBtn, "Invite Status", "\xE2\x9C\x93 = invite accepted\n\xE2\x9C\x97 = declined or failed\n\xE2\x8F\xB3 = pending (waiting for response)\n\xE2\x80\x94 = not yet attempted")

  local sf = CreateFrame("ScrollFrame", nil, pot, "FauxScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  sf:SetPoint("BOTTOMRIGHT", pot, "BOTTOMRIGHT", -2, 0)
  home.potScroll = sf

  local empty = pot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("CENTER", pot, "CENTER", 0, 0)
  empty:SetText("No potential candidates yet. Click Scan to begin.")
  empty:Hide()
  home.potEmpty = empty

  -- Row pool (dynamic row count based on visible height)
  local function initPotRow(frame)
    frame:SetHeight(POT_ROW_H)
    frame:Hide()

    frame.stripe = frame:CreateTexture(nil, "BACKGROUND")
    frame.stripe:SetAllPoints(frame)
    frame.stripe:SetColorTexture(1, 1, 1, 0.08)
    frame.stripe:Hide()

    frame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.name:SetJustifyH("LEFT")
    if frame.name.SetWordWrap then frame.name:SetWordWrap(false) end

    frame.lvl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.lvl:SetJustifyH("LEFT")
    if frame.lvl.SetWordWrap then frame.lvl:SetWordWrap(false) end

    frame.classIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.classIcon:SetSize(14, 14)
    frame.classIcon:Hide()

    frame.classTxt = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.classTxt:SetJustifyH("LEFT")
    if frame.classTxt.SetWordWrap then frame.classTxt:SetWordWrap(false) end

    frame.race = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.race:SetJustifyH("LEFT")
    if frame.race.SetWordWrap then frame.race:SetWordWrap(false) end

    frame.zone = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.zone:SetJustifyH("LEFT")
    if frame.zone.SetWordWrap then frame.zone:SetWordWrap(false) end

    frame.wIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.wIcon:SetSize(14, 14)
    frame.wIcon:Hide()

    frame.iIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.iIcon:SetSize(14, 14)
    frame.iIcon:Hide()

    frame._nameKey = nil
    frame._home = home

    frame:SetScript("OnClick", function(self, button)
      if button ~= "RightButton" then return end
      if not HasDB() then return end
      local n = self._nameKey
      if type(n) ~= "string" or n == "" then return end
      GRIP:ShowRowMenu(self._home, self, n)
    end)

    frame:SetScript("OnEnter", function(self)
      local n = self._nameKey
      if not n or not HasDB() then return end
      local e = GRIPDB_CHAR.potential and GRIPDB_CHAR.potential[n]
      if not e then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(n, 1, 1, 1)
      local details = {}
      if e.level then details[#details+1] = "Level " .. e.level end
      if e.class then details[#details+1] = tostring(e.class) end
      if e.race then details[#details+1] = tostring(e.race) end
      if #details > 0 then
        GameTooltip:AddLine(table.concat(details, "  \xC2\xB7  "), 0.8, 0.8, 0.6)
      end
      if e.zone or e.area then
        GameTooltip:AddLine("Zone: " .. (e.zone or e.area or "Unknown"), 0.8, 0.8, 0.6)
      end
      if e.whisperAttempted then
        local ws = e.whisperSuccess == true and "|cff00ff00Sent|r" or e.whisperSuccess == false and "|cffff0000Failed|r" or "|cffffff00Pending|r"
        GameTooltip:AddLine("Whisper: " .. ws, 0.8, 0.8, 0.8)
      end
      if e.inviteAttempted then
        local is = e.invitePending and "|cffffff00Pending|r" or e.inviteSuccess == true and "|cff00ff00Accepted|r" or e.inviteSuccess == false and "|cffff0000Declined|r" or "|cff888888Unknown|r"
        GameTooltip:AddLine("Invite: " .. is, 0.8, 0.8, 0.8)
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
    end)
  end

  local function resetPotRow(pool, frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame._nameKey = nil
    if frame.stripe then frame.stripe:Hide() end
    if frame.classIcon then frame.classIcon:Hide() end
    if frame.wIcon then frame.wIcon:Hide() end
    if frame.iIcon then frame.iIcon:Hide() end
  end

  home._potPool = CreateFramePool("Button", pot, nil, resetPotRow, false, initPotRow)
  home.potRows = {}

  local function OnScroll()
    GRIP:UI_UpdateHome()
  end
  sf:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, POT_ROW_H, OnScroll)
  end)

  GRIP:EnsureBlacklistShell(home)
end

local function ResizePotentialRows(home)
  if not home or not home.potFrame or not home.potScroll or not home._potPool then return end
  local sf = home.potScroll
  local h = tonumber(sf:GetHeight()) or 0
  if h <= 0 then return end
  local needed = math.floor(h / POT_ROW_H) + 1
  if needed < POT_ROWS_MIN then needed = POT_ROWS_MIN end
  local current = #home.potRows
  if needed == current then return end
  if needed > current then
    for i = current + 1, needed do
      local row = home._potPool:Acquire()
      home.potRows[i] = row
    end
  else
    for i = needed + 1, current do
      home._potPool:Release(home.potRows[i])
      home.potRows[i] = nil
    end
  end
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

  ResizePotentialRows(home)

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
      local e = GRIPDB_CHAR.potential[name] or {}

      row._nameKey = name
      row.name:SetText(name)

      -- Class-colored name
      local token = ClassTokenFromEntryClass(e.class)
      local cc = token and (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[token] or RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
      if cc then
        row.name:SetTextColor(cc.r, cc.g, cc.b)
      else
        row.name:SetTextColor(1, 1, 1)
      end

      local lvl = e.level and tostring(e.level) or "?"
      row.lvl:SetText(lvl)

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

function GRIP:UpdateGhostStrip()
  if not state.ui or not state.ui.home then return end
  local home = state.ui.home
  if not home.ghostStrip then return end

  local Ghost = GRIP.Ghost
  if not Ghost or not Ghost.IsEnabled then
    home.ghostStrip:Hide()
    return
  end
  if not Ghost:IsEnabled() then
    home.ghostStrip:Hide()
    return
  end

  home.ghostStrip:Show()

  local function FmtTime(sec)
    sec = math.max(0, math.floor(sec))
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
  end

  if Ghost:IsSessionActive() then
    local elapsed = Ghost:GetSessionElapsed()
    local maxSec = Ghost:GetSessionMaxSeconds()
    local pending = Ghost:GetNumPending()
    local actions = (state.ghost and state.ghost.sessionActionCount) or 0
    home.ghostLabel:SetText(
      ("|cff00ff00Ghost: Active|r  %s / %s  |  Queue: %d  |  Actions: %d"):format(
        FmtTime(elapsed), FmtTime(maxSec), pending, actions))
    home.ghostBtn:SetText("Stop")
    W.SetEnabledSafe(home.ghostBtn, true)
  else
    local cooldown = Ghost:GetCooldownRemaining()
    if cooldown > 0 then
      home.ghostLabel:SetText(
        ("|cffff8800Ghost: Cooldown|r  %s remaining"):format(FmtTime(cooldown)))
      home.ghostBtn:SetText("Start")
      W.SetEnabledSafe(home.ghostBtn, false)
    else
      home.ghostLabel:SetText("|cff888888Ghost: Ready|r")
      home.ghostBtn:SetText("Start")
      W.SetEnabledSafe(home.ghostBtn, true)
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
  GRIP:LayoutBlacklistPanel(home)
end

function GRIP:UI_CreateHome(parent)
  local home = CreateFrame("Frame", nil, parent)
  home:SetAllPoints(true)

  home.status = home:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  home.status:SetPoint("TOPLEFT", home, "TOPLEFT", 4, -2)
  home.status:SetJustifyH("LEFT")
  home.status:SetText("\xE2\x80\xA6")

  -- Separator between status bar and buttons
  home.statusSep = home:CreateTexture(nil, "ARTWORK")
  home.statusSep:SetPoint("TOPLEFT", home, "TOPLEFT", 4, -22)
  home.statusSep:SetPoint("TOPRIGHT", home, "TOPRIGHT", -4, -22)
  home.statusSep:SetHeight(1)
  home.statusSep:SetColorTexture(1, 1, 1, 0.08)

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
    local count = GRIP:Count(GRIPDB_CHAR.potential)
    if count > 10 then
      GRIP:ConfirmClearPotential(count)
      return
    end
    wipe(GRIPDB_CHAR.potential)
    wipe(state.whisperQueue)
    wipe(state.pendingWhisper)
    wipe(state.pendingInvite)
    GRIP:Print("Cleared Potential list.")
    GRIP:UpdateUI()
  end)
  home.btnClear:SetPoint("TOPRIGHT", home, "TOPRIGHT", -4, -24)

  -- Destructive action visual cue
  local clearText = home.btnClear:GetFontString()
  if clearText then
    clearText:SetTextColor(1, 0.6, 0.6)
  end

  -- Button tooltips
  GRIP:AttachTooltip(home.btnScan, "Scan", function()
    local pos = math.max(0, (state.whoIndex or 1) - 1)
    local total = #state.whoQueue
    return "Send next /who query.\nRequires keybind or button click.\nQueue: " .. pos .. "/" .. total .. " remaining"
  end)
  GRIP:AttachTooltip(home.btnWhisperInvite, "Whisper+Invite Next", function()
    local wq = #state.whisperQueue
    local pending = 0
    if state.pendingInvite and type(state.pendingInvite) == "table" then
      for _ in pairs(state.pendingInvite) do pending = pending + 1 end
    end
    return "Whisper the next candidate, then queue\na guild invite.\nRequires keybind or button click.\nWhisper queue: " .. wq .. "  |  Pending invites: " .. pending
  end)
  GRIP:AttachTooltip(home.btnPostNext, "Post Next", function()
    return "Send next Trade/General channel post.\nRequires keybind or button click.\nQueue: " .. #state.postQueue .. " posts remaining"
  end)
  GRIP:AttachTooltip(home.btnClear, "Clear Potential List", "Remove all candidates from the Potential list.\nDoes NOT affect blacklists or whisper history.")

  -- Ghost Mode status strip
  home.ghostStrip = CreateFrame("Frame", nil, home)
  home.ghostStrip:SetHeight(24)
  home.ghostStrip:SetPoint("TOPLEFT", home.btnScan, "BOTTOMLEFT", 0, -4)
  home.ghostStrip:SetPoint("RIGHT", home, "RIGHT", -4, 0)

  home.ghostLabel = home.ghostStrip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  home.ghostLabel:SetPoint("LEFT", home.ghostStrip, "LEFT", 0, 0)
  home.ghostLabel:SetJustifyH("LEFT")
  home.ghostLabel:SetText("")

  home.ghostBtn = W.CreateUIButton(home.ghostStrip, "Start", 60, 20, function()
    if not HasDB() then return end
    local Ghost = GRIP.Ghost
    if not Ghost then return end
    if Ghost:IsSessionActive() then
      Ghost:StopSession("manual")
      GRIP:Print("Ghost Mode session stopped.")
    else
      Ghost:StartSession()
    end
    GRIP:UpdateUI()
  end)
  home.ghostBtn:SetPoint("LEFT", home.ghostLabel, "RIGHT", 8, 0)

  home.ghostStrip._lastUpdate = 0
  home.ghostStrip:SetScript("OnUpdate", function(self, elapsed)
    self._lastUpdate = (self._lastUpdate or 0) + elapsed
    if self._lastUpdate < 1 then return end
    self._lastUpdate = 0
    GRIP:UpdateGhostStrip()
  end)

  home.hint = home:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  home.hint:SetPoint("TOPLEFT", home.ghostStrip, "BOTTOMLEFT", 0, -4)
  home.hint:SetPoint("RIGHT", home, "RIGHT", -4, 0)
  home.hint:SetText("Tip: /grip help  \xC2\xB7  None selected in filters = allow all")

  -- Separator between hint line and table
  home.hintSep = home:CreateTexture(nil, "ARTWORK")
  home.hintSep:SetHeight(1)
  home.hintSep:SetColorTexture(1, 1, 1, 0.08)

  EnsurePotentialTable(home)

  LayoutButtons(home)
  LayoutHomePanels(home)
  LayoutPotentialTable(home)
  GRIP:LayoutBlacklistPanel(home)

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
  GRIP:LayoutBlacklistPanel(home)

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

    W.SetEnabledSafe(home.btnScan, false)
    W.SetEnabledSafe(home.btnWhisperInvite, false)
    W.SetEnabledSafe(home.btnPostNext, false)
    W.SetEnabledSafe(home.btnClear, false)

    if home.ghostStrip then home.ghostStrip:Hide() end

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

  W.SetEnabledSafe(home.btnScan, true)
  W.SetEnabledSafe(home.btnWhisperInvite, true)
  W.SetEnabledSafe(home.btnPostNext, true)
  W.SetEnabledSafe(home.btnClear, true)

  local pot = self:Count(GRIPDB_CHAR.potential)
  local blPerm = self:Count(GRIPDB.blacklistPerm)
  local blTemp = self:Count(GRIPDB.blacklist)

  local whoPos = math.max(0, (state.whoIndex - 1))
  local whoTotal = #state.whoQueue
  local wq = #state.whisperQueue
  local pq = #state.postQueue
  local whisperOn = state.whisperTicker and "ON" or "OFF"
  local whoPending = state.pendingWho and " (waiting…)" or ""

  local sent, cap = GRIP:GetWhisperCapStatus()

  local whisperColor = state.whisperTicker and "|cff00ff00" or "|cffff0000"
  local whisperLabel = whisperColor .. whisperOn .. "|r"
  local blTempColor = blTemp > 0 and "|cffff8800" or "|cff888888"
  local capColor = ""
  local capEnd = ""
  if cap > 0 and sent >= cap * 0.8 then
    capColor = "|cffff4444"
    capEnd = "|r"
  end
  local capLine = ""
  if cap > 0 then
    capLine = ("   |   Sent: %s%d/%d%s"):format(capColor, sent, cap, capEnd)
  end
  home.status:SetText(
    ("Potential: |cffffffff%d|r   |   BL: |cff888888perm %d|r  %stemp %d|r\n"
  .. "Who: %d/%d%s   |   Whisper: %d (%s)   |   Post: %d%s"):format(
      pot, blPerm, blTempColor, blTemp,
      whoPos, whoTotal, whoPending, wq, whisperLabel, pq, capLine
    )
  )

  -- Contextual hint
  local hintText = nil
  local Ghost = GRIP.Ghost
  if Ghost and Ghost.IsEnabled and Ghost:IsEnabled() and Ghost.IsSessionActive and Ghost:IsSessionActive() then
    hintText = nil  -- Ghost strip takes over
  elseif pot == 0 and whoTotal == 0 then
    hintText = "Click Scan or press your Scan keybind to find unguilded players"
  elseif wq > 0 and not state.whisperTicker then
    hintText = ("Whisper queue has %d candidates \xE2\x80\x94 click Whisper+Invite to start"):format(wq)
  elseif blTemp > 20 then
    local days = tonumber(GRIPDB_CHAR and GRIPDB_CHAR.config and GRIPDB_CHAR.config.blacklistDays) or 14
    hintText = ("%d temp-blacklisted players will expire in ~%d days"):format(blTemp, days)
  else
    hintText = "Tip: /grip help  \xC2\xB7  Right-click rows for options"
  end
  if hintText then
    home.hint:SetText(hintText)
    home.hint:Show()
  else
    home.hint:SetText("")
    home.hint:Hide()
  end

  if home.blFrame and home.blFrame.header and home.blFrame.header.title then
    home.blFrame.header.title:SetText(("Blacklist (perm %d; temp %d)"):format(blPerm or 0, blTemp or 0))
  end

  local scanLeft = GRIP:SecondsLeft(f._scanCooldownUntil)
  if scanLeft > 0 then
    home.btnScan:Disable()
    home.btnScan:SetText(("Scan (%.0fs)"):format(math.ceil(scanLeft)))
  else
    home.btnScan:Enable()
    home.btnScan:SetText("Scan")
  end

  local recruitLeft = GRIP:SecondsLeft(GetRecruitCooldownUntil())
  if recruitLeft > 0 then
    home.btnWhisperInvite:Disable()
  else
    home.btnWhisperInvite:Enable()
  end

  local postLeft = GRIP:SecondsLeft(GetPostCooldownUntil())
  if postLeft > 0 then
    home.btnPostNext:Disable()
  else
    home.btnPostNext:Enable()
  end

  self:UpdateGhostStrip()
  UpdatePotentialRows(home)
  GRIP:UpdateBlacklistRows(home)
end
