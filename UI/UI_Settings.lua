-- GRIP: UI Settings Page
-- Level range, filter checklists, whisper editor with byte-budget enforcement.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, pcall, wipe = pairs, ipairs, pcall, wipe
local gsub, find, sub, rep = string.gsub, string.find, string.sub, string.rep
local tremove, tsort = table.remove, table.sort
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

-- WoW API
local UnitName = UnitName
local GetRealZoneText = GetRealZoneText

local state = GRIP.state
local W = GRIP.UIW

local MAX_WHISPER_BYTES = 255
local MAX_WHISPER_TEMPLATES = 10
local GUILDLINK_BUDGET_BYTES = 120  -- worst-case clickable link length

local PAD_L = 4
local PAD_R = 24 -- leave room from right edge inside scroll content

local function HasDB()
  return (_G.GRIPDB_CHAR and GRIPDB_CHAR.config and GRIPDB_CHAR.lists and GRIPDB_CHAR.filters) and true or false
end

local function SetAll(list, filterTbl)
  wipe(filterTbl)
  for _, v in ipairs(list or {}) do
    filterTbl[v] = true
  end
end

-- Expansion-aware budgeting for the whisper editor.
-- We budget in BYTES (Lua #), which is the safest to align with what actually gets sent.
local function EstimateWhisperRenderedBytes(rawText)
  rawText = tostring(rawText or "")

  -- Worst-case character name length is 12 (Retail naming rules: 2-12).
  local playerStub = "AAAAAAAAAAAA" -- 12 bytes

  -- Guild name is known locally (or may be temporarily empty early in login).
  -- IMPORTANT: existence check must use DOT; method call uses COLON.
  local guildName = (GRIP.GetGuildName and GRIP:GetGuildName()) or ""
  local inGuild = (guildName ~= "")

  -- {guildlink} should budget for the ACTUAL payload string that would be sent.
  -- If clickable link isn't available, budget for worst-case link length when
  -- the template uses {guildlink}, so the counter is conservative (not optimistic).
  local link = ""
  if inGuild and GRIP.GetGuildFinderLink then
    link = GRIP:GetGuildFinderLink() or ""
  end
  if GRIP:IsBlank(link) then
    if rawText:find("{guildlink}") then
      link = string.rep("X", GUILDLINK_BUDGET_BYTES)
    else
      link = inGuild and guildName or "your guild"
    end
  end

  local out = rawText
  out = out:gsub("{player}", playerStub)
  out = out:gsub("{name}", playerStub)
  -- Replace {guildlink} BEFORE {guild} — {guild} is a substring of {guildlink}.
  out = out:gsub("{guildlink}", link)
  out = out:gsub("{guild}", guildName)

  out = GRIP:SanitizeOneLine(out)
  return #out
end

local function UpdateWhisperBudgetUI(s)
  if not s then return end
  if not (s.whisperEdit and s.whisperRemaining) then return end

  local bytes = EstimateWhisperRenderedBytes(s.whisperEdit:GetText() or "")
  local remaining = MAX_WHISPER_BYTES - bytes
  if remaining < 0 then remaining = 0 end

  s.whisperRemaining:SetText(tostring(remaining))

  -- With enforcement, this should almost always be true, but keep the guard anyway.
  local ok = (bytes <= MAX_WHISPER_BYTES)
  W.SetEnabledSafe(s.whisperSave, ok)
  W.SetEnabledSafe(s.whisperPreview, ok)
end

-- Trim the RAW editor text until the EXPANDED message fits in MAX bytes.
local function EnforceWhisperBudget(s, eb)
  if not s or not eb then return end
  if not HasDB() then return end

  local txt = eb:GetText() or ""
  local bytes = EstimateWhisperRenderedBytes(txt)
  if bytes <= MAX_WHISPER_BYTES then
    UpdateWhisperBudgetUI(s)
    return
  end

  local cursor = 0
  if eb.GetCursorPosition then
    cursor = tonumber(eb:GetCursorPosition()) or 0
  end
  if cursor < 0 then cursor = 0 end
  if cursor > #txt then cursor = #txt end

  local trimmed = GRIP:TrimToBudget(txt, MAX_WHISPER_BYTES, EstimateWhisperRenderedBytes)

  W.ProgrammaticSet(eb, trimmed)
  eb._gripDirty = true

  eb:SetFocus()
  if eb.SetCursorPosition then
    local newCursor = cursor
    if newCursor > #trimmed then newCursor = #trimmed end
    eb:SetCursorPosition(newCursor)
  end

  UpdateWhisperBudgetUI(s)
end

-- ALL-OR-NOTHING token insertion:
-- If the expanded output would exceed the budget, do nothing (prevents partial token fragments).
local function TryInsertTokenAtCursorWithBudget(s, eb, token)
  if not s or not eb then return false end
  if not HasDB() then return false end

  local candidate, newCursor = W.BuildInsertedTextAtCursor(eb, token)
  if not candidate then return false end

  if EstimateWhisperRenderedBytes(candidate) > MAX_WHISPER_BYTES then
    -- No insertion. Keep focus so user can edit.
    eb:SetFocus()
    UpdateWhisperBudgetUI(s)
    return false
  end

  W.ProgrammaticSet(eb, candidate)
  eb._gripDirty = true

  eb:SetFocus()
  if eb.SetCursorPosition and newCursor then
    if newCursor < 0 then newCursor = 0 end
    if newCursor > #candidate then newCursor = #candidate end
    eb:SetCursorPosition(newCursor)
  end

  UpdateWhisperBudgetUI(s)
  return true
end

local function UpdateScrollContentHeight(settings)
  if not settings or not settings.content then return end
  local c = settings.content
  local top = W.SafeTop(c)
  if not top then return end

  local lowest = nil
  local function consider(f)
    if not f or (f.IsShown and not f:IsShown()) then return end
    local b = W.SafeBottom(f)
    if not b then return end
    if (not lowest) or (b < lowest) then lowest = b end
  end

  consider(settings.whisperRotRand)
  consider(settings.whisperRotSeq)
  consider(settings.whisperRotLbl)
  consider(settings.whisperPreview)
  consider(settings.whisperSave)
  consider(settings.whisperInsertPlayer)
  consider(settings.whisperInsertGuild)
  consider(settings.whisperAppendLink)
  consider(settings.whisperSF)
  consider(settings.whisperHdr)

  consider(settings.ghostApply)
  consider(settings.ghostMaxLbl)
  consider(settings.ghostEnabled)
  consider(settings.ghostHdr)

  consider(settings.soundCapWarning)
  consider(settings.soundScanComplete)
  consider(settings.soundInviteAccepted)
  consider(settings.soundWhisperDone)
  consider(settings.soundEnabled)
  consider(settings.soundHdr)

  consider(settings.clearFilters)
  consider(settings.classList)
  consider(settings.raceList)
  consider(settings.zoneList)
  consider(settings.filtersHelp)

  consider(settings.applyLevels)
  consider(settings.zoneOnly)
  consider(settings.stepLbl)
  consider(settings.minLbl)
  consider(settings.title)

  if not lowest then return end

  local needed = (top - lowest) + 28
  if needed < 520 then needed = 520 end
  c:SetHeight(needed)
end

-- Template navigation helpers for multi-template whisper editor
local function UpdateRotationHighlight(s)
  if not s or not HasDB() then return end
  local mode = GRIPDB_CHAR.config.whisperRotation or "sequential"
  if s.whisperRotSeq then s.whisperRotSeq:SetAlpha(mode == "sequential" and 1.0 or 0.5) end
  if s.whisperRotRand then s.whisperRotRand:SetAlpha(mode == "random" and 1.0 or 0.5) end
end

local function UpdateWhisperNavText(s)
  if not s then return end
  local total = s._whisperDrafts and #s._whisperDrafts or 0
  local idx = s._whisperIdx or 1
  if s.whisperNav then
    s.whisperNav:SetText(("Message %d/%d"):format(idx, total))
  end
  W.SetEnabledSafe(s.whisperPrev, idx > 1)
  W.SetEnabledSafe(s.whisperNext, idx < total)
  W.SetEnabledSafe(s.whisperRemove, total > 1)
  W.SetEnabledSafe(s.whisperAdd, total < MAX_WHISPER_TEMPLATES)
end

local function ShowWhisperTemplate(s, idx)
  if not s or not s._whisperDrafts then return end
  idx = idx or s._whisperIdx or 1
  if idx < 1 then idx = 1 end
  if idx > #s._whisperDrafts then idx = #s._whisperDrafts end
  s._whisperIdx = idx
  W.ProgrammaticSet(s.whisperEdit, s._whisperDrafts[idx] or "")
  s.whisperEdit._gripDirty = false
  UpdateWhisperNavText(s)
  UpdateWhisperBudgetUI(s)
end

local function SaveCurrentDraft(s)
  if not s or not s._whisperDrafts or not s._whisperIdx then return end
  if s.whisperEdit then
    s._whisperDrafts[s._whisperIdx] = s.whisperEdit:GetText() or ""
  end
end

local function LoadWhisperDrafts(s)
  if not HasDB() then return end
  local msgs = GRIPDB_CHAR.config.whisperMessages
  s._whisperDrafts = {}
  if type(msgs) == "table" and #msgs > 0 then
    for i = 1, #msgs do
      s._whisperDrafts[i] = msgs[i] or ""
    end
  else
    s._whisperDrafts = { GRIPDB_CHAR.config.whisperMessage or "" }
  end
  s._whisperIdx = 1
end

-- -----------------------------
-- Responsive layout (called by UI.lua on resize; safe to call anytime)
-- -----------------------------
function GRIP:UI_LayoutSettings()
  if not state.ui or not state.ui.settings then return end
  local settings = state.ui.settings
  if not (settings.content and settings.scroll) then return end

  local pageW = (settings.GetWidth and settings:GetWidth()) or 0
  local pageH = (settings.GetHeight and settings:GetHeight()) or 0
  if pageW <= 0 or pageH <= 0 then return end

  local scrollW = (settings.scroll.GetWidth and settings.scroll:GetWidth()) or pageW

  -- Estimate usable content width inside the scrollframe.
  -- Keep extra safety for scrollbar + template chrome.
  local innerW = scrollW - 34
  if innerW < 260 then innerW = 260 end

  local GAP = 12
  local MIN_COL = 240
  local colW = math.floor((innerW - GAP) / 2)
  if colW < MIN_COL then colW = MIN_COL end

  local narrowCols = innerW < (MIN_COL * 2 + GAP + 10)
  local narrowTopRow = pageW < 520
  local narrowWhisperBtns = innerW < 430

  -- Top "Apply + Rebuild" reflow if narrow.
  if settings.applyLevels then
    settings.applyLevels:ClearAllPoints()
    if narrowTopRow then
      settings.applyLevels:SetPoint("TOPLEFT", settings.minLbl, "BOTTOMLEFT", 0, -8)
    else
      settings.applyLevels:SetPoint("LEFT", settings.stepEdit, "RIGHT", 14, 0)
    end
  end

  -- Filters help anchor stays the same, but it needs to move if applyLevels moved down.
  if settings.filtersHelp then
    settings.filtersHelp:ClearAllPoints()
    local anchor = settings.zoneOnly
    if narrowTopRow and settings.applyLevels then
      -- If apply moved down, zoneOnly is still below the level row; keep filtersHelp below zoneOnly.
      anchor = settings.zoneOnly
    end
    settings.filtersHelp:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
  end

  -- Filter lists: reflow to 1 column if narrow.
  if settings.zoneList and settings.raceList and settings.classList then
    settings.zoneList:ClearAllPoints()
    settings.raceList:ClearAllPoints()
    settings.classList:ClearAllPoints()

    settings.zoneList:SetPoint("TOPLEFT", settings.filtersHelp, "BOTTOMLEFT", 0, -8)

    if narrowCols then
      settings.raceList:SetPoint("TOPLEFT", settings.zoneList, "BOTTOMLEFT", 0, -12)
      settings.classList:SetPoint("TOPLEFT", settings.raceList, "BOTTOMLEFT", 0, -12)
      if settings.clearFilters then
        settings.clearFilters:ClearAllPoints()
        settings.clearFilters:SetPoint("TOPLEFT", settings.classList, "BOTTOMLEFT", 0, -8)
      end

      if settings.zoneList.SetWidth then settings.zoneList:SetWidth(innerW) end
      if settings.raceList.SetWidth then settings.raceList:SetWidth(innerW) end
      if settings.classList.SetWidth then settings.classList:SetWidth(innerW) end
    else
      settings.raceList:SetPoint("TOPLEFT", settings.zoneList, "TOPRIGHT", GAP, 0)
      settings.classList:SetPoint("TOPLEFT", settings.zoneList, "BOTTOMLEFT", 0, -12)

      if settings.clearFilters then
        settings.clearFilters:ClearAllPoints()
        settings.clearFilters:SetPoint("TOPLEFT", settings.classList, "TOPRIGHT", GAP, -2)
      end

      if settings.zoneList.SetWidth then settings.zoneList:SetWidth(colW) end
      if settings.raceList.SetWidth then settings.raceList:SetWidth(colW) end
      if settings.classList.SetWidth then settings.classList:SetWidth(colW) end
    end
  end

  -- Whisper editor width should use the full inner width and be anchored to both edges.
  local whisperW = innerW
  if whisperW < 320 then whisperW = 320 end

  if settings.whisperSF then
    settings.whisperSF:ClearAllPoints()
    settings.whisperSF:SetPoint("TOPLEFT", settings.whisperPrev or settings.whisperHdr, "BOTTOMLEFT", 0, -6)
    settings.whisperSF:SetPoint("TOPRIGHT", settings.content, "TOPRIGHT", -PAD_R, 0)
  end

  if settings.whisperSF and settings.whisperSF.SetWidth then settings.whisperSF:SetWidth(whisperW) end
  if settings.whisperEdit and settings.whisperEdit.SetWidth then settings.whisperEdit:SetWidth(whisperW) end

  -- Whisper height: expand a bit when window is taller, but keep sane limits.
  local baseH = 60
  local extra = math.max(0, pageH - 520)
  local whisperH = baseH + math.min(140, extra)
  if whisperH < 60 then whisperH = 60 end
  if whisperH > 220 then whisperH = 220 end

  if settings.whisperSF and settings.whisperSF.SetHeight then settings.whisperSF:SetHeight(whisperH) end
  if settings.whisperEdit and settings.whisperEdit.SetHeight then settings.whisperEdit:SetHeight(whisperH) end

  -- Whisper token buttons: reflow if narrow.
  if settings.whisperAppendLink and settings.whisperInsertGuild and settings.whisperInsertPlayer then
    settings.whisperAppendLink:ClearAllPoints()
    settings.whisperInsertGuild:ClearAllPoints()
    settings.whisperInsertPlayer:ClearAllPoints()

    settings.whisperAppendLink:SetPoint("TOPLEFT", settings.whisperSF, "BOTTOMLEFT", 0, -6)

    if narrowWhisperBtns then
      settings.whisperInsertGuild:SetPoint("TOPLEFT", settings.whisperAppendLink, "BOTTOMLEFT", 0, -6)
      settings.whisperInsertPlayer:SetPoint("TOPLEFT", settings.whisperInsertGuild, "BOTTOMLEFT", 0, -6)
    else
      settings.whisperInsertGuild:SetPoint("LEFT", settings.whisperAppendLink, "RIGHT", 8, 0)
      settings.whisperInsertPlayer:SetPoint("LEFT", settings.whisperInsertGuild, "RIGHT", 8, 0)
    end
  end

  if settings.whisperSave and settings.whisperPreview then
    settings.whisperSave:ClearAllPoints()
    settings.whisperPreview:ClearAllPoints()

    -- Place Save row under the last token button row.
    local anchor = settings.whisperAppendLink
    if narrowWhisperBtns then
      anchor = settings.whisperInsertPlayer
    end

    settings.whisperSave:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    settings.whisperPreview:SetPoint("LEFT", settings.whisperSave, "RIGHT", 8, 0)
  end

  if settings.whisperRotLbl and settings.whisperRotSeq and settings.whisperRotRand then
    settings.whisperRotLbl:ClearAllPoints()
    settings.whisperRotSeq:ClearAllPoints()
    settings.whisperRotRand:ClearAllPoints()
    settings.whisperRotLbl:SetPoint("LEFT", settings.whisperPreview, "RIGHT", 16, 0)
    settings.whisperRotSeq:SetPoint("LEFT", settings.whisperRotLbl, "RIGHT", 4, 0)
    settings.whisperRotRand:SetPoint("LEFT", settings.whisperRotSeq, "RIGHT", 4, 0)
  end

  UpdateScrollContentHeight(settings)
end

function GRIP:UI_CreateSettings(parent)
  local settings = CreateFrame("Frame", nil, parent)
  settings:SetAllPoints(true)

  settings.scroll, settings.content = W.CreateScrollPage(settings)
  local s = settings.content

  settings.title = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  settings.title:SetPoint("TOPLEFT", s, "TOPLEFT", 4, -2)
  settings.title:SetText("Settings")

  settings.levelLabel = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  settings.levelLabel:SetPoint("TOPLEFT", s, "TOPLEFT", 4, -24)
  settings.levelLabel:SetText("Scan Levels (min / max / step)")

  settings.minLbl, settings.minEdit = W.CreateLabeledEdit(s, "Min", 60)
  settings.minLbl:SetPoint("TOPLEFT", s, "TOPLEFT", 4, -44)
  settings.minEdit:SetPoint("LEFT", settings.minLbl, "RIGHT", 8, 0)

  settings.maxLbl, settings.maxEdit = W.CreateLabeledEdit(s, "Max", 60)
  settings.maxLbl:SetPoint("LEFT", settings.minEdit, "RIGHT", 16, 0)
  settings.maxEdit:SetPoint("LEFT", settings.maxLbl, "RIGHT", 8, 0)

  settings.stepLbl, settings.stepEdit = W.CreateLabeledEdit(s, "Step", 60)
  settings.stepLbl:SetPoint("LEFT", settings.maxEdit, "RIGHT", 16, 0)
  settings.stepEdit:SetPoint("LEFT", settings.stepLbl, "RIGHT", 8, 0)

  settings.zoneOnly = W.CreateCheckbox(s, "Include current zone in /who query", function(btn)
    if not HasDB() then
      GRIP:Print("Settings unavailable yet (DB not initialized).")
      btn:SetChecked(false)
      return
    end

    GRIPDB_CHAR.config.scanZoneOnly = btn:GetChecked() and true or false
    GRIP:Print("scanZoneOnly: " .. (GRIPDB_CHAR.config.scanZoneOnly and "ON" or "OFF"))
    GRIP:BuildWhoQueue()
    GRIP:UpdateUI()
  end)
  settings.zoneOnly:SetPoint("TOPLEFT", settings.minLbl, "BOTTOMLEFT", 0, -10)

  settings.applyLevels = W.CreateUIButton(s, "Apply + Rebuild", 120, 22, function()
    if not HasDB() then
      GRIP:Print("Settings unavailable yet (DB not initialized).")
      return
    end

    settings.minEdit:ClearFocus()
    settings.maxEdit:ClearFocus()
    settings.stepEdit:ClearFocus()

    local a1 = tonumber(settings.minEdit:GetText())
    local b1 = tonumber(settings.maxEdit:GetText())
    local c1 = tonumber(settings.stepEdit:GetText())
    if not (a1 and b1 and c1) then
      GRIP:Print("Levels must be numbers.")
      return
    end

    GRIPDB_CHAR.config.scanMinLevel = GRIP:Clamp(a1, 1, 100)
    GRIPDB_CHAR.config.scanMaxLevel = GRIP:Clamp(b1, GRIPDB_CHAR.config.scanMinLevel, 100)
    GRIPDB_CHAR.config.scanStep = GRIP:Clamp(c1, 1, 20)

    W.ClearDirty(settings.minEdit, settings.maxEdit, settings.stepEdit)

    GRIP:BuildWhoQueue()
    GRIP:Print(("Scan levels set: %d-%d step %d"):format(GRIPDB_CHAR.config.scanMinLevel, GRIPDB_CHAR.config.scanMaxLevel, GRIPDB_CHAR.config.scanStep))
    GRIP:UpdateUI()
  end)
  settings.applyLevels:SetPoint("LEFT", settings.stepEdit, "RIGHT", 14, 0)

  settings.filtersHelp = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  settings.filtersHelp:SetPoint("TOPLEFT", settings.zoneOnly, "BOTTOMLEFT", 0, -8)
  settings.filtersHelp:SetText("Filters are allowlists. If nothing is checked in a category, that category allows ALL.")

  settings.zoneList = W.CreateGroupedChecklist(s, "Zones", 250, 200)
  settings.zoneList:SetPoint("TOPLEFT", settings.filtersHelp, "BOTTOMLEFT", 0, -8)

  settings.raceList = W.CreateChecklist(s, "Races", 250, 140)
  settings.raceList:SetPoint("TOPLEFT", settings.zoneList, "TOPRIGHT", 12, 0)

  settings.classList = W.CreateChecklist(s, "Classes", 250, 140)
  settings.classList:SetPoint("TOPLEFT", settings.zoneList, "BOTTOMLEFT", 0, -12)

  settings.zoneAll = W.CreateUIButton(s, "All", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB_CHAR.filters.zones)
    local groups = GRIP:GetZonesGroupedForUI()
    for _, g in ipairs(groups) do
      for _, z in ipairs(g.zones) do
        GRIPDB_CHAR.filters.zones[z] = true
      end
    end
    GRIP:UpdateUI()
  end)
  settings.zoneAll:SetPoint("TOPRIGHT", settings.zoneList, "TOPRIGHT", -52, -4)

  settings.zoneNone = W.CreateUIButton(s, "None", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB_CHAR.filters.zones); GRIP:UpdateUI()
  end)
  settings.zoneNone:SetPoint("LEFT", settings.zoneAll, "RIGHT", 4, 0)

  settings.zoneCurrent = W.CreateUIButton(s, "Current", 56, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    local zoneName = GetRealZoneText and GetRealZoneText() or ""
    if zoneName == "" then
      GRIP:Print("Could not determine current zone.")
      return
    end
    -- Find this zone in any expansion group and select it
    local found = false
    local groups = GRIP:GetZonesGroupedForUI()
    if groups then
      for _, g in ipairs(groups) do
        for _, z in ipairs(g.zones) do
          if z == zoneName then
            GRIPDB_CHAR.filters.zones[z] = true
            found = true
            break
          end
        end
        if found then break end
      end
    end
    if found then
      GRIP:Debug("Zone filter: added current zone", zoneName)
    else
      GRIP:Print(("Zone \"%s\" not found in zone lists."):format(zoneName))
    end
    GRIP:UpdateUI()
  end)
  settings.zoneCurrent:SetPoint("TOPRIGHT", settings.zoneAll, "TOPLEFT", -4, 0)

  settings.raceAll = W.CreateUIButton(s, "All", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    SetAll(GRIPDB_CHAR.lists.races, GRIPDB_CHAR.filters.races); GRIP:UpdateUI()
  end)
  settings.raceAll:SetPoint("TOPRIGHT", settings.raceList, "TOPRIGHT", -52, -4)

  settings.raceNone = W.CreateUIButton(s, "None", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB_CHAR.filters.races); GRIP:UpdateUI()
  end)
  settings.raceNone:SetPoint("LEFT", settings.raceAll, "RIGHT", 4, 0)

  settings.classAll = W.CreateUIButton(s, "All", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    SetAll(GRIPDB_CHAR.lists.classes, GRIPDB_CHAR.filters.classes); GRIP:UpdateUI()
  end)
  settings.classAll:SetPoint("TOPRIGHT", settings.classList, "TOPRIGHT", -52, -4)

  settings.classNone = W.CreateUIButton(s, "None", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB_CHAR.filters.classes); GRIP:UpdateUI()
  end)
  settings.classNone:SetPoint("LEFT", settings.classAll, "RIGHT", 4, 0)

  settings.clearFilters = W.CreateUIButton(s, "Clear Selections", 120, 22, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB_CHAR.filters.zones)
    wipe(GRIPDB_CHAR.filters.races)
    wipe(GRIPDB_CHAR.filters.classes)
    GRIP:Print("Cleared filter selections.")
    GRIP:UpdateUI()
  end)
  settings.clearFilters:SetPoint("TOPLEFT", settings.classList, "TOPRIGHT", 12, -2)

  settings.whisperHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  settings.whisperHdr:SetPoint("TOPLEFT", settings.classList, "BOTTOMLEFT", 0, -12)
  settings.whisperHdr:SetText("Whisper Templates (supports {player} {guild} {guildlink})")

  -- Template navigation bar
  settings.whisperPrev = W.CreateUIButton(s, "Prev", 40, 20, function()
    if not HasDB() then return end
    SaveCurrentDraft(settings)
    ShowWhisperTemplate(settings, (settings._whisperIdx or 1) - 1)
  end)
  settings.whisperPrev:SetPoint("TOPLEFT", settings.whisperHdr, "BOTTOMLEFT", 0, -6)

  settings.whisperNav = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  settings.whisperNav:SetPoint("LEFT", settings.whisperPrev, "RIGHT", 6, 0)
  settings.whisperNav:SetText("Message 1/1")

  settings.whisperNext = W.CreateUIButton(s, "Next", 40, 20, function()
    if not HasDB() then return end
    SaveCurrentDraft(settings)
    ShowWhisperTemplate(settings, (settings._whisperIdx or 1) + 1)
  end)
  settings.whisperNext:SetPoint("LEFT", settings.whisperNav, "RIGHT", 6, 0)

  settings.whisperAdd = W.CreateUIButton(s, "+ Add", 50, 20, function()
    if not HasDB() then return end
    settings._whisperDrafts = settings._whisperDrafts or { "" }
    if #settings._whisperDrafts >= MAX_WHISPER_TEMPLATES then
      GRIP:Print(("Max %d templates."):format(MAX_WHISPER_TEMPLATES))
      return
    end
    SaveCurrentDraft(settings)
    settings._whisperDrafts[#settings._whisperDrafts + 1] = ""
    ShowWhisperTemplate(settings, #settings._whisperDrafts)
    settings.whisperEdit:SetFocus()
  end)
  settings.whisperAdd:SetPoint("LEFT", settings.whisperNext, "RIGHT", 12, 0)

  settings.whisperRemove = W.CreateUIButton(s, "- Remove", 64, 20, function()
    if not HasDB() then return end
    settings._whisperDrafts = settings._whisperDrafts or { "" }
    if #settings._whisperDrafts <= 1 then
      GRIP:Print("Must have at least 1 template.")
      return
    end
    local idx = settings._whisperIdx or 1
    table.remove(settings._whisperDrafts, idx)
    if idx > #settings._whisperDrafts then idx = #settings._whisperDrafts end
    ShowWhisperTemplate(settings, idx)
  end)
  settings.whisperRemove:SetPoint("LEFT", settings.whisperAdd, "RIGHT", 4, 0)

  -- Edit box (anchored to navigation bar; layout hook re-anchors + sizes it)
  settings.whisperSF, settings.whisperEdit = W.CreateMultilineEdit(s, 1, 60)
  settings.whisperSF:SetPoint("TOPLEFT", settings.whisperPrev, "BOTTOMLEFT", 0, -6)

  -- Expansion-aware "remaining" counter (bottom-right of the edit area).
  settings.whisperRemaining = settings.whisperSF:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  settings.whisperRemaining:SetPoint("BOTTOMRIGHT", settings.whisperSF, "BOTTOMRIGHT", -6, 6)
  settings.whisperRemaining:SetText("")

  -- Update budget live as the user types + enforce the budget.
  if settings.whisperEdit and settings.whisperEdit.SetScript then
    settings.whisperEdit:SetScript("OnTextChanged", function(eb, user)
      if eb._gripProgrammatic then return end
      if not HasDB() then return end

      settings.whisperEdit._gripDirty = true

      -- Keep draft buffer in sync with live edits.
      if settings._whisperDrafts and settings._whisperIdx then
        settings._whisperDrafts[settings._whisperIdx] = eb:GetText() or ""
      end

      if user then
        EnforceWhisperBudget(settings, eb)
      else
        UpdateWhisperBudgetUI(settings)
      end
    end)
  end

  settings.whisperAppendLink = W.CreateUIButton(s, "Insert {guildlink}", 140, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursorWithBudget(settings, settings.whisperEdit, "{guildlink}")
    if not ok then GRIP:Print("No room to insert {guildlink} (max 255 after expansion).") end
  end)
  settings.whisperAppendLink:SetPoint("TOPLEFT", settings.whisperSF, "BOTTOMLEFT", 0, -6)

  settings.whisperInsertGuild = W.CreateUIButton(s, "Insert {guild}", 110, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursorWithBudget(settings, settings.whisperEdit, "{guild}")
    if not ok then GRIP:Print("No room to insert {guild} (max 255 after expansion).") end
  end)
  settings.whisperInsertGuild:SetPoint("LEFT", settings.whisperAppendLink, "RIGHT", 8, 0)

  settings.whisperInsertPlayer = W.CreateUIButton(s, "Insert {player}", 120, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursorWithBudget(settings, settings.whisperEdit, "{player}")
    if not ok then GRIP:Print("No room to insert {player} (max 255 after expansion).") end
  end)
  settings.whisperInsertPlayer:SetPoint("LEFT", settings.whisperInsertGuild, "RIGHT", 8, 0)

  settings.whisperSave = W.CreateUIButton(s, "Save All", 70, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    settings.whisperEdit:ClearFocus()
    SaveCurrentDraft(settings)

    -- Validate all templates before saving.
    local drafts = settings._whisperDrafts or {}
    for i = 1, #drafts do
      if EstimateWhisperRenderedBytes(drafts[i]) > MAX_WHISPER_BYTES then
        GRIP:Print(("Template %d is too long after token expansion (max 255)."):format(i))
        ShowWhisperTemplate(settings, i)
        return
      end
    end

    GRIPDB_CHAR.config.whisperMessages = {}
    for i = 1, #drafts do
      GRIPDB_CHAR.config.whisperMessages[i] = drafts[i]
    end
    GRIPDB_CHAR.config.whisperMessage = GRIPDB_CHAR.config.whisperMessages[1] or ""
    W.ClearDirty(settings.whisperEdit)
    GRIP:Print(("Saved %d whisper template(s)."):format(#drafts))
    GRIP:UpdateUI()
  end)
  settings.whisperSave:SetPoint("TOPLEFT", settings.whisperAppendLink, "BOTTOMLEFT", 0, -6)

  settings.whisperPreview = W.CreateUIButton(s, "Preview", 80, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end

    UpdateWhisperBudgetUI(settings)
    local bytes = EstimateWhisperRenderedBytes(settings.whisperEdit:GetText() or "")
    if bytes > MAX_WHISPER_BYTES then
      GRIP:Print("Template is too long after token expansion (max 255).")
      return
    end

    local msg = GRIP:ApplyTemplate(settings.whisperEdit:GetText() or "", UnitName("player") or "")
    GRIP:Print("Preview: " .. msg)
  end)
  settings.whisperPreview:SetPoint("LEFT", settings.whisperSave, "RIGHT", 8, 0)

  -- Rotation mode selector
  settings.whisperRotLbl = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  settings.whisperRotLbl:SetPoint("LEFT", settings.whisperPreview, "RIGHT", 16, 0)
  settings.whisperRotLbl:SetText("Rotation:")

  settings.whisperRotSeq = W.CreateUIButton(s, "Sequential", 80, 20, function()
    if not HasDB() then return end
    GRIPDB_CHAR.config.whisperRotation = "sequential"
    UpdateRotationHighlight(settings)
  end)
  settings.whisperRotSeq:SetPoint("LEFT", settings.whisperRotLbl, "RIGHT", 4, 0)

  settings.whisperRotRand = W.CreateUIButton(s, "Random", 60, 20, function()
    if not HasDB() then return end
    GRIPDB_CHAR.config.whisperRotation = "random"
    UpdateRotationHighlight(settings)
  end)
  settings.whisperRotRand:SetPoint("LEFT", settings.whisperRotSeq, "RIGHT", 4, 0)

  -- Sound Feedback section
  settings.soundHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  settings.soundHdr:SetPoint("TOPLEFT", settings.whisperSave, "BOTTOMLEFT", 0, -16)
  settings.soundHdr:SetText("Sound Feedback")

  settings.soundEnabled = W.CreateCheckbox(s, "Enable sound feedback", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundEnabled = btn:GetChecked() and true or false
    GRIP:UpdateUI()
  end)
  settings.soundEnabled:SetPoint("TOPLEFT", settings.soundHdr, "BOTTOMLEFT", 0, -4)

  settings.soundWhisperDone = W.CreateCheckbox(s, "Whisper queue complete", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundWhisperDone = btn:GetChecked() and true or false
  end)
  settings.soundWhisperDone:SetPoint("TOPLEFT", settings.soundEnabled, "BOTTOMLEFT", 16, -2)

  settings.soundInviteAccepted = W.CreateCheckbox(s, "Invite accepted", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundInviteAccepted = btn:GetChecked() and true or false
  end)
  settings.soundInviteAccepted:SetPoint("TOPLEFT", settings.soundWhisperDone, "BOTTOMLEFT", 0, -2)

  settings.soundScanComplete = W.CreateCheckbox(s, "Scan results found", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundScanComplete = btn:GetChecked() and true or false
  end)
  settings.soundScanComplete:SetPoint("TOPLEFT", settings.soundInviteAccepted, "BOTTOMLEFT", 0, -2)

  settings.soundCapWarning = W.CreateCheckbox(s, "Daily cap warning", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundCapWarning = btn:GetChecked() and true or false
  end)
  settings.soundCapWarning:SetPoint("TOPLEFT", settings.soundScanComplete, "BOTTOMLEFT", 0, -2)

  -- Ghost Mode section
  settings.ghostHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  settings.ghostHdr:SetPoint("TOPLEFT", settings.soundCapWarning, "BOTTOMLEFT", -16, -16)
  settings.ghostHdr:SetText("Ghost Mode (Experimental)")

  settings.ghostEnabled = W.CreateCheckbox(s, "Enable Ghost Mode", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.ghostModeEnabled = btn:GetChecked() and true or false
    GRIP:UpdateUI()
  end)
  settings.ghostEnabled:SetPoint("TOPLEFT", settings.ghostHdr, "BOTTOMLEFT", 0, -4)

  settings.ghostMaxLbl, settings.ghostMaxEdit = W.CreateLabeledEdit(s, "Session max (min)", 50)
  settings.ghostMaxLbl:SetPoint("TOPLEFT", settings.ghostEnabled, "BOTTOMLEFT", 16, -6)
  settings.ghostMaxEdit:SetPoint("LEFT", settings.ghostMaxLbl, "RIGHT", 8, 0)

  settings.ghostCoolLbl, settings.ghostCoolEdit = W.CreateLabeledEdit(s, "Cooldown (min)", 50)
  settings.ghostCoolLbl:SetPoint("LEFT", settings.ghostMaxEdit, "RIGHT", 16, 0)
  settings.ghostCoolEdit:SetPoint("LEFT", settings.ghostCoolLbl, "RIGHT", 8, 0)

  settings.ghostApply = W.CreateUIButton(s, "Apply", 60, 22, function()
    if not HasDB() then return end
    settings.ghostMaxEdit:ClearFocus()
    settings.ghostCoolEdit:ClearFocus()
    local maxV = tonumber(settings.ghostMaxEdit:GetText())
    local coolV = tonumber(settings.ghostCoolEdit:GetText())
    if maxV then
      GRIPDB_CHAR.config.ghostSessionMaxMinutes = GRIP:Clamp(maxV, 5, 120)
    end
    if coolV then
      GRIPDB_CHAR.config.ghostCooldownMinutes = GRIP:Clamp(coolV, 1, 60)
    end
    W.ClearDirty(settings.ghostMaxEdit, settings.ghostCoolEdit)
    GRIP:Print(("Ghost Mode: session max %d min, cooldown %d min"):format(
      GRIPDB_CHAR.config.ghostSessionMaxMinutes, GRIPDB_CHAR.config.ghostCooldownMinutes))
    GRIP:UpdateUI()
  end)
  settings.ghostApply:SetPoint("LEFT", settings.ghostCoolEdit, "RIGHT", 12, 0)

  -- Initial layout pass (UI.lua will also call this on resize).
  pcall(function() GRIP:UI_LayoutSettings() end)

  return settings
end

function GRIP:UI_UpdateSettings()
  if not state.ui or not state.ui.settings or not state.ui.settings:IsShown() then return end
  local s = state.ui.settings

  if not HasDB() then
    -- Lock everything and display a gentle hint.
    if s._initHint then
      s._initHint:Show()
    else
      local parent = s.content or s
      s._initHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      s._initHint:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -4)
      s._initHint:SetText("Initializing… (database not ready yet)")
      s._initHint:Show()
    end

    W.SetEnabledSafe(s.minEdit, false)
    W.SetEnabledSafe(s.maxEdit, false)
    W.SetEnabledSafe(s.stepEdit, false)
    W.SetEnabledSafe(s.zoneOnly, false)
    W.SetEnabledSafe(s.applyLevels, false)

    W.SetEnabledSafe(s.zoneAll, false)
    W.SetEnabledSafe(s.zoneNone, false)
    W.SetEnabledSafe(s.zoneCurrent, false)
    W.SetEnabledSafe(s.raceAll, false)
    W.SetEnabledSafe(s.raceNone, false)
    W.SetEnabledSafe(s.classAll, false)
    W.SetEnabledSafe(s.classNone, false)
    W.SetEnabledSafe(s.clearFilters, false)

    W.SetEnabledSafe(s.whisperEdit, false)
    W.SetEnabledSafe(s.whisperAppendLink, false)
    W.SetEnabledSafe(s.whisperInsertGuild, false)
    W.SetEnabledSafe(s.whisperInsertPlayer, false)
    W.SetEnabledSafe(s.whisperSave, false)
    W.SetEnabledSafe(s.whisperPreview, false)
    W.SetEnabledSafe(s.whisperPrev, false)
    W.SetEnabledSafe(s.whisperNext, false)
    W.SetEnabledSafe(s.whisperAdd, false)
    W.SetEnabledSafe(s.whisperRemove, false)
    W.SetEnabledSafe(s.whisperRotSeq, false)
    W.SetEnabledSafe(s.whisperRotRand, false)

    W.SetEnabledSafe(s.soundEnabled, false)
    W.SetEnabledSafe(s.soundWhisperDone, false)
    W.SetEnabledSafe(s.soundInviteAccepted, false)
    W.SetEnabledSafe(s.soundScanComplete, false)
    W.SetEnabledSafe(s.soundCapWarning, false)

    W.SetEnabledSafe(s.ghostEnabled, false)
    W.SetEnabledSafe(s.ghostMaxEdit, false)
    W.SetEnabledSafe(s.ghostCoolEdit, false)
    W.SetEnabledSafe(s.ghostApply, false)

    if s.whisperRemaining then s.whisperRemaining:SetText("") end
    pcall(function() GRIP:UI_LayoutSettings() end)
    return
  end

  if s._initHint then s._initHint:Hide() end

  -- Re-enable controls now that DB exists.
  W.SetEnabledSafe(s.minEdit, true)
  W.SetEnabledSafe(s.maxEdit, true)
  W.SetEnabledSafe(s.stepEdit, true)
  W.SetEnabledSafe(s.zoneOnly, true)
  W.SetEnabledSafe(s.applyLevels, true)

  W.SetEnabledSafe(s.zoneAll, true)
  W.SetEnabledSafe(s.zoneNone, true)
  W.SetEnabledSafe(s.zoneCurrent, true)
  W.SetEnabledSafe(s.raceAll, true)
  W.SetEnabledSafe(s.raceNone, true)
  W.SetEnabledSafe(s.classAll, true)
  W.SetEnabledSafe(s.classNone, true)
  W.SetEnabledSafe(s.clearFilters, true)

  W.SetEnabledSafe(s.whisperEdit, true)
  W.SetEnabledSafe(s.whisperAppendLink, true)
  W.SetEnabledSafe(s.whisperInsertGuild, true)
  W.SetEnabledSafe(s.whisperInsertPlayer, true)
  W.SetEnabledSafe(s.whisperAdd, true)
  W.SetEnabledSafe(s.whisperRotSeq, true)
  W.SetEnabledSafe(s.whisperRotRand, true)

  W.SetTextIfUnfocused(s.minEdit, tostring(GRIPDB_CHAR.config.scanMinLevel or 1))
  W.SetTextIfUnfocused(s.maxEdit, tostring(GRIPDB_CHAR.config.scanMaxLevel or 90))
  W.SetTextIfUnfocused(s.stepEdit, tostring(GRIPDB_CHAR.config.scanStep or 5))
  s.zoneOnly:SetChecked(GRIPDB_CHAR.config.scanZoneOnly and true or false)

  s.zoneList:Render(GRIP:GetZonesGroupedForUI(), GRIPDB_CHAR.filters.zones)
  s.raceList:Render(GRIPDB_CHAR.lists.races, GRIPDB_CHAR.filters.races)
  s.classList:Render(GRIPDB_CHAR.lists.classes, GRIPDB_CHAR.filters.classes)

  -- Multi-template: reload drafts when edit box isn't actively being used.
  if not s.whisperEdit:HasFocus() and not s.whisperEdit._gripDirty then
    LoadWhisperDrafts(s)
    ShowWhisperTemplate(s, s._whisperIdx or 1)
  else
    UpdateWhisperNavText(s)
  end
  UpdateRotationHighlight(s)
  EnforceWhisperBudget(s, s.whisperEdit)

  -- Sound checkboxes
  local soundOn = GRIPDB_CHAR.config.soundEnabled and true or false
  W.SetEnabledSafe(s.soundEnabled, true)
  s.soundEnabled:SetChecked(soundOn)
  W.SetEnabledSafe(s.soundWhisperDone, soundOn)
  W.SetEnabledSafe(s.soundInviteAccepted, soundOn)
  W.SetEnabledSafe(s.soundScanComplete, soundOn)
  W.SetEnabledSafe(s.soundCapWarning, soundOn)
  s.soundWhisperDone:SetChecked(GRIPDB_CHAR.config.soundWhisperDone and true or false)
  s.soundInviteAccepted:SetChecked(GRIPDB_CHAR.config.soundInviteAccepted and true or false)
  s.soundScanComplete:SetChecked(GRIPDB_CHAR.config.soundScanComplete and true or false)
  s.soundCapWarning:SetChecked(GRIPDB_CHAR.config.soundCapWarning and true or false)

  -- Ghost Mode
  local ghostOn = GRIPDB_CHAR.config.ghostModeEnabled and true or false
  W.SetEnabledSafe(s.ghostEnabled, true)
  s.ghostEnabled:SetChecked(ghostOn)
  W.SetEnabledSafe(s.ghostMaxEdit, ghostOn)
  W.SetEnabledSafe(s.ghostCoolEdit, ghostOn)
  W.SetEnabledSafe(s.ghostApply, ghostOn)
  W.SetTextIfUnfocused(s.ghostMaxEdit, tostring(GRIPDB_CHAR.config.ghostSessionMaxMinutes or 60))
  W.SetTextIfUnfocused(s.ghostCoolEdit, tostring(GRIPDB_CHAR.config.ghostCooldownMinutes or 10))

  -- Keep layout responsive (UI.lua calls it too, but this makes Settings robust if called directly).
  pcall(function() GRIP:UI_LayoutSettings() end)
end