-- GRIP: UI Ads Page
-- Trade/General message editors, post scheduler config, queue/post buttons.

local ADDON_NAME, GRIP = ...
local state = GRIP.state
local W = GRIP.UIW

local MAX_CHANNEL_BYTES = 255

local PAD_L = 4
local PAD_R = 24 -- leave room from the right edge inside scroll content

local function HasCfg()
  return (_G.GRIPDB and GRIPDB.config) and true or false
end

local function GetCfg()
  return (_G.GRIPDB and GRIPDB.config) or nil
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

local function SecondsLeft(untilT)
  local now = GetTime()
  local left = (untilT or 0) - now
  if left < 0 then left = 0 end
  return left
end

-- ---------------------------------------------------------------------------
-- Byte-budget estimation for channel message editors.
-- Channel messages support {guild} and {guildlink} but NOT {player}/{name}
-- (channel messages have no single target; ApplyTemplate passes nil).
-- ---------------------------------------------------------------------------
local function EstimateChannelRenderedBytes(rawText)
  rawText = tostring(rawText or "")

  local guildName = (GRIP.GetGuildName and GRIP:GetGuildName()) or ""
  local inGuild = (guildName ~= "")

  local link = ""
  if inGuild and GRIP.GetGuildFinderLink then
    link = GRIP:GetGuildFinderLink() or ""
  end
  if IsBlank(link) then
    link = inGuild and guildName or "your guild"
  end

  local out = rawText
  -- Replace {guildlink} BEFORE {guild} — {guild} is a substring of {guildlink}.
  out = out:gsub("{guildlink}", link)
  out = out:gsub("{guild}", guildName)
  out = SanitizeOneLine(out)
  return #out
end

-- Update the "remaining bytes" counter for one editor (gen or trade).
local function UpdateEditorBudgetUI(ads, editKey)
  if not ads then return end
  local eb = ads[editKey .. "Edit"]
  local counter = ads[editKey .. "Remaining"]
  if not (eb and counter) then return end

  local bytes = EstimateChannelRenderedBytes(eb:GetText() or "")
  local remaining = MAX_CHANNEL_BYTES - bytes
  if remaining < 0 then remaining = 0 end
  counter:SetText(tostring(remaining))
end

-- Enable/disable Save and per-editor Preview based on budget.
local function UpdateBudgetControls(ads)
  if not ads then return end

  local genOk = EstimateChannelRenderedBytes((ads.genEdit and ads.genEdit:GetText()) or "") <= MAX_CHANNEL_BYTES
  local tradeOk = EstimateChannelRenderedBytes((ads.tradeEdit and ads.tradeEdit:GetText()) or "") <= MAX_CHANNEL_BYTES

  SetEnabledSafe(ads.save, genOk and tradeOk)
  SetEnabledSafe(ads.genPreview, genOk)
  SetEnabledSafe(ads.tradePreview, tradeOk)
end

-- Trim the raw editor text until the expanded message fits MAX_CHANNEL_BYTES.
local function EnforceChannelBudget(ads, eb, editKey)
  if not ads or not eb then return end
  if not HasCfg() then return end

  local txt = eb:GetText() or ""
  local bytes = EstimateChannelRenderedBytes(txt)
  if bytes <= MAX_CHANNEL_BYTES then
    UpdateEditorBudgetUI(ads, editKey)
    UpdateBudgetControls(ads)
    return
  end

  local cursor = 0
  if eb.GetCursorPosition then
    cursor = tonumber(eb:GetCursorPosition()) or 0
  end
  if cursor < 0 then cursor = 0 end
  if cursor > #txt then cursor = #txt end

  local trimmed = txt
  while #trimmed > 0 and EstimateChannelRenderedBytes(trimmed) > MAX_CHANNEL_BYTES do
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

  UpdateEditorBudgetUI(ads, editKey)
  UpdateBudgetControls(ads)
end

-- Build text with token inserted at cursor, with light spacing help.
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

  local needsLeftSpace = (before ~= "" and not before:match("%s$"))
  local needsRightSpace = (after ~= "" and not after:match("^%s"))

  local insert = token
  if needsLeftSpace then insert = " " .. insert end
  if needsRightSpace then insert = insert .. " " end

  local newText = before .. insert .. after
  local newCursor = #before + #insert
  return newText, newCursor
end

-- All-or-nothing token insert: if the expanded output would exceed budget, do nothing.
local function TryInsertTokenAtCursor(ads, eb, token, editKey)
  if not ads or not eb then return false end
  if not HasCfg() then return false end

  local candidate, newCursor = BuildInsertedTextAtCursor(eb, token)
  if not candidate then return false end

  if EstimateChannelRenderedBytes(candidate) > MAX_CHANNEL_BYTES then
    eb:SetFocus()
    UpdateEditorBudgetUI(ads, editKey)
    UpdateBudgetControls(ads)
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

  UpdateEditorBudgetUI(ads, editKey)
  UpdateBudgetControls(ads)
  return true
end

-- ---------------------------------------------------------------------------
-- Lock / Unlock helpers
-- ---------------------------------------------------------------------------
local function LockUI(a, why)
  if not a then return end

  if a._initHint then
    a._initHint:Show()
    if why and why ~= "" then
      a._initHint:SetText(tostring(why))
    else
      a._initHint:SetText("Initializing\226\128\166 (database not ready yet)")
    end
  elseif a.content then
    a._initHint = a.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    a._initHint:SetPoint("TOPLEFT", a.title, "BOTTOMLEFT", 0, -4)
    a._initHint:SetText((why and why ~= "") and tostring(why) or "Initializing\226\128\166 (database not ready yet)")
    a._initHint:Show()
  end

  SetEnabledSafe(a.enabled, false)
  SetEnabledSafe(a.intEdit, false)
  SetEnabledSafe(a.apply, false)
  SetEnabledSafe(a.genEdit, false)
  SetEnabledSafe(a.tradeEdit, false)
  SetEnabledSafe(a.genInsertGuild, false)
  SetEnabledSafe(a.genInsertLink, false)
  SetEnabledSafe(a.genPreview, false)
  SetEnabledSafe(a.tradeInsertGuild, false)
  SetEnabledSafe(a.tradeInsertLink, false)
  SetEnabledSafe(a.tradePreview, false)
  SetEnabledSafe(a.save, false)
  SetEnabledSafe(a.queueNow, false)
  SetEnabledSafe(a.postNext, false)
end

local function UnlockUI(a)
  if not a then return end
  if a._initHint then a._initHint:Hide() end

  SetEnabledSafe(a.enabled, true)
  SetEnabledSafe(a.intEdit, true)
  SetEnabledSafe(a.apply, true)
  SetEnabledSafe(a.genEdit, true)
  SetEnabledSafe(a.tradeEdit, true)
  SetEnabledSafe(a.genInsertGuild, true)
  SetEnabledSafe(a.genInsertLink, true)
  SetEnabledSafe(a.genPreview, true)
  SetEnabledSafe(a.tradeInsertGuild, true)
  SetEnabledSafe(a.tradeInsertLink, true)
  SetEnabledSafe(a.tradePreview, true)
  SetEnabledSafe(a.save, true)
  SetEnabledSafe(a.queueNow, true)
  SetEnabledSafe(a.postNext, true)
end

-- ---------------------------------------------------------------------------
-- Scroll child height tracking
-- ---------------------------------------------------------------------------
local function SafeTop(frame)
  if not frame or not frame.GetTop then return nil end
  return frame:GetTop()
end

local function SafeBottom(frame)
  if not frame or not frame.GetBottom then return nil end
  return frame:GetBottom()
end

local function UpdateScrollChildHeight(ads)
  if not ads or not ads.content then return end
  local a = ads.content
  local top = SafeTop(a)
  if not top then return end

  local lowest = nil
  local function consider(f)
    if not f or (f.IsShown and not f:IsShown()) then return end
    local b = SafeBottom(f)
    if not b then return end
    if (not lowest) or (b < lowest) then lowest = b end
  end

  consider(ads.postNext)
  consider(ads.queueNow)
  consider(ads.save)
  consider(ads.tradePreview)
  consider(ads.tradeInsertLink)
  consider(ads.tradeInsertGuild)
  consider(ads.tradeSF)
  consider(ads.tradeHdr)
  consider(ads.genPreview)
  consider(ads.genInsertLink)
  consider(ads.genInsertGuild)
  consider(ads.genSF)
  consider(ads.generalHdr)
  consider(ads.apply)
  consider(ads.intLbl)
  consider(ads.enabled)
  consider(ads.title)

  if not lowest then return end

  local needed = (top - lowest) + 28
  if needed < 200 then needed = 200 end

  a:SetHeight(needed)
end

-- ---------------------------------------------------------------------------
-- Responsive layout (called by UI.lua on size changes / tab switch)
-- ---------------------------------------------------------------------------
function GRIP:UI_LayoutAds()
  if not state.ui or not state.ui.ads then return end
  local ads = state.ui.ads
  if not ads.content then return end

  local a = ads.content
  local w = tonumber(a:GetWidth()) or 0
  if w <= 0 then return end

  local usable = w - PAD_L - PAD_R
  if usable < 200 then usable = 200 end

  -- Stretch multiline editors to full content width.
  if ads.genSF and ads.genSF.SetWidth then ads.genSF:SetWidth(usable) end
  if ads.tradeSF and ads.tradeSF.SetWidth then ads.tradeSF:SetWidth(usable) end

  if ads.genEdit and ads.genEdit.SetWidth and ads.genSF and ads.genSF.GetWidth then
    ads.genEdit:SetWidth(ads.genSF:GetWidth())
  end
  if ads.tradeEdit and ads.tradeEdit.SetWidth and ads.tradeSF and ads.tradeSF.GetWidth then
    ads.tradeEdit:SetWidth(ads.tradeSF:GetWidth())
  end

  -- Button reflow: stack vertically if narrow (token row + preview don't fit on one line).
  -- Insert {guild}(110) + Insert {guildlink}(140) + Preview(80) + gaps(16) = ~346px
  local narrow1 = usable < 360

  -- General editor button row
  local genLastBtn = ads.genInsertGuild -- track the bottom-most button for tradeHdr anchor
  if ads.genInsertGuild and ads.genInsertLink and ads.genPreview then
    ads.genInsertLink:ClearAllPoints()
    ads.genPreview:ClearAllPoints()
    if narrow1 then
      ads.genInsertLink:SetPoint("TOPLEFT", ads.genInsertGuild, "BOTTOMLEFT", 0, -4)
      ads.genPreview:SetPoint("TOPLEFT", ads.genInsertLink, "BOTTOMLEFT", 0, -4)
      genLastBtn = ads.genPreview
    else
      ads.genInsertLink:SetPoint("LEFT", ads.genInsertGuild, "RIGHT", 8, 0)
      ads.genPreview:SetPoint("LEFT", ads.genInsertLink, "RIGHT", 8, 0)
      genLastBtn = ads.genInsertGuild -- all on same row; any button works
    end
  end

  -- Re-anchor Trade header below the General editor's last button row.
  if ads.tradeHdr and genLastBtn then
    ads.tradeHdr:ClearAllPoints()
    ads.tradeHdr:SetPoint("TOPLEFT", genLastBtn, "BOTTOMLEFT", 0, -12)
  end

  -- Trade editor button row
  local tradeLastBtn = ads.tradeInsertGuild
  if ads.tradeInsertGuild and ads.tradeInsertLink and ads.tradePreview then
    ads.tradeInsertLink:ClearAllPoints()
    ads.tradePreview:ClearAllPoints()
    if narrow1 then
      ads.tradeInsertLink:SetPoint("TOPLEFT", ads.tradeInsertGuild, "BOTTOMLEFT", 0, -4)
      ads.tradePreview:SetPoint("TOPLEFT", ads.tradeInsertLink, "BOTTOMLEFT", 0, -4)
      tradeLastBtn = ads.tradePreview
    else
      ads.tradeInsertLink:SetPoint("LEFT", ads.tradeInsertGuild, "RIGHT", 8, 0)
      ads.tradePreview:SetPoint("LEFT", ads.tradeInsertLink, "RIGHT", 8, 0)
      tradeLastBtn = ads.tradeInsertGuild
    end
  end

  -- Re-anchor Save row below the Trade editor's last button row.
  if ads.save and tradeLastBtn then
    ads.save:ClearAllPoints()
    ads.save:SetPoint("TOPLEFT", tradeLastBtn, "BOTTOMLEFT", 0, -10)
  end

  -- Bottom action row: Save + Queue Now + Post Next
  -- Save(70) + Queue Now(90) + Post Next(90) + gaps(16) = ~266px
  local narrow2 = usable < 280
  if ads.save and ads.queueNow and ads.postNext then
    ads.queueNow:ClearAllPoints()
    ads.postNext:ClearAllPoints()
    if narrow2 then
      ads.queueNow:SetPoint("TOPLEFT", ads.save, "BOTTOMLEFT", 0, -6)
      ads.postNext:SetPoint("TOPLEFT", ads.queueNow, "BOTTOMLEFT", 0, -6)
    else
      ads.queueNow:SetPoint("LEFT", ads.save, "RIGHT", 8, 0)
      ads.postNext:SetPoint("LEFT", ads.queueNow, "RIGHT", 8, 0)
    end
  end

  UpdateScrollChildHeight(ads)
end

-- ---------------------------------------------------------------------------
-- Create
-- ---------------------------------------------------------------------------
function GRIP:UI_CreateAds(parent)
  local ads = CreateFrame("Frame", nil, parent)
  ads:SetAllPoints(true)

  ads.scroll, ads.content = W.CreateScrollPage(ads)
  local a = ads.content

  ads.title = a:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ads.title:SetPoint("TOPLEFT", a, "TOPLEFT", PAD_L, -2)
  ads.title:SetText("Advertisement Config")

  ads.enabled = W.CreateCheckbox(a, "Enable scheduler (queues messages every interval)", function(btn)
    local cfg = GetCfg()
    if not cfg then
      GRIP:Print("Ads settings unavailable yet (DB not initialized).")
      btn:SetChecked(false)
      return
    end
    cfg.postEnabled = btn:GetChecked() and true or false
    GRIP:Print("Post scheduler: " .. (cfg.postEnabled and "ON" or "OFF"))
    GRIP:StartPostScheduler()
    GRIP:UpdateUI()
  end)
  ads.enabled:SetPoint("TOPLEFT", a, "TOPLEFT", PAD_L, -24)

  ads.intLbl, ads.intEdit = W.CreateLabeledEdit(a, "Interval (minutes)", 70)
  ads.intLbl:SetPoint("TOPLEFT", ads.enabled, "BOTTOMLEFT", 0, -10)
  ads.intEdit:SetPoint("LEFT", ads.intLbl, "RIGHT", 8, 0)

  ads.apply = W.CreateUIButton(a, "Apply", 70, 20, function()
    local cfg = GetCfg()
    if not cfg then
      GRIP:Print("Ads settings unavailable yet (DB not initialized).")
      return
    end

    ads.intEdit:ClearFocus()
    local n = tonumber(ads.intEdit:GetText())
    if not n then
      GRIP:Print("Interval must be a number.")
      return
    end
    cfg.postIntervalMinutes = GRIP:Clamp(n, 1, 180)
    ClearDirty(ads.intEdit)
    GRIP:Print("Post interval set to " .. cfg.postIntervalMinutes .. " minutes.")
    GRIP:StartPostScheduler()
    GRIP:UpdateUI()
  end)
  ads.apply:SetPoint("TOPLEFT", ads.intLbl, "BOTTOMLEFT", 0, -8)

  -- =======================================================================
  -- General message editor
  -- =======================================================================
  ads.generalHdr = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ads.generalHdr:SetPoint("TOPLEFT", ads.apply, "BOTTOMLEFT", 0, -12)
  ads.generalHdr:SetText("General message (supports {guild} {guildlink})")

  ads.genSF, ads.genEdit = W.CreateMultilineEdit(a, 1, 70)
  ads.genSF:ClearAllPoints()
  ads.genSF:SetPoint("TOPLEFT", ads.generalHdr, "BOTTOMLEFT", 0, -6)
  ads.genSF:SetPoint("TOPRIGHT", a, "TOPRIGHT", -PAD_R, 0)

  -- Remaining-bytes counter (bottom-right of editor).
  ads.genRemaining = ads.genSF:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ads.genRemaining:SetPoint("BOTTOMRIGHT", ads.genSF, "BOTTOMRIGHT", -6, 6)
  ads.genRemaining:SetText("")

  -- Budget enforcement on user edits.
  if ads.genEdit and ads.genEdit.SetScript then
    ads.genEdit:SetScript("OnTextChanged", function(eb, user)
      if eb._gripProgrammatic then return end
      if not HasCfg() then return end
      ads.genEdit._gripDirty = true
      if user then
        EnforceChannelBudget(ads, eb, "gen")
      else
        UpdateEditorBudgetUI(ads, "gen")
        UpdateBudgetControls(ads)
      end
    end)
  end

  -- Per-editor token buttons + Preview.
  ads.genInsertGuild = W.CreateUIButton(a, "Insert {guild}", 110, 20, function()
    if not HasCfg() then GRIP:Print("Ads settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursor(ads, ads.genEdit, "{guild}", "gen")
    if not ok then
      GRIP:Print("No room to insert {guild} (max 255 after expansion).")
    end
  end)
  ads.genInsertGuild:SetPoint("TOPLEFT", ads.genSF, "BOTTOMLEFT", 0, -6)

  ads.genInsertLink = W.CreateUIButton(a, "Insert {guildlink}", 140, 20, function()
    if not HasCfg() then GRIP:Print("Ads settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursor(ads, ads.genEdit, "{guildlink}", "gen")
    if not ok then
      GRIP:Print("No room to insert {guildlink} (max 255 after expansion).")
    end
  end)
  ads.genInsertLink:SetPoint("LEFT", ads.genInsertGuild, "RIGHT", 8, 0)

  ads.genPreview = W.CreateUIButton(a, "Preview", 80, 20, function()
    if not HasCfg() then GRIP:Print("Ads settings unavailable yet (DB not initialized).") return end
    UpdateEditorBudgetUI(ads, "gen")
    local bytes = EstimateChannelRenderedBytes(ads.genEdit:GetText() or "")
    if bytes > MAX_CHANNEL_BYTES then
      GRIP:Print("General message is too long after token expansion (max 255).")
      return
    end
    local msg = GRIP:ApplyTemplate(ads.genEdit:GetText() or "", nil)
    GRIP:Print("General preview: " .. msg)
  end)
  ads.genPreview:SetPoint("LEFT", ads.genInsertLink, "RIGHT", 8, 0)

  -- =======================================================================
  -- Trade message editor
  -- =======================================================================
  ads.tradeHdr = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ads.tradeHdr:SetPoint("TOPLEFT", ads.genInsertGuild, "BOTTOMLEFT", 0, -12)
  ads.tradeHdr:SetText("Trade message (supports {guild} {guildlink})")

  ads.tradeSF, ads.tradeEdit = W.CreateMultilineEdit(a, 1, 70)
  ads.tradeSF:ClearAllPoints()
  ads.tradeSF:SetPoint("TOPLEFT", ads.tradeHdr, "BOTTOMLEFT", 0, -6)
  ads.tradeSF:SetPoint("TOPRIGHT", a, "TOPRIGHT", -PAD_R, 0)

  -- Remaining-bytes counter (bottom-right of editor).
  ads.tradeRemaining = ads.tradeSF:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ads.tradeRemaining:SetPoint("BOTTOMRIGHT", ads.tradeSF, "BOTTOMRIGHT", -6, 6)
  ads.tradeRemaining:SetText("")

  -- Budget enforcement on user edits.
  if ads.tradeEdit and ads.tradeEdit.SetScript then
    ads.tradeEdit:SetScript("OnTextChanged", function(eb, user)
      if eb._gripProgrammatic then return end
      if not HasCfg() then return end
      ads.tradeEdit._gripDirty = true
      if user then
        EnforceChannelBudget(ads, eb, "trade")
      else
        UpdateEditorBudgetUI(ads, "trade")
        UpdateBudgetControls(ads)
      end
    end)
  end

  -- Per-editor token buttons + Preview.
  ads.tradeInsertGuild = W.CreateUIButton(a, "Insert {guild}", 110, 20, function()
    if not HasCfg() then GRIP:Print("Ads settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursor(ads, ads.tradeEdit, "{guild}", "trade")
    if not ok then
      GRIP:Print("No room to insert {guild} (max 255 after expansion).")
    end
  end)
  ads.tradeInsertGuild:SetPoint("TOPLEFT", ads.tradeSF, "BOTTOMLEFT", 0, -6)

  ads.tradeInsertLink = W.CreateUIButton(a, "Insert {guildlink}", 140, 20, function()
    if not HasCfg() then GRIP:Print("Ads settings unavailable yet (DB not initialized).") return end
    local ok = TryInsertTokenAtCursor(ads, ads.tradeEdit, "{guildlink}", "trade")
    if not ok then
      GRIP:Print("No room to insert {guildlink} (max 255 after expansion).")
    end
  end)
  ads.tradeInsertLink:SetPoint("LEFT", ads.tradeInsertGuild, "RIGHT", 8, 0)

  ads.tradePreview = W.CreateUIButton(a, "Preview", 80, 20, function()
    if not HasCfg() then GRIP:Print("Ads settings unavailable yet (DB not initialized).") return end
    UpdateEditorBudgetUI(ads, "trade")
    local bytes = EstimateChannelRenderedBytes(ads.tradeEdit:GetText() or "")
    if bytes > MAX_CHANNEL_BYTES then
      GRIP:Print("Trade message is too long after token expansion (max 255).")
      return
    end
    local msg = GRIP:ApplyTemplate(ads.tradeEdit:GetText() or "", nil)
    GRIP:Print("Trade preview: " .. msg)
  end)
  ads.tradePreview:SetPoint("LEFT", ads.tradeInsertLink, "RIGHT", 8, 0)

  -- =======================================================================
  -- Bottom row: Save (both editors) + Queue + Post
  -- =======================================================================
  ads.save = W.CreateUIButton(a, "Save", 70, 20, function()
    local cfg = GetCfg()
    if not cfg then
      GRIP:Print("Ads settings unavailable yet (DB not initialized).")
      return
    end

    -- Final budget check before saving.
    local genBytes = EstimateChannelRenderedBytes(ads.genEdit:GetText() or "")
    local tradeBytes = EstimateChannelRenderedBytes(ads.tradeEdit:GetText() or "")
    if genBytes > MAX_CHANNEL_BYTES or tradeBytes > MAX_CHANNEL_BYTES then
      GRIP:Print("One or both messages exceed 255 bytes after token expansion. Please shorten them first.")
      return
    end

    ads.genEdit:ClearFocus()
    ads.tradeEdit:ClearFocus()
    cfg.postMessageGeneral = ads.genEdit:GetText() or cfg.postMessageGeneral
    cfg.postMessageTrade = ads.tradeEdit:GetText() or cfg.postMessageTrade
    ClearDirty(ads.genEdit, ads.tradeEdit)
    GRIP:Print("Ad messages saved.")
    GRIP:UpdateUI()
  end)
  ads.save:SetPoint("TOPLEFT", ads.tradeInsertGuild, "BOTTOMLEFT", 0, -10)

  ads.queueNow = W.CreateUIButton(a, "Queue Now", 90, 20, function()
    if not HasCfg() then
      GRIP:Print("Ads settings unavailable yet (DB not initialized).")
      return
    end
    GRIP:QueuePostCycle("manual-ui")
    GRIP:Print("Queued one General + one Trade message. Use Post Next to send.")
    GRIP:UpdateUI()
  end)
  ads.queueNow:SetPoint("LEFT", ads.save, "RIGHT", 8, 0)

  ads.postNext = W.CreateUIButton(a, "Post Next", 90, 20, function()
    if not HasCfg() then
      GRIP:Print("Ads settings unavailable yet (DB not initialized).")
      return
    end

    -- Small UI-local cooldown to discourage spam clicking (posting module still enforces minPostInterval).
    if state.ui then
      local left = SecondsLeft(state.ui._postCooldownUntil)
      if left > 0 then
        GRIP:Print(("Please wait %.1fs before posting again."):format(left))
        GRIP:UpdateUI()
        return
      end
    end

    GRIP:PostNext()
    if state.ui then
      state.ui._postCooldownUntil = GetTime() + 0.5
    end
    GRIP:UpdateUI()
  end)
  ads.postNext:SetPoint("LEFT", ads.queueNow, "RIGHT", 8, 0)

  -- Initial sizing pass (helps first render before the next resize tick)
  if GRIP and GRIP.UI_LayoutAds then
    pcall(GRIP.UI_LayoutAds, GRIP)
  end

  UpdateScrollChildHeight(ads)
  return ads
end

-- ---------------------------------------------------------------------------
-- Update (called from GRIP:UpdateUI on every refresh cycle)
-- ---------------------------------------------------------------------------
function GRIP:UI_UpdateAds()
  if not state.ui or not state.ui.ads or not state.ui.ads:IsShown() then return end
  local a = state.ui.ads

  local cfg = GetCfg()
  if not cfg then
    LockUI(a, "Initializing\226\128\166 (database not ready yet)")
    return
  end

  UnlockUI(a)

  -- Keep layout current (cheap + makes first show consistent)
  if GRIP and GRIP.UI_LayoutAds then
    pcall(GRIP.UI_LayoutAds, GRIP)
  end

  a.enabled:SetChecked(cfg.postEnabled and true or false)
  W.SetTextIfUnfocused(a.intEdit, tostring(cfg.postIntervalMinutes or 15))
  W.SetTextIfUnfocused(a.genEdit, cfg.postMessageGeneral or "")
  W.SetTextIfUnfocused(a.tradeEdit, cfg.postMessageTrade or "")

  -- Enforce + refresh budget counters and button states.
  EnforceChannelBudget(a, a.genEdit, "gen")
  EnforceChannelBudget(a, a.tradeEdit, "trade")

  -- Reflect UI-local post cooldown in the button state + label (optional polish).
  local left = SecondsLeft(state.ui and state.ui._postCooldownUntil or 0)
  if left > 0 then
    a.postNext:Disable()
    a.postNext:SetText(("Post (%.0fs)"):format(math.ceil(left)))
  else
    a.postNext:Enable()
    a.postNext:SetText("Post Next")
  end

  -- Clear remaining counters if editors are empty (visual polish).
  if a.genRemaining and (a.genEdit:GetText() or "") == "" then
    a.genRemaining:SetText("")
  end
  if a.tradeRemaining and (a.tradeEdit:GetText() or "") == "" then
    a.tradeRemaining:SetText("")
  end

  UpdateScrollChildHeight(a)
end
