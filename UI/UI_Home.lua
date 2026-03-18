-- GRIP: UI Home Page
-- Potential candidate list, buttons, Ghost strip, layout orchestration.
-- Popup dialogs → UI_Home_Popups.lua | Blacklist panel → UI_Home_Blacklist.lua | Context menu → UI_Home_Menu.lua

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, ipairs, wipe, strsplit = pairs, ipairs, wipe, strsplit
local tsort = table.sort
local upper, sub = string.upper, string.sub
local floor, max, ceil = math.floor, math.max, math.ceil

-- WoW API
local GetTime = GetTime

local state = GRIP.state
local W = GRIP.UIW
local L = LibStub("AceLocale-3.0"):GetLocale("GRIP")

-- Extra right inset so the scrollbar never clips outside the page.
local HOME_SCROLL_RIGHT_INSET = 34

-- Potential list layout constants
local POT_HEADER_H = 20
local POT_ROW_H    = 18
local CLASS_BAR_W  = 4

-- Blacklist panel layout constants (also in UI_Home_Blacklist.lua)
local BL_PANEL_WIDE_WIDTH = 320
local BL_PANEL_STACK_H    = 160
local BL_GAP              = 10

-- Minimum width for the Potential panel when in two-column mode.
-- This is sized so the header can always fit through Zone + W + I without crossing into the Blacklist region.
local POT_MIN_TWO_COL_W = 500

local HasDB = function() return GRIP:HomeHasDB() end

local ClampFontString = function(fs, w) GRIP:ClampFontString(fs, w) end

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
  return upper(s)
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
  if #u >= 3 then return sub(u, 1, 3) end
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
  tsort(names, function(a, b)
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

  local yTop = -44

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

  local topY = -94
  local bottomY = 4
  local leftX = 4
  local rightX = -HOME_SCROLL_RIGHT_INSET

  if home.btnWhisperInvite and home.btnWhisperInvite:GetPoint(1) == "TOPLEFT" then
    topY = -116
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
  pot:SetPoint("TOPLEFT", home, "TOPLEFT", 4, -94)
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
  header.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  header.bg:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0.03), CreateColor(1, 1, 1, 0.09))

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

  home.hName   = H(L["Name"])
  home.hLvl    = H(L["Lvl"])
  home.hClass  = H(L["Class"])
  home.hRace   = H(L["Race"])
  home.hZone   = H(L["Zone"])
  home.hRio    = H(L["M+"])
  home.hW      = H(L["W"])
  home.hI      = H(L["I"])

  -- Tooltip overlays for W/I column headers
  home.hWBtn = CreateFrame("Button", nil, header)
  home.hWBtn:SetAllPoints(home.hW)
  home.hWBtn:EnableMouse(true)
  if home.hWBtn.SetPassThroughButtons then home.hWBtn:SetPassThroughButtons() end
  GRIP:AttachTooltip(home.hWBtn, L["Whisper Status"], L["W = Whisper status for this candidate."])

  home.hIBtn = CreateFrame("Button", nil, header)
  home.hIBtn:SetAllPoints(home.hI)
  home.hIBtn:EnableMouse(true)
  if home.hIBtn.SetPassThroughButtons then home.hIBtn:SetPassThroughButtons() end
  GRIP:AttachTooltip(home.hIBtn, L["Invite Status"], L["I = Invite status for this candidate."])

  -- ScrollBox + ScrollBar (replaces FauxScrollFrame + row pool)
  local scrollBox = CreateFrame("Frame", nil, pot, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", pot, "BOTTOMRIGHT", -16, 0)
  home.potScrollBox = scrollBox

  local scrollBar = CreateFrame("EventFrame", nil, pot, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
  scrollBar:SetHideIfUnscrollable(true)

  local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 0)
  view:SetElementExtent(POT_ROW_H)
  home._potView = view

  view:SetElementInitializer("Button", function(row, elementData)
    if not row._initialized then
      row._initialized = true
      row:SetHeight(POT_ROW_H)

      row.stripe = row:CreateTexture(nil, "BACKGROUND")
      row.stripe:SetAllPoints(row)
      row.stripe:SetColorTexture(1, 1, 1, 0.08)
      row.stripe:Hide()

      row.hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
      row.hoverBg:SetAllPoints(row)
      row.hoverBg:SetColorTexture(1, 1, 1, 0)
      row.hoverBg:Hide()

      row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

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

      row.rioText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.rioText:SetJustifyH("RIGHT")
      if row.rioText.SetWordWrap then row.rioText:SetWordWrap(false) end

      row.wIcon = row:CreateTexture(nil, "OVERLAY")
      row.wIcon:SetSize(14, 14)
      row.wIcon:Hide()

      row.iIcon = row:CreateTexture(nil, "OVERLAY")
      row.iIcon:SetSize(14, 14)
      row.iIcon:Hide()

      row.classBar = row:CreateTexture(nil, "ARTWORK")
      row.classBar:SetWidth(2)
      row.classBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
      row.classBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
      row.classBar:SetColorTexture(1, 1, 1, 0)
      row.classBar:Show()

      row._nameKey = nil
      row._home = home

      row:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        if not HasDB() then return end
        local n = self._nameKey
        if type(n) ~= "string" or n == "" then return end
        GRIP:ShowRowMenu(self._home, self, n)
      end)

      row:SetScript("OnEnter", function(self)
        if self.hoverBg then
          if self._classColor then
            self.hoverBg:SetColorTexture(self._classColor.r, self._classColor.g, self._classColor.b, 0.10)
          else
            self.hoverBg:SetColorTexture(1, 0.82, 0, 0.08)
          end
          self.hoverBg:Show()
        end
        local n = self._nameKey
        if not n or not HasDB() then return end
        local e = GRIPDB_CHAR.potential and GRIPDB_CHAR.potential[n]
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(n, 1, 1, 1)
        local details = {}
        if e.level then details[#details+1] = (L["Level %d"]):format(e.level) end
        if e.class then details[#details+1] = tostring(e.class) end
        if e.race then details[#details+1] = tostring(e.race) end
        if #details > 0 then
          GameTooltip:AddLine(table.concat(details, "  ·  "), 0.8, 0.8, 0.6)
        end
        if e.zone or e.area then
          GameTooltip:AddLine((L["Zone: %s"]):format(e.zone or e.area or "Unknown"), 0.8, 0.8, 0.6)
        end
        if e.rioScore then
          GameTooltip:AddLine((L["M+ Score: %s"]):format(tostring(e.rioScore)), 0.6, 0.8, 1.0)
        end
        if e.whisperAttempted then
          local ws = e.whisperSuccess == true and "|cff00ff00" .. L["Sent"] .. "|r" or e.whisperSuccess == false and "|cffff0000" .. L["Failed"] .. "|r" or "|cffffff00" .. L["Pending"] .. "|r"
          GameTooltip:AddLine((L["Whisper: %s"]):format(ws), 0.8, 0.8, 0.8)
        end
        if e.inviteAttempted then
          local is = e.invitePending and "|cffffff00" .. L["Pending"] .. "|r" or e.inviteSuccess == true and "|cff00ff00" .. L["Accepted"] .. "|r" or e.inviteSuccess == false and "|cffff0000" .. L["Declined"] .. "|r" or "|cff888888" .. L["Unknown"] .. "|r"
          GameTooltip:AddLine((L["Invite: %s"]):format(is), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Right-click for options"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function(self)
        if self.hoverBg then self.hoverBg:Hide() end
        GameTooltip:Hide()
      end)
    end

    -- Populate data (runs every time row scrolls into view)
    local cw = home._colWidths
    if not cw then return end

    local nameKey = elementData.key
    local e = elementData.entry
    local idx = elementData.index

    row._nameKey = nameKey

    -- Position sub-elements using stored column widths
    local pad = cw.pad
    local rx = pad + CLASS_BAR_W

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.name, cw.name)
    rx = rx + cw.name + pad

    row.lvl:ClearAllPoints()
    row.lvl:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.lvl, cw.lvl)
    rx = rx + cw.lvl + pad

    row.classIcon:ClearAllPoints()
    row.classIcon:SetPoint("LEFT", row, "LEFT", rx, 0)

    row.classTxt:ClearAllPoints()
    row.classTxt:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)
    ClampFontString(row.classTxt, cw.class - 18)
    rx = rx + cw.class + pad

    row.race:ClearAllPoints()
    row.race:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.race, cw.race)
    rx = rx + cw.race + pad

    row.zone:ClearAllPoints()
    row.zone:SetPoint("LEFT", row, "LEFT", rx, 0)
    ClampFontString(row.zone, cw.zone)
    rx = rx + cw.zone + pad

    -- FE3: Raider.IO M+ column (conditional)
    if cw.rio and cw.rio > 0 then
      row.rioText:ClearAllPoints()
      row.rioText:SetPoint("LEFT", row, "LEFT", rx, 0)
      ClampFontString(row.rioText, cw.rio)
      row.rioText:Show()
      rx = rx + cw.rio + pad
    else
      row.rioText:Hide()
    end

    row.wIcon:ClearAllPoints()
    row.wIcon:SetPoint("LEFT", row, "LEFT", rx + 2 + cw.seamPad, 0)
    rx = rx + cw.wi + pad

    row.iIcon:ClearAllPoints()
    row.iIcon:SetPoint("LEFT", row, "LEFT", rx + 2 + cw.seamPad, 0)

    -- Set data
    row.name:SetText(nameKey)

    local token = ClassTokenFromEntryClass(e.class)
    local cc = token and (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[token] or RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
    if cc then
      row.name:SetTextColor(cc.r, cc.g, cc.b)
    else
      row.name:SetTextColor(1, 1, 1)
    end

    row._classColor = cc or nil

    if row.classBar then
      if cc then
        row.classBar:SetColorTexture(cc.r, cc.g, cc.b, 0.7)
      else
        row.classBar:SetColorTexture(1, 1, 1, 0)
      end
    end

    row.lvl:SetText(e.level and tostring(e.level) or "?")

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

    -- FE3: M+ score
    if cw.rio and cw.rio > 0 then
      local score = e.rioScore
      row.rioText:SetText(score and tostring(score) or "—")
    end

    SetStatusIcon(row.wIcon, e.whisperAttempted, e.whisperSuccess, false)
    SetStatusIcon(row.iIcon, e.inviteAttempted, e.inviteSuccess, e.invitePending)

    if row.stripe then
      if (idx % 2) == 0 then row.stripe:Show() else row.stripe:Hide() end
    end
    if row.hoverBg then row.hoverBg:Hide() end
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  -- Empty state
  local empty = pot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("CENTER", pot, "CENTER", 0, 0)
  empty:SetText(L["No potential candidates yet. Click Scan to begin."])
  empty:Hide()
  home.potEmpty = empty

  local emptyIcon = pot:CreateTexture(nil, "OVERLAY")
  emptyIcon:SetSize(32, 32)
  emptyIcon:SetPoint("BOTTOM", empty, "TOP", 0, 4)
  emptyIcon:SetTexture("Interface\\COMMON\\UI-Searchbox-Icon")
  emptyIcon:SetAlpha(0.3)
  emptyIcon:Hide()
  home.potEmptyIcon = emptyIcon

  GRIP:EnsureBlacklistShell(home)
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

  -- FE3: Raider.IO M+ column (conditional on addon presence + config)
  local cfg = (_G.GRIPDB_CHAR and GRIPDB_CHAR.config) or {}
  local showRio = (cfg.rioShowColumn ~= false) and GRIP:IsRaiderIOAvailable()
  local wRio = showRio and 50 or 0

  local fixed = pad + wName + wLvl + wClass + wRace + wWI + wWI + (pad * 6)
  if wRio > 0 then fixed = fixed + wRio + pad end
  local wZone = usable - fixed

  if wZone < 80 then
    local deficit = 80 - wZone
    wZone = 80
    wName = max(100, wName - deficit)
  end

  local seamPad = 4

  local x = pad + CLASS_BAR_W
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

  -- FE3: M+ header (conditional)
  if wRio > 0 then
    home.hRio:ClearAllPoints()
    home.hRio:SetPoint("LEFT", home.potHeader, "LEFT", x, 0)
    ClampFontString(home.hRio, wRio)
    home.hRio:Show()
    x = x + wRio + pad
  else
    home.hRio:Hide()
  end

  home.hW:ClearAllPoints()
  home.hW:SetPoint("LEFT", home.potHeader, "LEFT", x + seamPad, 0)
  ClampFontString(home.hW, wWI)
  x = x + wWI + pad

  home.hI:ClearAllPoints()
  home.hI:SetPoint("LEFT", home.potHeader, "LEFT", x + seamPad, 0)
  ClampFontString(home.hI, wWI)

  -- Store column widths for the ScrollBox element initializer
  home._colWidths = {
    name = wName, lvl = wLvl, class = wClass, race = wRace,
    zone = wZone, rio = wRio, wi = wWI, pad = pad, seamPad = seamPad,
  }
end

local function RefreshPotentialData(home)
  if not home or not home.potScrollBox then return end
  if not HasDB() then return end

  local names = BuildPotentialNameList()
  home._potNames = names

  local total = #names

  if total == 0 then
    if home.potEmpty then home.potEmpty:Show() end
    if home.potEmptyIcon then home.potEmptyIcon:Show() end
  else
    if home.potEmpty then home.potEmpty:Hide() end
    if home.potEmptyIcon then home.potEmptyIcon:Hide() end
  end

  local data = {}
  for i, name in ipairs(names) do
    local e = GRIPDB_CHAR.potential[name] or {}
    data[i] = { key = name, entry = e, index = i }
  end

  local provider = CreateDataProvider()
  provider:InsertTable(data)
  home.potScrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
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
    sec = max(0, floor(sec))
    return ("%d:%02d"):format(floor(sec / 60), sec % 60)
  end

  if Ghost:IsSessionActive() then
    local elapsed = Ghost:GetSessionElapsed()
    local maxSec = Ghost:GetSessionMaxSeconds()
    local pending = Ghost:GetNumPending()
    local actions = (state.ghost and state.ghost.sessionActionCount) or 0
    home.ghostLabel:SetText(
      (L["|cff00ff00Ghost: Active|r  %s / %s  |  Queue: %d  |  Actions: %d"]):format(
        FmtTime(elapsed), FmtTime(maxSec), pending, actions))
    home.ghostBtn:SetText(L["Stop"])
    W.SetEnabledSafe(home.ghostBtn, true)
    if home.ghostStrip.SetBackdropColor then
      home.ghostStrip:SetBackdropColor(0, 1, 0, 0.05)
      home.ghostStrip:SetBackdropBorderColor(0, 1, 0, 0.25)
    end
  else
    local cooldown = Ghost:GetCooldownRemaining()
    if cooldown > 0 then
      home.ghostLabel:SetText(
        (L["|cffff8800Ghost: Cooldown|r  %s remaining"]):format(FmtTime(cooldown)))
      home.ghostBtn:SetText(L["Start"])
      W.SetEnabledSafe(home.ghostBtn, false)
      if home.ghostStrip.SetBackdropColor then
        home.ghostStrip:SetBackdropColor(1, 0.5, 0, 0.05)
        home.ghostStrip:SetBackdropBorderColor(1, 0.5, 0, 0.25)
      end
    else
      home.ghostLabel:SetText(L["|cff888888Ghost: Ready|r"])
      home.ghostBtn:SetText(L["Start"])
      W.SetEnabledSafe(home.ghostBtn, true)
      if home.ghostStrip.SetBackdropColor then
        home.ghostStrip:SetBackdropColor(0, 0, 0, 0)
        home.ghostStrip:SetBackdropBorderColor(1, 1, 1, 0)
      end
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

local function AddButtonIcon(btn, texturePath, btnWidth)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(14, 14)
  icon:SetPoint("LEFT", btn, "LEFT", 6, 0)
  icon:SetTexture(texturePath)
  btn._icon = icon
  local fs = btn:GetFontString()
  if fs then
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
  end
  btn:SetWidth(btnWidth)
end

function GRIP:UI_CreateHome(parent)
  local home = CreateFrame("Frame", nil, parent)
  home:SetAllPoints(true)

  -- Bordered status panel
  home.statusPanel = CreateFrame("Frame", nil, home, "BackdropTemplate")
  home.statusPanel:SetPoint("TOPLEFT", home, "TOPLEFT", 4, -2)
  home.statusPanel:SetPoint("TOPRIGHT", home, "TOPRIGHT", -4, -2)
  home.statusPanel:SetHeight(38)
  home.statusPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  home.statusPanel:SetBackdropColor(1, 1, 1, 0.03)
  home.statusPanel:SetBackdropBorderColor(1, 1, 1, 0.08)

  home.status = home.statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  home.status:SetPoint("TOPLEFT", home.statusPanel, "TOPLEFT", 8, -4)
  home.status:SetPoint("BOTTOMRIGHT", home.statusPanel, "BOTTOMRIGHT", -8, 4)
  home.status:SetJustifyH("LEFT")
  home.status:SetJustifyV("TOP")
  home.status:SetText("…")

  -- Separator between status panel and buttons
  home.statusSep = home:CreateTexture(nil, "ARTWORK")
  home.statusSep:SetPoint("TOPLEFT", home.statusPanel, "BOTTOMLEFT", 0, -2)
  home.statusSep:SetPoint("TOPRIGHT", home.statusPanel, "BOTTOMRIGHT", 0, -2)
  home.statusSep:SetHeight(1)
  home.statusSep:SetColorTexture(1, 1, 1, 0.08)

  home.btnScan = W.CreateUIButton(home, L["Scan"], 90, 24, function()
    if not HasDB() then
      GRIP:Print(L["Home unavailable yet (DB not initialized)."])
      return
    end
    -- Immediate disable to prevent same-frame spam clicks
    home.btnScan:Disable()
    GRIP:Debug("UI: Scan pressed")
    GRIP:SendNextWho()
    GRIP:UpdateUI()
  end)
  home.btnScan:SetPoint("TOPLEFT", home, "TOPLEFT", 4, -44)

  home.btnWhisperInvite = W.CreateUIButton(home, L["Whisper+Invite Next"], 160, 24, function()
    if not HasDB() then
      GRIP:Print(L["Home unavailable yet (DB not initialized)."])
      return
    end

    GRIP:Debug("UI: Whisper+Invite Next pressed")
    GRIP:InviteNext()
    GRIP:UpdateUI()
  end)
  home.btnWhisperInvite:SetPoint("LEFT", home.btnScan, "RIGHT", 8, 0)

  home.btnPostNext = W.CreateUIButton(home, L["Post Next"], 90, 24, function()
    if not HasDB() then
      GRIP:Print(L["Home unavailable yet (DB not initialized)."])
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

  home.btnClear = W.CreateUIButton(home, L["Clear"], 70, 20, function()
    if not HasDB() then
      GRIP:Print(L["Home unavailable yet (DB not initialized)."])
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
    GRIP:Print(L["Cleared Potential list."])
    GRIP:UpdateUI()
  end)
  home.btnClear:SetPoint("TOPRIGHT", home, "TOPRIGHT", -4, -44)

  -- Destructive action visual cue
  local clearText = home.btnClear:GetFontString()
  if clearText then
    clearText:SetTextColor(unpack(GRIP.COLORS.DANGER_RED))
  end

  -- Button icons (14x14, left of text)
  AddButtonIcon(home.btnScan, "Interface\\COMMON\\UI-Searchbox-Icon", 110)
  AddButtonIcon(home.btnWhisperInvite, "Interface\\GossipFrame\\GossipGossipIcon", 180)
  AddButtonIcon(home.btnPostNext, "Interface\\CHATFRAME\\UI-ChatIcon-Blizz", 110)

  -- Button tooltips
  GRIP:AttachTooltip(home.btnScan, L["Scan"], function()
    local pos = max(0, (state.whoIndex or 1) - 1)
    local total = #state.whoQueue
    return (L["Send next /who query.\nRequires keybind or button click.\nQueue: %d/%d remaining"]):format(pos, total)
  end)
  GRIP:AttachTooltip(home.btnWhisperInvite, L["Whisper+Invite Next"], function()
    local wq = #state.whisperQueue
    local pending = 0
    if state.pendingInvite and type(state.pendingInvite) == "table" then
      for _ in pairs(state.pendingInvite) do pending = pending + 1 end
    end
    return (L["Whisper the next candidate, then queue\na guild invite.\nRequires keybind or button click.\nWhisper queue: %d  |  Pending invites: %d"]):format(wq, pending)
  end)
  GRIP:AttachTooltip(home.btnPostNext, L["Post Next"], function()
    return (L["Send next Trade/General channel post.\nRequires keybind or button click.\nQueue: %d posts remaining"]):format(#state.postQueue)
  end)
  GRIP:AttachTooltip(home.btnClear, L["Clear Potential List"], L["Remove all candidates from the Potential list.\nDoes NOT affect blacklists or whisper history."])

  -- Button accent underlines
  W.AddButtonAccent(home.btnScan, 1, 0.82, 0)
  W.AddButtonAccent(home.btnWhisperInvite, 1, 0.82, 0)
  W.AddButtonAccent(home.btnPostNext, 1, 0.82, 0)
  W.AddButtonAccent(home.btnClear, 0.8, 0.3, 0.3)

  -- Ghost Mode status strip (with BackdropTemplate border)
  home.ghostStrip = CreateFrame("Frame", nil, home, "BackdropTemplate")
  home.ghostStrip:SetHeight(24)
  home.ghostStrip:SetPoint("TOPLEFT", home.btnScan, "BOTTOMLEFT", 0, -4)
  home.ghostStrip:SetPoint("RIGHT", home, "RIGHT", -4, 0)
  home.ghostStrip:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  home.ghostStrip:SetBackdropColor(0, 0, 0, 0)
  home.ghostStrip:SetBackdropBorderColor(1, 1, 1, 0)

  home.ghostLabel = home.ghostStrip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  home.ghostLabel:SetPoint("LEFT", home.ghostStrip, "LEFT", 0, 0)
  home.ghostLabel:SetJustifyH("LEFT")
  home.ghostLabel:SetText("")

  home.ghostBtn = W.CreateUIButton(home.ghostStrip, L["Start"], 60, 20, function()
    if not HasDB() then return end
    local Ghost = GRIP.Ghost
    if not Ghost then return end
    if Ghost:IsSessionActive() then
      Ghost:StopSession("manual")
      GRIP:Print(L["Ghost Mode session stopped."])
    else
      Ghost:StartSession()
    end
    GRIP:UpdateUI()
  end)
  home.ghostBtn:SetPoint("LEFT", home.ghostLabel, "RIGHT", 8, 0)

  home.ghostStrip._lastUpdate = 0
  home.ghostStrip:SetScript("OnUpdate", function(self, elapsed)
    self._lastUpdate = (self._lastUpdate or 0) + elapsed
    -- Visual pulse (runs every frame when ghost session active)
    local Ghost = GRIP.Ghost
    if Ghost and Ghost.IsSessionActive and Ghost:IsSessionActive() then
      self._pulseTime = (self._pulseTime or 0) + elapsed
      local alpha = 0.03 + 0.04 * (0.5 + 0.5 * math.sin(self._pulseTime * 1.5))
      if self.SetBackdropColor then
        self:SetBackdropColor(0, 1, 0, alpha)
      end
    else
      self._pulseTime = nil
    end
    -- Timer update (1s throttle)
    if self._lastUpdate < 1 then return end
    self._lastUpdate = 0
    GRIP:UpdateGhostStrip()
  end)

  home.hint = home:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  home.hint:SetPoint("TOPLEFT", home.ghostStrip, "BOTTOMLEFT", 0, -4)
  home.hint:SetPoint("RIGHT", home, "RIGHT", -4, 0)
  home.hint:SetText(L["Tip: /grip help  \194\183  None selected in filters = allow all"])

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

function GRIP:EnsureOnboarding(home)
  if not _G.GRIPDB_CHAR or not GRIPDB_CHAR.config then return end

  -- Smart-dismiss: skip onboarding if user already has recruitment data
  if _G.GRIPDB and (GRIP:Count(GRIPDB.blacklist) > 0 or GRIP:Count(GRIPDB.blacklistPerm) > 0) then
    return
  end
  if _G.GRIPDB_CHAR then
    if GRIP:Count(GRIPDB_CHAR.potential) > 0 then return end
    if GRIPDB_CHAR.stats and GRIPDB_CHAR.stats.today and (GRIPDB_CHAR.stats.today.whispers or 0) > 0 then return end
    if GRIPDB_CHAR.stats and GRIPDB_CHAR.stats.days and #GRIPDB_CHAR.stats.days > 0 then return end
  end

  if GRIPDB_CHAR.config._onboardingDismissed then return end
  if home._onboarding then return end
  local ob = CreateFrame("Frame", nil, home, "BackdropTemplate")
  ob:SetPoint("TOPLEFT", home.potFrame or home, "TOPLEFT", 10, -10)
  ob:SetPoint("BOTTOMRIGHT", home.potFrame or home, "BOTTOMRIGHT", -10, 10)
  ob:SetFrameStrata("DIALOG")
  ob:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  ob:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
  ob:SetBackdropBorderColor(1, 0.82, 0, 0.6)
  local title = ob:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", ob, "TOP", 0, -16)
  title:SetText("|cffffd100" .. L["Welcome to GRIP!"] .. "|r")
  local body = ob:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  body:SetPoint("TOP", title, "BOTTOM", 0, -12)
  body:SetPoint("LEFT", ob, "LEFT", 20, 0)
  body:SetPoint("RIGHT", ob, "RIGHT", -20, 0)
  body:SetJustifyH("LEFT")
  body:SetSpacing(4)
  body:SetText(
    "|cffffd100" .. L["Quick Setup:"] .. "|r\n\n"
    .. "|cffffffff" .. L["1. Settings tab: set your level range and zone/race/class filters."] .. "|r\n"
    .. "|cffffffff" .. L["2. Settings tab: edit your whisper template. Use {player} and {guildlink}."] .. "|r\n"
    .. "|cffffffff" .. L["3. Ads tab: write your Trade/General recruitment messages."] .. "|r\n"
    .. "|cffffffff" .. L["4. Click Scan to start finding unguilded players!"] .. "|r\n\n"
    .. "|cff888888" .. L["Tip: Hover any button for details. See /grip help for all commands."] .. "|r\n"
    .. "|cff888888" .. L["Tip: Right-click a candidate row for quick blacklist/invite actions."] .. "|r"
  )
  local dismiss = W.CreateUIButton(ob, L["Got it!"], 100, 26, function()
    if _G.GRIPDB_CHAR and GRIPDB_CHAR.config then
      GRIPDB_CHAR.config._onboardingDismissed = true
    end
    ob:Hide()
    GRIP:UpdateUI()
  end)
  dismiss:SetPoint("BOTTOM", ob, "BOTTOM", 0, 16)
  W.AddButtonAccent(dismiss, 1, 0.82, 0)
  home._onboarding = ob
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
      home._initHint:SetText(L["Initializing… (database not ready yet)"])
      home._initHint:Show()
    end

    home.status:SetText("…")

    W.SetEnabledSafe(home.btnScan, false)
    W.SetEnabledSafe(home.btnWhisperInvite, false)
    W.SetEnabledSafe(home.btnPostNext, false)
    W.SetEnabledSafe(home.btnClear, false)

    if home.ghostStrip then home.ghostStrip:Hide() end

    if home.potEmpty then
      home.potEmpty:SetText(L["Initializing…"])
      home.potEmpty:Show()
    end
    if home.potEmptyIcon then home.potEmptyIcon:Hide() end
    if home.potScrollBox then
      home.potScrollBox:SetDataProvider(CreateDataProvider())
    end

    if home.blFrame and home.blFrame.header and home.blFrame.header.title then
      home.blFrame.header.title:SetText(L["Blacklist"])
    end
    if home.blFrame and home.blFrame.empty then
      home.blFrame.empty:Show()
    end
    if home.blFrame and home.blFrame.scrollBox then
      home.blFrame.scrollBox:SetDataProvider(CreateDataProvider())
    end

    return
  end

  if home._initHint then home._initHint:Hide() end

  self:EnsureOnboarding(home)
  if home._onboarding and home._onboarding:IsShown() then
    if home.potEmpty then home.potEmpty:Hide() end
    if home.potEmptyIcon then home.potEmptyIcon:Hide() end
  end

  local ghostLocked = GRIP.Ghost and GRIP.Ghost.IsSessionLocked and GRIP.Ghost:IsSessionLocked()
  W.SetEnabledSafe(home.btnScan, not ghostLocked)
  W.SetEnabledSafe(home.btnWhisperInvite, not ghostLocked)
  W.SetEnabledSafe(home.btnPostNext, not ghostLocked)
  W.SetEnabledSafe(home.btnClear, not ghostLocked)

  local pot = self:Count(GRIPDB_CHAR.potential)
  local blPerm = self:Count(GRIPDB.blacklistPerm)
  local blTemp = self:Count(GRIPDB.blacklist)

  local whoPos = max(0, ((state.whoIndex or 0) - 1))
  local whoTotal = #state.whoQueue
  local wq = #state.whisperQueue
  local pq = #state.postQueue
  local whisperOn = state.whisperTicker and L["ON"] or L["OFF"]
  local whoPending = state.pendingWho and L[" (waiting…)"] or ""

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
    (L["Potential: |cffffffff%d|r   |   BL: |cff888888perm %d|r  %stemp %d|r\nWho: %d/%d%s   |   Whisper: %d (%s)   |   Post: %d%s"]):format(
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
    hintText = L["Click Scan or press your Scan keybind to find unguilded players"]
  elseif wq > 0 and not state.whisperTicker then
    hintText = (L["Whisper queue has %d candidates — click Whisper+Invite to start"]):format(wq)
  elseif blTemp > 20 then
    local days = tonumber(GRIPDB_CHAR and GRIPDB_CHAR.config and GRIPDB_CHAR.config.blacklistDays) or 14
    hintText = (L["%d temp-blacklisted players will expire in ~%d days"]):format(blTemp, days)
  else
    hintText = L["Tip: /grip help  ·  Right-click rows for options"]
  end
  if hintText then
    home.hint:SetText(hintText)
    home.hint:Show()
  else
    home.hint:SetText("")
    home.hint:Hide()
  end

  if home.blFrame and home.blFrame.header and home.blFrame.header.title then
    home.blFrame.header.title:SetText((L["Blacklist (perm %d; temp %d)"]):format(blPerm or 0, blTemp or 0))
  end

  local scanLeft = GRIP:SecondsLeft(f._scanCooldownUntil)
  if ghostLocked then
    home.btnScan:Disable()
    home.btnScan:SetText(L["Scan"])
  elseif scanLeft > 0 then
    home.btnScan:Disable()
    home.btnScan:SetText((L["Scan (%.0fs)"]):format(ceil(scanLeft)))
  else
    home.btnScan:Enable()
    home.btnScan:SetText(L["Scan"])
  end

  local recruitLeft = GRIP:SecondsLeft(GetRecruitCooldownUntil())
  if ghostLocked or recruitLeft > 0 then
    home.btnWhisperInvite:Disable()
  else
    home.btnWhisperInvite:Enable()
  end

  local postLeft = GRIP:SecondsLeft(GetPostCooldownUntil())
  if ghostLocked or postLeft > 0 then
    home.btnPostNext:Disable()
  else
    home.btnPostNext:Enable()
  end

  self:UpdateGhostStrip()
  RefreshPotentialData(home)
  GRIP:UpdateBlacklistRows(home)
end
