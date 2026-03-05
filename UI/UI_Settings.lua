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

local function ToggleOptOutLanguage(lang, checked)
  if not _G.GRIPDB_CHAR then return end
  local cfg = GRIPDB_CHAR.config
  local langs = cfg.optOutLanguages or {"en"}
  if checked then
    local found = false
    for _, l in ipairs(langs) do
      if l == lang then found = true; break end
    end
    if not found then
      langs[#langs + 1] = lang
    end
  else
    for i = #langs, 1, -1 do
      if langs[i] == lang then
        table.remove(langs, i)
      end
    end
  end
  -- Ensure "en" is always present
  local hasEN = false
  for _, l in ipairs(langs) do
    if l == "en" then hasEN = true; break end
  end
  if not hasEN then
    table.insert(langs, 1, "en")
  end
  cfg.optOutLanguages = langs
  GRIP:RebuildOptOutPhrases()
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

  consider(settings.hideWhisperEcho)
  consider(settings.inviteFirst)
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

  consider(settings.ghostCooldownSlider)
  consider(settings.ghostSessionSlider)
  consider(settings.ghostEnabled)
  consider(settings.ghostHdr)

  consider(settings.optOutAggressive)
  consider(settings.optOutES)
  consider(settings.optOutDE)
  consider(settings.optOutFR)
  consider(settings.optOutEN)
  consider(settings.optOutHdr)

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
      anchor = settings.zoneOnly
    end
    if settings.sep1 then
      settings.sep1:ClearAllPoints()
      settings.sep1:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
      settings.sep1:SetPoint("RIGHT", settings.content, "RIGHT", -PAD_R, 0)
    end
    settings.filtersHelp:SetPoint("TOPLEFT", settings.sep1 or anchor, "BOTTOMLEFT", 0, -6)
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

    GRIPDB_CHAR.config.scanMinLevel = GRIP:Clamp(a1, GRIP.MIN_SCAN_LEVEL, GRIP.MAX_SCAN_LEVEL)
    GRIPDB_CHAR.config.scanMaxLevel = GRIP:Clamp(b1, GRIPDB_CHAR.config.scanMinLevel, GRIP.MAX_SCAN_LEVEL)
    GRIPDB_CHAR.config.scanStep = GRIP:Clamp(c1, 1, 20)

    W.ClearDirty(settings.minEdit, settings.maxEdit, settings.stepEdit)

    GRIP:BuildWhoQueue()
    GRIP:Print(("Scan levels set: %d-%d step %d"):format(GRIPDB_CHAR.config.scanMinLevel, GRIPDB_CHAR.config.scanMaxLevel, GRIPDB_CHAR.config.scanStep))
    GRIP:UpdateUI()
  end)
  settings.applyLevels:SetPoint("LEFT", settings.stepEdit, "RIGHT", 14, 0)

  GRIP:AttachTooltip(settings.zoneOnly, "Zone Only", "When checked, appends your current zone name to every\n/who query. Narrows results to your zone only.")
  GRIP:AttachTooltip(settings.applyLevels, "Apply + Rebuild", "Applies level range + step and rebuilds the /who scan queue.")

  -- Separator: level/zone controls → filter checklists
  settings.sep1 = s:CreateTexture(nil, "ARTWORK")
  settings.sep1:SetHeight(1)
  settings.sep1:SetPoint("TOPLEFT", settings.zoneOnly, "BOTTOMLEFT", 0, -6)
  settings.sep1:SetPoint("RIGHT", s, "RIGHT", -PAD_R, 0)
  settings.sep1:SetColorTexture(1, 1, 1, 0.08)

  settings.filtersHelp = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  settings.filtersHelp:SetPoint("TOPLEFT", settings.sep1, "BOTTOMLEFT", 0, -6)
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
  GRIP:AttachTooltip(settings.zoneAll, "Select All Zones", "Select all zones in every expansion group.")

  settings.zoneNone = W.CreateUIButton(s, "None", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB_CHAR.filters.zones); GRIP:UpdateUI()
  end)
  settings.zoneNone:SetPoint("LEFT", settings.zoneAll, "RIGHT", 4, 0)
  GRIP:AttachTooltip(settings.zoneNone, "Deselect All Zones", "Deselect all zones (allows all zones when empty).")

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
  GRIP:AttachTooltip(settings.zoneCurrent, "Current Zone", "Add your current zone to the selection.")

  settings.raceAll = W.CreateUIButton(s, "All", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    SetAll(GRIPDB_CHAR.lists.races, GRIPDB_CHAR.filters.races); GRIP:UpdateUI()
  end)
  settings.raceAll:SetPoint("TOPRIGHT", settings.raceList, "TOPRIGHT", -52, -4)
  GRIP:AttachTooltip(settings.raceAll, "Select All Races", "Select all races.")

  settings.raceNone = W.CreateUIButton(s, "None", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB_CHAR.filters.races); GRIP:UpdateUI()
  end)
  settings.raceNone:SetPoint("LEFT", settings.raceAll, "RIGHT", 4, 0)
  GRIP:AttachTooltip(settings.raceNone, "Deselect All Races", "Deselect all races (allows all races when empty).")

  settings.classAll = W.CreateUIButton(s, "All", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    SetAll(GRIPDB_CHAR.lists.classes, GRIPDB_CHAR.filters.classes); GRIP:UpdateUI()
  end)
  settings.classAll:SetPoint("TOPRIGHT", settings.classList, "TOPRIGHT", -52, -4)
  GRIP:AttachTooltip(settings.classAll, "Select All Classes", "Select all classes.")

  settings.classNone = W.CreateUIButton(s, "None", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB_CHAR.filters.classes); GRIP:UpdateUI()
  end)
  settings.classNone:SetPoint("LEFT", settings.classAll, "RIGHT", 4, 0)
  GRIP:AttachTooltip(settings.classNone, "Deselect All Classes", "Deselect all classes (allows all classes when empty).")

  settings.clearFilters = W.CreateUIButton(s, "Clear Selections", 120, 22, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB_CHAR.filters.zones)
    wipe(GRIPDB_CHAR.filters.races)
    wipe(GRIPDB_CHAR.filters.classes)
    GRIP:Print("Cleared filter selections.")
    GRIP:UpdateUI()
  end)
  settings.clearFilters:SetPoint("TOPLEFT", settings.classList, "TOPRIGHT", 12, -2)
  GRIP:AttachTooltip(settings.clearFilters, "Clear Selections", "Deselect all zones, races, and classes.\nEmpty filters = allow all.")
  do local fs = settings.clearFilters:GetFontString(); if fs then fs:SetTextColor(unpack(GRIP.COLORS.DANGER_RED)) end end

  -- Separator: filter checklists → whisper templates
  settings.sep2 = s:CreateTexture(nil, "ARTWORK")
  settings.sep2:SetHeight(1)
  settings.sep2:SetPoint("TOPLEFT", settings.classList, "BOTTOMLEFT", 0, -6)
  settings.sep2:SetPoint("RIGHT", s, "RIGHT", -PAD_R, 0)
  settings.sep2:SetColorTexture(1, 1, 1, 0.08)

  settings.whisperHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  settings.whisperHdr:SetPoint("TOPLEFT", settings.sep2, "BOTTOMLEFT", 0, -6)
  settings.whisperHdr:SetText("Whisper Templates (supports {player} {guild} {guildlink})")

  -- Template navigation bar
  settings.whisperPrev = W.CreateUIButton(s, "Prev", 40, 20, function()
    if not HasDB() then return end
    SaveCurrentDraft(settings)
    ShowWhisperTemplate(settings, (settings._whisperIdx or 1) - 1)
  end)
  settings.whisperPrev:SetPoint("TOPLEFT", settings.whisperHdr, "BOTTOMLEFT", 0, -6)
  GRIP:AttachTooltip(settings.whisperPrev, "Previous Template", "Navigate between whisper templates.")

  settings.whisperNav = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  settings.whisperNav:SetPoint("LEFT", settings.whisperPrev, "RIGHT", 6, 0)
  settings.whisperNav:SetText("Message 1/1")

  settings.whisperNext = W.CreateUIButton(s, "Next", 40, 20, function()
    if not HasDB() then return end
    SaveCurrentDraft(settings)
    ShowWhisperTemplate(settings, (settings._whisperIdx or 1) + 1)
  end)
  settings.whisperNext:SetPoint("LEFT", settings.whisperNav, "RIGHT", 6, 0)
  GRIP:AttachTooltip(settings.whisperNext, "Next Template", "Navigate between whisper templates.")

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
  GRIP:AttachTooltip(settings.whisperAdd, "Add Template", "Add a new blank whisper template (max 10).")

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
  GRIP:AttachTooltip(settings.whisperRemove, "Remove Template", "Remove the current template (min 1).")
  do local fs = settings.whisperRemove:GetFontString(); if fs then fs:SetTextColor(unpack(GRIP.COLORS.DANGER_RED)) end end

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
  GRIP:AttachTooltip(settings.whisperAppendLink, "Insert {guildlink}", "Inserts a clickable Guild Finder link at cursor.\nBudgets ~120 bytes for the link payload.")

  settings.whisperInsertGuild = W.CreateUIButton(s, "Insert {guild}", 110, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursorWithBudget(settings, settings.whisperEdit, "{guild}")
    if not ok then GRIP:Print("No room to insert {guild} (max 255 after expansion).") end
  end)
  settings.whisperInsertGuild:SetPoint("LEFT", settings.whisperAppendLink, "RIGHT", 8, 0)
  GRIP:AttachTooltip(settings.whisperInsertGuild, "Insert {guild}", "Inserts your guild name at cursor.")

  settings.whisperInsertPlayer = W.CreateUIButton(s, "Insert {player}", 120, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursorWithBudget(settings, settings.whisperEdit, "{player}")
    if not ok then GRIP:Print("No room to insert {player} (max 255 after expansion).") end
  end)
  settings.whisperInsertPlayer:SetPoint("LEFT", settings.whisperInsertGuild, "RIGHT", 8, 0)
  GRIP:AttachTooltip(settings.whisperInsertPlayer, "Insert {player}", "Inserts the target player's name at cursor.")

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
  GRIP:AttachTooltip(settings.whisperSave, "Save All", "Save all whisper templates to SavedVariables.")

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
  GRIP:AttachTooltip(settings.whisperPreview, "Preview", "Expands tokens and prints the result to chat.\nUses your name as the {player} stand-in.")

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
  GRIP:AttachTooltip(settings.whisperRotSeq, "Sequential", "Send templates in order (1, 2, 3, \xe2\x80\xa6, repeat).")

  settings.whisperRotRand = W.CreateUIButton(s, "Random", 60, 20, function()
    if not HasDB() then return end
    GRIPDB_CHAR.config.whisperRotation = "random"
    UpdateRotationHighlight(settings)
  end)
  settings.whisperRotRand:SetPoint("LEFT", settings.whisperRotSeq, "RIGHT", 4, 0)
  GRIP:AttachTooltip(settings.whisperRotRand, "Random", "Pick a random template for each whisper.")

  -- Hide outgoing whisper echoes checkbox
  settings.hideWhisperEcho = W.CreateCheckbox(s, "Hide outgoing whisper echoes", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    local v = btn:GetChecked() and true or false
    GRIPDB_CHAR.config.suppressWhisperEcho = v
    GRIPDB_CHAR.config.hideOutgoingWhispers = v
  end)
  settings.hideWhisperEcho:SetPoint("TOPLEFT", settings.whisperSave, "BOTTOMLEFT", 0, -6)
  GRIP:AttachTooltip(settings.hideWhisperEcho, "Hide Whisper Echoes", "Prevents your outgoing whisper messages from appearing\nin your chat window. Useful to reduce chat spam\nduring recruitment.")

  -- NH-11: Invite-first mode checkbox
  settings.inviteFirst = W.CreateCheckbox(s, "Invite first (safer)", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.inviteFirst = btn:GetChecked() and true or false
  end)
  settings.inviteFirst:SetPoint("TOPLEFT", settings.hideWhisperEcho, "BOTTOMLEFT", 0, -2)
  GRIP:AttachTooltip(settings.inviteFirst, "Invite First", "Send guild invite before whisper. Only whispers players\nwho successfully receive the invite.\nReduces risk of reports from players who block invites.")

  -- Separator: whisper templates → sound feedback
  settings.sep3 = s:CreateTexture(nil, "ARTWORK")
  settings.sep3:SetHeight(1)
  settings.sep3:SetPoint("TOPLEFT", settings.inviteFirst, "BOTTOMLEFT", 0, -8)
  settings.sep3:SetPoint("RIGHT", s, "RIGHT", -PAD_R, 0)
  settings.sep3:SetColorTexture(1, 1, 1, 0.08)

  -- Sound Feedback section
  settings.soundHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  settings.soundHdr:SetPoint("TOPLEFT", settings.sep3, "BOTTOMLEFT", 0, -8)
  settings.soundHdr:SetText("Sound Feedback")

  settings.soundEnabled = W.CreateCheckbox(s, "Enable sound feedback", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundEnabled = btn:GetChecked() and true or false
    GRIP:UpdateUI()
  end)
  settings.soundEnabled:SetPoint("TOPLEFT", settings.soundHdr, "BOTTOMLEFT", 0, -4)
  GRIP:AttachTooltip(settings.soundEnabled, "Sound Feedback", "Master toggle for all GRIP sound notifications.")

  settings.soundWhisperDone = W.CreateCheckbox(s, "Whisper queue complete", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundWhisperDone = btn:GetChecked() and true or false
  end)
  settings.soundWhisperDone:SetPoint("TOPLEFT", settings.soundEnabled, "BOTTOMLEFT", 16, -2)
  GRIP:AttachTooltip(settings.soundWhisperDone, "Whisper Complete", "Play a sound when the whisper queue is fully drained.")

  settings.soundInviteAccepted = W.CreateCheckbox(s, "Invite accepted", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundInviteAccepted = btn:GetChecked() and true or false
  end)
  settings.soundInviteAccepted:SetPoint("TOPLEFT", settings.soundWhisperDone, "BOTTOMLEFT", 0, -2)
  GRIP:AttachTooltip(settings.soundInviteAccepted, "Invite Accepted", "Play a sound when a guild invite is accepted.")

  settings.soundScanComplete = W.CreateCheckbox(s, "Scan results found", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundScanComplete = btn:GetChecked() and true or false
  end)
  settings.soundScanComplete:SetPoint("TOPLEFT", settings.soundInviteAccepted, "BOTTOMLEFT", 0, -2)
  GRIP:AttachTooltip(settings.soundScanComplete, "Scan Results", "Play a sound when a /who scan returns results.")

  settings.soundCapWarning = W.CreateCheckbox(s, "Daily cap warning", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.soundCapWarning = btn:GetChecked() and true or false
  end)
  settings.soundCapWarning:SetPoint("TOPLEFT", settings.soundScanComplete, "BOTTOMLEFT", 0, -2)
  GRIP:AttachTooltip(settings.soundCapWarning, "Cap Warning", "Play a sound when approaching the daily whisper cap.")

  -- Separator: sound feedback → opt-out languages
  settings.sep5 = s:CreateTexture(nil, "ARTWORK")
  settings.sep5:SetHeight(1)
  settings.sep5:SetPoint("TOPLEFT", settings.soundCapWarning, "BOTTOMLEFT", -16, -8)
  settings.sep5:SetPoint("RIGHT", s, "RIGHT", -PAD_R, 0)
  settings.sep5:SetColorTexture(1, 1, 1, 0.08)

  -- Opt-Out Detection Languages section
  settings.optOutHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  settings.optOutHdr:SetPoint("TOPLEFT", settings.sep5, "BOTTOMLEFT", 0, -8)
  settings.optOutHdr:SetText("Opt-Out Detection Languages")

  settings.optOutEN = W.CreateCheckbox(s, "English", function(btn)
    btn:SetChecked(true)
    GRIP:Print("English is always enabled for opt-out detection.")
  end)
  settings.optOutEN:SetPoint("TOPLEFT", settings.optOutHdr, "BOTTOMLEFT", 0, -4)
  GRIP:AttachTooltip(settings.optOutEN, "English (Required)", "English opt-out phrases are always active and cannot be disabled.")

  settings.optOutFR = W.CreateCheckbox(s, "Français (French)", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    ToggleOptOutLanguage("fr", btn:GetChecked() and true or false)
  end)
  settings.optOutFR:SetPoint("TOPLEFT", settings.optOutEN, "BOTTOMLEFT", 0, -2)
  GRIP:AttachTooltip(settings.optOutFR, "French Opt-Out Phrases", "Enable French opt-out phrase detection for EU-FR realms.\nPhrases: non merci, pas intéressé, déjà dans une guilde, etc.")

  settings.optOutDE = W.CreateCheckbox(s, "Deutsch (German)", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    ToggleOptOutLanguage("de", btn:GetChecked() and true or false)
  end)
  settings.optOutDE:SetPoint("TOPLEFT", settings.optOutFR, "BOTTOMLEFT", 0, -2)
  GRIP:AttachTooltip(settings.optOutDE, "German Opt-Out Phrases", "Enable German opt-out phrase detection for EU-DE realms.\nPhrases: nein danke, nicht interessiert, hab schon ne gilde, etc.")

  settings.optOutES = W.CreateCheckbox(s, "Español (Spanish)", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    ToggleOptOutLanguage("es", btn:GetChecked() and true or false)
  end)
  settings.optOutES:SetPoint("TOPLEFT", settings.optOutDE, "BOTTOMLEFT", 0, -2)
  GRIP:AttachTooltip(settings.optOutES, "Spanish Opt-Out Phrases", "Enable Spanish opt-out phrase detection for EU-ES realms.\nPhrases: no gracias, no me interesa, ya tengo gremio, etc.")

  settings.optOutAggressive = W.CreateCheckbox(s, "Aggressive language detection", function(btn)
    if not _G.GRIPDB_CHAR then return end
    GRIPDB_CHAR.config.optOutAggressiveEnabled = btn:GetChecked() and true or false
    GRIP:RebuildOptOutPhrases()
  end)
  settings.optOutAggressive:SetPoint("TOPLEFT", settings.optOutES, "BOTTOMLEFT", 0, -8)
  GRIP:AttachTooltip(settings.optOutAggressive,
    "Aggressive Language Detection",
    "Enable detection of explicit/hostile rejection phrases as opt-outs.\n" ..
    "Phrases: fuck off, piss off, go away, bugger off, screw off, sod off.\n" ..
    "These are unambiguous rejections with near-zero false positive risk.\n" ..
    "Default: off.")

  -- Separator: opt-out languages → Raider.IO
  settings.sepRio = s:CreateTexture(nil, "ARTWORK")
  settings.sepRio:SetHeight(1)
  settings.sepRio:SetPoint("TOPLEFT", settings.optOutAggressive, "BOTTOMLEFT", 0, -8)
  settings.sepRio:SetPoint("RIGHT", s, "RIGHT", -PAD_R, 0)
  settings.sepRio:SetColorTexture(1, 1, 1, 0.08)

  -- Raider.IO Integration section (FE3)
  settings.rioHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  settings.rioHdr:SetPoint("TOPLEFT", settings.sepRio, "BOTTOMLEFT", 0, -8)
  settings.rioHdr:SetText("Raider.IO Integration")

  settings.rioNote = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  settings.rioNote:SetPoint("TOPLEFT", settings.rioHdr, "BOTTOMLEFT", 0, -4)
  settings.rioNote:SetJustifyH("LEFT")
  if settings.rioNote.SetWordWrap then settings.rioNote:SetWordWrap(true) end
  settings.rioNote:SetText("Requires the Raider.IO addon to be installed.")

  settings.rioMinScoreLabel = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  settings.rioMinScoreLabel:SetPoint("TOPLEFT", settings.rioNote, "BOTTOMLEFT", 0, -8)
  settings.rioMinScoreLabel:SetText("Minimum M+ Score (0 = disabled):")

  settings.rioMinScoreEB = CreateFrame("EditBox", nil, s, "InputBoxTemplate")
  settings.rioMinScoreEB:SetSize(60, 20)
  settings.rioMinScoreEB:SetPoint("LEFT", settings.rioMinScoreLabel, "RIGHT", 8, 0)
  settings.rioMinScoreEB:SetAutoFocus(false)
  settings.rioMinScoreEB:SetNumeric(true)
  settings.rioMinScoreEB:SetMaxLetters(5)
  settings.rioMinScoreEB:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  settings.rioMinScoreEB:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    if GRIP.state.ui and GRIP.state.ui.frame then GRIP.state.ui.frame:Hide() end
  end)
  settings.rioMinScoreEB:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    if not HasDB() then return end
    local n = tonumber(self:GetText()) or 0
    if n < 0 then n = 0 end
    GRIPDB_CHAR.config.rioMinScore = n
  end)

  settings.rioShowColumn = W.CreateCheckbox(s, "Show M+ column in Potential list", function(btn)
    if not HasDB() then btn:SetChecked(true) return end
    GRIPDB_CHAR.config.rioShowColumn = btn:GetChecked() and true or false
    GRIP:UpdateUI()
  end)
  settings.rioShowColumn:SetPoint("TOPLEFT", settings.rioMinScoreLabel, "BOTTOMLEFT", 0, -8)
  GRIP:AttachTooltip(settings.rioShowColumn, "M+ Column", "Show the M+ score column in the Home page Potential list.\nOnly visible when Raider.IO addon is installed.")

  -- Separator: Raider.IO → sync
  settings.sep4 = s:CreateTexture(nil, "ARTWORK")
  settings.sep4:SetHeight(1)
  settings.sep4:SetPoint("TOPLEFT", settings.rioShowColumn, "BOTTOMLEFT", 0, -8)
  settings.sep4:SetPoint("RIGHT", s, "RIGHT", -PAD_R, 0)
  settings.sep4:SetColorTexture(1, 1, 1, 0.08)

  -- Officer Blacklist Sync section (FE4)
  settings.syncHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  settings.syncHdr:SetPoint("TOPLEFT", settings.sep4, "BOTTOMLEFT", 0, -8)
  settings.syncHdr:SetText("Officer Blacklist Sync")

  settings.syncEnabled = W.CreateCheckbox(s, "Enable officer blacklist sync", function(btn)
    if not _G.GRIPDB then btn:SetChecked(false) return end
    GRIPDB.syncEnabled = btn:GetChecked() and true or false
    if GRIPDB.syncEnabled and GRIP.InitSync then
      pcall(function() GRIP:InitSync() end)
    end
  end)
  settings.syncEnabled:SetPoint("TOPLEFT", settings.syncHdr, "BOTTOMLEFT", 0, -4)
  GRIP:AttachTooltip(settings.syncEnabled, "Blacklist Sync",
    "Syncs permanent blacklist entries between guild officers running GRIP.\n"
    .. "Uses guild chat channel (invisible to players).\n"
    .. "Entries are only added, never removed (set-union merge).")

  -- Separator: sync → ghost mode
  settings.sep5 = s:CreateTexture(nil, "ARTWORK")
  settings.sep5:SetHeight(1)
  settings.sep5:SetPoint("TOPLEFT", settings.syncEnabled, "BOTTOMLEFT", 0, -8)
  settings.sep5:SetPoint("RIGHT", s, "RIGHT", -PAD_R, 0)
  settings.sep5:SetColorTexture(1, 1, 1, 0.08)

  -- Ghost Mode section
  settings.ghostHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  settings.ghostHdr:SetPoint("TOPLEFT", settings.sep5, "BOTTOMLEFT", 0, -8)
  settings.ghostHdr:SetText("Ghost Mode (Experimental)")

  settings.ghostEnabled = W.CreateCheckbox(s, "Enable Ghost Mode", function(btn)
    if not HasDB() then btn:SetChecked(false) return end
    GRIPDB_CHAR.config.ghostModeEnabled = btn:GetChecked() and true or false
    GRIP:UpdateUI()
  end)
  settings.ghostEnabled:SetPoint("TOPLEFT", settings.ghostHdr, "BOTTOMLEFT", 0, -4)
  GRIP:AttachTooltip(settings.ghostEnabled, "Ghost Mode", "Enables the Ghost overlay that captures hardware events\nto automatically drain whisper/invite/post queues.")

  settings.ghostSessionSlider = W.CreateSlider(s, "Ghost Session Max (minutes)", 5, 120, 5, 60, 160, function(v)
    if not HasDB() then return end
    GRIPDB_CHAR.config.ghostSessionMaxMinutes = v
  end)
  settings.ghostSessionSlider:SetPoint("TOPLEFT", settings.ghostEnabled, "BOTTOMLEFT", 16, -22)

  settings.ghostCooldownSlider = W.CreateSlider(s, "Ghost Cooldown (minutes)", 1, 60, 1, 10, 160, function(v)
    if not HasDB() then return end
    GRIPDB_CHAR.config.ghostCooldownMinutes = v
  end)
  settings.ghostCooldownSlider:SetPoint("TOPLEFT", settings.ghostSessionSlider, "BOTTOMLEFT", 0, -24)

  -- Button accent underlines
  W.AddButtonAccent(settings.applyLevels, 1, 0.82, 0)
  W.AddButtonAccent(settings.whisperSave, 1, 0.82, 0)
  W.AddButtonAccent(settings.whisperPreview, 1, 0.82, 0)
  W.AddButtonAccent(settings.clearFilters, 0.8, 0.3, 0.3)
  W.AddButtonAccent(settings.whisperRemove, 0.8, 0.3, 0.3)

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
    W.SetEnabledSafe(s.hideWhisperEcho, false)
    W.SetEnabledSafe(s.inviteFirst, false)

    W.SetEnabledSafe(s.soundEnabled, false)
    W.SetEnabledSafe(s.soundWhisperDone, false)
    W.SetEnabledSafe(s.soundInviteAccepted, false)
    W.SetEnabledSafe(s.soundScanComplete, false)
    W.SetEnabledSafe(s.soundCapWarning, false)

    W.SetEnabledSafe(s.optOutEN, false)
    W.SetEnabledSafe(s.optOutFR, false)
    W.SetEnabledSafe(s.optOutDE, false)
    W.SetEnabledSafe(s.optOutES, false)
    W.SetEnabledSafe(s.optOutAggressive, false)

    W.SetEnabledSafe(s.syncEnabled, false)

    W.SetEnabledSafe(s.ghostEnabled, false)
    W.SetEnabledSafe(s.ghostSessionSlider, false)
    W.SetEnabledSafe(s.ghostCooldownSlider, false)

    if s.whisperRemaining then s.whisperRemaining:SetText("") end
    pcall(function() GRIP:UI_LayoutSettings() end)
    return
  end

  if s._initHint then s._initHint:Hide() end

  -- Re-enable controls now that DB exists.
  -- Lock scan/filter controls during Ghost session to prevent mid-session config changes.
  local ghostLocked = GRIP.Ghost and GRIP.Ghost.IsSessionLocked and GRIP.Ghost:IsSessionLocked()
  local filterEnabled = not ghostLocked

  W.SetEnabledSafe(s.minEdit, filterEnabled)
  W.SetEnabledSafe(s.maxEdit, filterEnabled)
  W.SetEnabledSafe(s.stepEdit, filterEnabled)
  W.SetEnabledSafe(s.zoneOnly, filterEnabled)
  W.SetEnabledSafe(s.applyLevels, filterEnabled)

  W.SetEnabledSafe(s.zoneAll, filterEnabled)
  W.SetEnabledSafe(s.zoneNone, filterEnabled)
  W.SetEnabledSafe(s.zoneCurrent, filterEnabled)
  W.SetEnabledSafe(s.raceAll, filterEnabled)
  W.SetEnabledSafe(s.raceNone, filterEnabled)
  W.SetEnabledSafe(s.classAll, filterEnabled)
  W.SetEnabledSafe(s.classNone, filterEnabled)
  W.SetEnabledSafe(s.clearFilters, filterEnabled)

  W.SetEnabledSafe(s.whisperEdit, true)
  W.SetEnabledSafe(s.whisperAppendLink, true)
  W.SetEnabledSafe(s.whisperInsertGuild, true)
  W.SetEnabledSafe(s.whisperInsertPlayer, true)
  W.SetEnabledSafe(s.whisperAdd, true)
  W.SetEnabledSafe(s.whisperRotSeq, true)
  W.SetEnabledSafe(s.whisperRotRand, true)
  W.SetEnabledSafe(s.hideWhisperEcho, true)
  W.SetEnabledSafe(s.inviteFirst, true)

  W.SetTextIfUnfocused(s.minEdit, tostring(GRIPDB_CHAR.config.scanMinLevel or 1))
  W.SetTextIfUnfocused(s.maxEdit, tostring(GRIPDB_CHAR.config.scanMaxLevel or 90))
  W.SetTextIfUnfocused(s.stepEdit, tostring(GRIPDB_CHAR.config.scanStep or 5))
  s.zoneOnly:SetChecked(GRIPDB_CHAR.config.scanZoneOnly and true or false)

  s.zoneList:Render(GRIP:GetZonesGroupedForUI(), GRIPDB_CHAR.filters.zones)
  s.raceList:Render(GRIPDB_CHAR.lists.races, GRIPDB_CHAR.filters.races)
  s.classList:Render(GRIPDB_CHAR.lists.classes, GRIPDB_CHAR.filters.classes)

  -- Grey out checklist panels during Ghost session
  if s.zoneList.EnableMouse then s.zoneList:EnableMouse(filterEnabled) end
  if s.raceList.EnableMouse then s.raceList:EnableMouse(filterEnabled) end
  if s.classList.EnableMouse then s.classList:EnableMouse(filterEnabled) end
  if s.zoneList.SetAlpha then s.zoneList:SetAlpha(filterEnabled and 1.0 or 0.45) end
  if s.raceList.SetAlpha then s.raceList:SetAlpha(filterEnabled and 1.0 or 0.45) end
  if s.classList.SetAlpha then s.classList:SetAlpha(filterEnabled and 1.0 or 0.45) end

  -- Multi-template: reload drafts when edit box isn't actively being used.
  if not s.whisperEdit:HasFocus() and not s.whisperEdit._gripDirty then
    LoadWhisperDrafts(s)
    ShowWhisperTemplate(s, s._whisperIdx or 1)
  else
    UpdateWhisperNavText(s)
  end
  UpdateRotationHighlight(s)
  EnforceWhisperBudget(s, s.whisperEdit)

  -- Whisper echo suppression
  s.hideWhisperEcho:SetChecked(GRIPDB_CHAR.config.suppressWhisperEcho and true or false)
  s.inviteFirst:SetChecked(GRIPDB_CHAR.config.inviteFirst and true or false)

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

  -- Opt-out language checkboxes
  W.SetEnabledSafe(s.optOutEN, true)
  s.optOutEN:SetChecked(true)  -- always on
  W.SetEnabledSafe(s.optOutFR, true)
  W.SetEnabledSafe(s.optOutDE, true)
  W.SetEnabledSafe(s.optOutES, true)
  local langs = GRIPDB_CHAR.config.optOutLanguages or {"en"}
  local langSet = {}
  for _, l in ipairs(langs) do langSet[l] = true end
  s.optOutFR:SetChecked(langSet["fr"] and true or false)
  s.optOutDE:SetChecked(langSet["de"] and true or false)
  s.optOutES:SetChecked(langSet["es"] and true or false)

  W.SetEnabledSafe(s.optOutAggressive, not ghostLocked)
  s.optOutAggressive:SetChecked(GRIPDB_CHAR.config.optOutAggressiveEnabled and true or false)

  -- Raider.IO section (FE3)
  local rioAvailable = GRIP:IsRaiderIOAvailable()
  local rioEnabled = rioAvailable and not ghostLocked
  if s.rioNote then
    if rioAvailable then
      s.rioNote:SetText("Raider.IO addon detected.")
      s.rioNote:SetTextColor(0.4, 0.8, 0.4)
    else
      s.rioNote:SetText("Raider.IO addon not installed. Controls are disabled.")
      s.rioNote:SetTextColor(0.5, 0.5, 0.5)
    end
  end
  W.SetEnabledSafe(s.rioMinScoreEB, rioEnabled)
  if s.rioMinScoreEB and not s.rioMinScoreEB:HasFocus() then
    s.rioMinScoreEB:SetText(tostring(GRIPDB_CHAR.config.rioMinScore or 0))
  end
  W.SetEnabledSafe(s.rioShowColumn, rioEnabled)
  if s.rioShowColumn then
    s.rioShowColumn:SetChecked(GRIPDB_CHAR.config.rioShowColumn ~= false)
  end
  -- Dim the header when RIO not available
  if s.rioHdr then
    if rioAvailable then
      s.rioHdr:SetTextColor(1, 0.82, 0)
    else
      s.rioHdr:SetTextColor(0.5, 0.5, 0.5)
    end
  end
  if s.rioMinScoreLabel then
    if rioAvailable then
      s.rioMinScoreLabel:SetTextColor(1, 1, 1)
    else
      s.rioMinScoreLabel:SetTextColor(0.5, 0.5, 0.5)
    end
  end

  -- Officer Blacklist Sync (FE4)
  W.SetEnabledSafe(s.syncEnabled, true)
  if s.syncEnabled then
    s.syncEnabled:SetChecked(_G.GRIPDB and GRIPDB.syncEnabled ~= false)
  end

  -- Ghost Mode
  local ghostOn = GRIPDB_CHAR.config.ghostModeEnabled and true or false
  W.SetEnabledSafe(s.ghostEnabled, true)
  s.ghostEnabled:SetChecked(ghostOn)
  W.SetEnabledSafe(s.ghostSessionSlider, ghostOn)
  W.SetEnabledSafe(s.ghostCooldownSlider, ghostOn)
  if s.ghostSessionSlider then s.ghostSessionSlider:SetValue(GRIPDB_CHAR.config.ghostSessionMaxMinutes or 60) end
  if s.ghostCooldownSlider then s.ghostCooldownSlider:SetValue(GRIPDB_CHAR.config.ghostCooldownMinutes or 10) end

  -- Keep layout responsive (UI.lua calls it too, but this makes Settings robust if called directly).
  pcall(function() GRIP:UI_LayoutSettings() end)
end