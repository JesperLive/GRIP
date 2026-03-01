-- Rev 12
-- GRIP – UI: Settings page
--
-- CHANGED (Rev 11):
-- - Fix Lua syntax error that prevented the file from loading:
--   use DOT for existence checks + COLON only for method calls (e.g., GRIP.GetGuildName and GRIP:GetGuildName()).
-- - Compress prior revision notes into one short summary list.
--
-- Summary of Rev 1–10:
-- - Added DB nil-safety + init locking to prevent early-open errors.
-- - Hardened callbacks and reduced UI churn during initialization.
-- - Whisper editor: cursor-aware token insertion, multiple tokens allowed, layout fixes.
-- - Whisper editor: expansion-aware 255-byte budgeting with live counter, typing enforcement, and all-or-nothing token insertion.
-- - Added responsive Settings layout hook for resizable main window.
--
-- CHANGED (Rev 12):
-- - Make layout truly width-driven using real scrollframe width; avoid overlap at narrow sizes via reflow.
-- - Anchor whisper editor to both left+right edges (natural resize; less hard-coded width dependence).
-- - Reflow filter columns + action buttons when narrow (stack vertically instead of overlapping).
-- - Auto-size scroll content height from bottom-most widget (prevents clipping on short heights / UI scale differences).

local ADDON_NAME, GRIP = ...
local state = GRIP.state
local W = GRIP.UIW

local MAX_WHISPER_BYTES = 255

local PAD_L = 4
local PAD_R = 24 -- leave room from right edge inside scroll content

local function HasDB()
  return (_G.GRIPDB and GRIPDB.config and GRIPDB.lists and GRIPDB.filters) and true or false
end

local function ClearDirty(...)
  for i = 1, select("#", ...) do
    local eb = select(i, ...)
    if eb then eb._gripDirty = false end
  end
end

local function ProgrammaticSet(eb, text)
  if not eb then return end
  eb._gripProgrammatic = true
  eb:SetText(tostring(text or ""))
  eb._gripProgrammatic = false
end

local function SetAll(list, filterTbl)
  wipe(filterTbl)
  for _, v in ipairs(list or {}) do
    filterTbl[v] = true
  end
end

local function SetEnabledSafe(widget, enabled)
  if not widget then return end
  enabled = enabled and true or false

  if widget.SetEnabled then
    widget:SetEnabled(enabled)
  elseif enabled and widget.Enable then
    widget:Enable()
  elseif (not enabled) and widget.Disable then
    widget:Disable()
  end

  -- For checkbuttons/editboxes that don't fully "grey" via SetEnabled:
  if widget.SetAlpha then
    widget:SetAlpha(enabled and 1 or 0.6)
  end
end

local function IsBlank(s)
  if type(s) ~= "string" then return true end
  return s:gsub("%s+", "") == ""
end

local function SanitizeOneLine(s)
  s = tostring(s or "")
  s = s:gsub("[\r\n]+", " ")
  return s
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
  -- If clickable link isn't available, fall back to the guild name (still stable).
  local link = ""
  if inGuild and GRIP.GetGuildFinderLink then
    link = GRIP:GetGuildFinderLink() or ""
  end
  if IsBlank(link) then
    link = inGuild and guildName or "your guild"
  end

  local out = rawText
  out = out:gsub("{player}", playerStub)
  out = out:gsub("{name}", playerStub)
  out = out:gsub("{guild}", guildName)
  out = out:gsub("{guildlink}", link)

  out = SanitizeOneLine(out)
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
  SetEnabledSafe(s.whisperSave, ok)
  SetEnabledSafe(s.whisperPreview, ok)
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

  local trimmed = txt
  -- Simple, reliable approach: drop from the END until it fits.
  while #trimmed > 0 and EstimateWhisperRenderedBytes(trimmed) > MAX_WHISPER_BYTES do
    trimmed = trimmed:sub(1, -2)
  end

  ProgrammaticSet(eb, trimmed)
  eb._gripDirty = true

  eb:SetFocus()
  if eb.SetCursorPosition then
    local newCursor = cursor
    if newCursor > #trimmed then newCursor = #trimmed end
    eb:SetCursorPosition(newCursor)
  end

  UpdateWhisperBudgetUI(s)
end

-- Build a candidate string that inserts token at cursor with light spacing help.
local function BuildInsertedTextAtCursor(eb, token)
  if not eb then return nil, nil end
  token = tostring(token or "")
  if token == "" then return nil, nil end

  local t = eb:GetText() or ""

  local cursor = 0
  if eb.GetCursorPosition then
    cursor = tonumber(eb:GetCursorPosition()) or 0
  end
  if cursor < 0 then cursor = 0 end
  if cursor > #t then cursor = #t end

  local before = t:sub(1, cursor)
  local after = t:sub(cursor + 1)

  -- Light spacing help: if we're mid-word, just insert; otherwise, add a space on either side as needed.
  local needsLeftSpace = (before ~= "" and not before:match("%s$"))
  local needsRightSpace = (after ~= "" and not after:match("^%s"))

  local insert = token
  if needsLeftSpace then insert = " " .. insert end
  if needsRightSpace then insert = insert .. " " end

  local newText = before .. insert .. after
  local newCursor = #before + #insert
  return newText, newCursor
end

-- ALL-OR-NOTHING token insertion:
-- If the expanded output would exceed the budget, do nothing (prevents partial token fragments).
local function TryInsertTokenAtCursorWithBudget(s, eb, token)
  if not s or not eb then return false end
  if not HasDB() then return false end

  local candidate, newCursor = BuildInsertedTextAtCursor(eb, token)
  if not candidate then return false end

  if EstimateWhisperRenderedBytes(candidate) > MAX_WHISPER_BYTES then
    -- No insertion. Keep focus so user can edit.
    eb:SetFocus()
    UpdateWhisperBudgetUI(s)
    return false
  end

  ProgrammaticSet(eb, candidate)
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

local function SafeTop(frame)
  if not frame or not frame.GetTop then return nil end
  return frame:GetTop()
end

local function SafeBottom(frame)
  if not frame or not frame.GetBottom then return nil end
  return frame:GetBottom()
end

local function UpdateScrollContentHeight(settings)
  if not settings or not settings.content then return end
  local c = settings.content
  local top = SafeTop(c)
  if not top then return end

  local lowest = nil
  local function consider(f)
    if not f or (f.IsShown and not f:IsShown()) then return end
    local b = SafeBottom(f)
    if not b then return end
    if (not lowest) or (b < lowest) then lowest = b end
  end

  consider(settings.whisperPreview)
  consider(settings.whisperSave)
  consider(settings.whisperInsertPlayer)
  consider(settings.whisperInsertGuild)
  consider(settings.whisperAppendLink)
  consider(settings.whisperSF)
  consider(settings.whisperHdr)

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
    settings.whisperSF:SetPoint("TOPLEFT", settings.whisperHdr, "BOTTOMLEFT", 0, -6)
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

    GRIPDB.config.scanZoneOnly = btn:GetChecked() and true or false
    GRIP:Print("scanZoneOnly: " .. (GRIPDB.config.scanZoneOnly and "ON" or "OFF"))
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

    GRIPDB.config.scanMinLevel = GRIP:Clamp(a1, 1, 100)
    GRIPDB.config.scanMaxLevel = GRIP:Clamp(b1, GRIPDB.config.scanMinLevel, 100)
    GRIPDB.config.scanStep = GRIP:Clamp(c1, 1, 20)

    ClearDirty(settings.minEdit, settings.maxEdit, settings.stepEdit)

    GRIP:BuildWhoQueue()
    GRIP:Print(("Scan levels set: %d-%d step %d"):format(GRIPDB.config.scanMinLevel, GRIPDB.config.scanMaxLevel, GRIPDB.config.scanStep))
    GRIP:UpdateUI()
  end)
  settings.applyLevels:SetPoint("LEFT", settings.stepEdit, "RIGHT", 14, 0)

  settings.filtersHelp = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  settings.filtersHelp:SetPoint("TOPLEFT", settings.zoneOnly, "BOTTOMLEFT", 0, -8)
  settings.filtersHelp:SetText("Filters are allowlists. If nothing is checked in a category, that category allows ALL.")

  settings.zoneList = W.CreateChecklist(s, "Zones", 250, 140)
  settings.zoneList:SetPoint("TOPLEFT", settings.filtersHelp, "BOTTOMLEFT", 0, -8)

  settings.raceList = W.CreateChecklist(s, "Races", 250, 140)
  settings.raceList:SetPoint("TOPLEFT", settings.zoneList, "TOPRIGHT", 12, 0)

  settings.classList = W.CreateChecklist(s, "Classes", 250, 140)
  settings.classList:SetPoint("TOPLEFT", settings.zoneList, "BOTTOMLEFT", 0, -12)

  settings.zoneAll = W.CreateUIButton(s, "All", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    SetAll(GRIPDB.lists.zones, GRIPDB.filters.zones); GRIP:UpdateUI()
  end)
  settings.zoneAll:SetPoint("TOPRIGHT", settings.zoneList, "TOPRIGHT", -52, -4)

  settings.zoneNone = W.CreateUIButton(s, "None", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB.filters.zones); GRIP:UpdateUI()
  end)
  settings.zoneNone:SetPoint("LEFT", settings.zoneAll, "RIGHT", 4, 0)

  settings.raceAll = W.CreateUIButton(s, "All", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    SetAll(GRIPDB.lists.races, GRIPDB.filters.races); GRIP:UpdateUI()
  end)
  settings.raceAll:SetPoint("TOPRIGHT", settings.raceList, "TOPRIGHT", -52, -4)

  settings.raceNone = W.CreateUIButton(s, "None", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB.filters.races); GRIP:UpdateUI()
  end)
  settings.raceNone:SetPoint("LEFT", settings.raceAll, "RIGHT", 4, 0)

  settings.classAll = W.CreateUIButton(s, "All", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    SetAll(GRIPDB.lists.classes, GRIPDB.filters.classes); GRIP:UpdateUI()
  end)
  settings.classAll:SetPoint("TOPRIGHT", settings.classList, "TOPRIGHT", -52, -4)

  settings.classNone = W.CreateUIButton(s, "None", 44, 18, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB.filters.classes); GRIP:UpdateUI()
  end)
  settings.classNone:SetPoint("LEFT", settings.classAll, "RIGHT", 4, 0)

  settings.clearFilters = W.CreateUIButton(s, "Clear Selections", 120, 22, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    wipe(GRIPDB.filters.zones)
    wipe(GRIPDB.filters.races)
    wipe(GRIPDB.filters.classes)
    GRIP:Print("Cleared filter selections.")
    GRIP:UpdateUI()
  end)
  settings.clearFilters:SetPoint("TOPLEFT", settings.classList, "TOPRIGHT", 12, -2)

  settings.whisperHdr = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  settings.whisperHdr:SetPoint("TOPLEFT", settings.classList, "BOTTOMLEFT", 0, -12)
  settings.whisperHdr:SetText("Whisper message (supports {player} {guild} {guildlink})")

  -- Create with tiny initial width; layout hook anchors + sizes it properly.
  settings.whisperSF, settings.whisperEdit = W.CreateMultilineEdit(s, 1, 60)
  settings.whisperSF:SetPoint("TOPLEFT", settings.whisperHdr, "BOTTOMLEFT", 0, -6)

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

      -- Only enforce on actual user edits (typing/paste), not our own ProgrammaticSet.
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
    if not ok then
      GRIP:Print("No room to insert {guildlink} (max 255 after expansion).")
    end
  end)
  settings.whisperAppendLink:SetPoint("TOPLEFT", settings.whisperSF, "BOTTOMLEFT", 0, -6)

  settings.whisperInsertGuild = W.CreateUIButton(s, "Insert {guild}", 110, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursorWithBudget(settings, settings.whisperEdit, "{guild}")
    if not ok then
      GRIP:Print("No room to insert {guild} (max 255 after expansion).")
    end
  end)
  settings.whisperInsertGuild:SetPoint("LEFT", settings.whisperAppendLink, "RIGHT", 8, 0)

  settings.whisperInsertPlayer = W.CreateUIButton(s, "Insert {player}", 120, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursorWithBudget(settings, settings.whisperEdit, "{player}")
    if not ok then
      GRIP:Print("No room to insert {player} (max 255 after expansion).")
    end
  end)
  settings.whisperInsertPlayer:SetPoint("LEFT", settings.whisperInsertGuild, "RIGHT", 8, 0)

  settings.whisperSave = W.CreateUIButton(s, "Save", 70, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end
    settings.whisperEdit:ClearFocus()

    -- Should already be enforced, but keep the check.
    UpdateWhisperBudgetUI(settings)
    local bytes = EstimateWhisperRenderedBytes(settings.whisperEdit:GetText() or "")
    if bytes > MAX_WHISPER_BYTES then
      GRIP:Print("Whisper message is too long after token expansion (max 255).")
      return
    end

    GRIPDB.config.whisperMessage = settings.whisperEdit:GetText() or GRIPDB.config.whisperMessage
    ClearDirty(settings.whisperEdit)
    GRIP:Print("Whisper message saved.")
    GRIP:UpdateUI()
  end)
  settings.whisperSave:SetPoint("TOPLEFT", settings.whisperAppendLink, "BOTTOMLEFT", 0, -6)

  settings.whisperPreview = W.CreateUIButton(s, "Preview", 80, 20, function()
    if not HasDB() then GRIP:Print("Settings unavailable yet (DB not initialized).") return end

    UpdateWhisperBudgetUI(settings)
    local bytes = EstimateWhisperRenderedBytes(settings.whisperEdit:GetText() or "")
    if bytes > MAX_WHISPER_BYTES then
      GRIP:Print("Whisper message is too long after token expansion (max 255).")
      return
    end

    local msg = GRIP:ApplyTemplate(settings.whisperEdit:GetText() or "", UnitName("player") or "")
    GRIP:Print("Preview: " .. msg)
  end)
  settings.whisperPreview:SetPoint("LEFT", settings.whisperSave, "RIGHT", 8, 0)

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

    SetEnabledSafe(s.minEdit, false)
    SetEnabledSafe(s.maxEdit, false)
    SetEnabledSafe(s.stepEdit, false)
    SetEnabledSafe(s.zoneOnly, false)
    SetEnabledSafe(s.applyLevels, false)

    SetEnabledSafe(s.zoneAll, false)
    SetEnabledSafe(s.zoneNone, false)
    SetEnabledSafe(s.raceAll, false)
    SetEnabledSafe(s.raceNone, false)
    SetEnabledSafe(s.classAll, false)
    SetEnabledSafe(s.classNone, false)
    SetEnabledSafe(s.clearFilters, false)

    SetEnabledSafe(s.whisperEdit, false)
    SetEnabledSafe(s.whisperAppendLink, false)
    SetEnabledSafe(s.whisperInsertGuild, false)
    SetEnabledSafe(s.whisperInsertPlayer, false)
    SetEnabledSafe(s.whisperSave, false)
    SetEnabledSafe(s.whisperPreview, false)

    if s.whisperRemaining then s.whisperRemaining:SetText("") end
    pcall(function() GRIP:UI_LayoutSettings() end)
    return
  end

  if s._initHint then s._initHint:Hide() end

  -- Re-enable controls now that DB exists.
  SetEnabledSafe(s.minEdit, true)
  SetEnabledSafe(s.maxEdit, true)
  SetEnabledSafe(s.stepEdit, true)
  SetEnabledSafe(s.zoneOnly, true)
  SetEnabledSafe(s.applyLevels, true)

  SetEnabledSafe(s.zoneAll, true)
  SetEnabledSafe(s.zoneNone, true)
  SetEnabledSafe(s.raceAll, true)
  SetEnabledSafe(s.raceNone, true)
  SetEnabledSafe(s.classAll, true)
  SetEnabledSafe(s.classNone, true)
  SetEnabledSafe(s.clearFilters, true)

  SetEnabledSafe(s.whisperEdit, true)
  SetEnabledSafe(s.whisperAppendLink, true)
  SetEnabledSafe(s.whisperInsertGuild, true)
  SetEnabledSafe(s.whisperInsertPlayer, true)

  W.SetTextIfUnfocused(s.minEdit, tostring(GRIPDB.config.scanMinLevel or 1))
  W.SetTextIfUnfocused(s.maxEdit, tostring(GRIPDB.config.scanMaxLevel or 90))
  W.SetTextIfUnfocused(s.stepEdit, tostring(GRIPDB.config.scanStep or 5))
  s.zoneOnly:SetChecked(GRIPDB.config.scanZoneOnly and true or false)

  s.zoneList:Render(GRIPDB.lists.zones, GRIPDB.filters.zones)
  s.raceList:Render(GRIPDB.lists.races, GRIPDB.filters.races)
  s.classList:Render(GRIPDB.lists.classes, GRIPDB.filters.classes)

  W.SetTextIfUnfocused(s.whisperEdit, GRIPDB.config.whisperMessage or "")

  -- Enforce + refresh budget and Save/Preview enabled state based on current text.
  EnforceWhisperBudget(s, s.whisperEdit)

  -- Keep layout responsive (UI.lua calls it too, but this makes Settings robust if called directly).
  pcall(function() GRIP:UI_LayoutSettings() end)
end