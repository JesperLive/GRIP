-- GRIP: UI Ads Page
-- Trade/General message editors, post scheduler config, queue/post buttons.

local ADDON_NAME, GRIP = ...

-- Lua
local tostring, tonumber = tostring, tonumber
local pcall = pcall

-- WoW API
local GetTime = GetTime

local state = GRIP.state
local W = GRIP.UIW
local L = LibStub("AceLocale-3.0"):GetLocale("GRIP")

local MAX_CHANNEL_BYTES = 255

local PAD_L = 4
local PAD_R = 24 -- leave room from the right edge inside scroll content

local function HasCfg()
  return (_G.GRIPDB_CHAR and GRIPDB_CHAR.config) and true or false
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
  if GRIP:IsBlank(link) then
    link = inGuild and guildName or "your guild"
  end

  local out = rawText
  -- Replace {guildlink} BEFORE {guild} — {guild} is a substring of {guildlink}.
  out = out:gsub("{guildlink}", link)
  out = out:gsub("{guild}", guildName)
  out = GRIP:SanitizeOneLine(out)
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

  W.SetEnabledSafe(ads.save, genOk and tradeOk)
  W.SetEnabledSafe(ads.genPreview, genOk)
  W.SetEnabledSafe(ads.tradePreview, tradeOk)
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

  local trimmed = GRIP:TrimToBudget(txt, MAX_CHANNEL_BYTES, EstimateChannelRenderedBytes)

  W.ProgrammaticSet(eb, trimmed)
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

-- All-or-nothing token insert: if the expanded output would exceed budget, do nothing.
local function TryInsertTokenAtCursor(ads, eb, token, editKey)
  if not ads or not eb then return false end
  if not HasCfg() then return false end

  local candidate, newCursor = W.BuildInsertedTextAtCursor(eb, token)
  if not candidate then return false end

  if EstimateChannelRenderedBytes(candidate) > MAX_CHANNEL_BYTES then
    eb:SetFocus()
    UpdateEditorBudgetUI(ads, editKey)
    UpdateBudgetControls(ads)
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
      a._initHint:SetText(L["Initializing… (database not ready yet)"])
    end
  elseif a.content then
    a._initHint = a.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    a._initHint:SetPoint("TOPLEFT", a.title, "BOTTOMLEFT", 0, -4)
    a._initHint:SetText((why and why ~= "") and tostring(why) or L["Initializing… (database not ready yet)"])
    a._initHint:Show()
  end

  W.SetEnabledSafe(a.enabled, false)
  W.SetEnabledSafe(a.intEdit, false)
  W.SetEnabledSafe(a.apply, false)
  W.SetEnabledSafe(a.genEdit, false)
  W.SetEnabledSafe(a.tradeEdit, false)
  W.SetEnabledSafe(a.genInsertGuild, false)
  W.SetEnabledSafe(a.genInsertLink, false)
  W.SetEnabledSafe(a.genPreview, false)
  W.SetEnabledSafe(a.tradeInsertGuild, false)
  W.SetEnabledSafe(a.tradeInsertLink, false)
  W.SetEnabledSafe(a.tradePreview, false)
  W.SetEnabledSafe(a.save, false)
  W.SetEnabledSafe(a.queueNow, false)
  W.SetEnabledSafe(a.postNext, false)
end

local function UnlockUI(a)
  if not a then return end
  if a._initHint then a._initHint:Hide() end

  W.SetEnabledSafe(a.enabled, true)
  W.SetEnabledSafe(a.intEdit, true)
  W.SetEnabledSafe(a.apply, true)
  W.SetEnabledSafe(a.genEdit, true)
  W.SetEnabledSafe(a.tradeEdit, true)
  W.SetEnabledSafe(a.genInsertGuild, true)
  W.SetEnabledSafe(a.genInsertLink, true)
  W.SetEnabledSafe(a.genPreview, true)
  W.SetEnabledSafe(a.tradeInsertGuild, true)
  W.SetEnabledSafe(a.tradeInsertLink, true)
  W.SetEnabledSafe(a.tradePreview, true)
  W.SetEnabledSafe(a.save, true)
  W.SetEnabledSafe(a.queueNow, true)
  W.SetEnabledSafe(a.postNext, true)
end

-- ---------------------------------------------------------------------------
-- Scroll child height tracking
-- ---------------------------------------------------------------------------
local function UpdateScrollChildHeight(ads)
  if not ads or not ads.content then return end
  local a = ads.content
  local top = W.SafeTop(a)
  if not top then return end

  local lowest = nil
  local function consider(f)
    if not f or (f.IsShown and not f:IsShown()) then return end
    local b = W.SafeBottom(f)
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

  -- Re-anchor separator + Trade header below the General editor's last button row.
  if ads.sep2 and genLastBtn then
    ads.sep2:ClearAllPoints()
    ads.sep2:SetPoint("TOPLEFT", genLastBtn, "BOTTOMLEFT", 0, -6)
    ads.sep2:SetPoint("RIGHT", ads.content, "RIGHT", -PAD_R, 0)
  end
  if ads.tradeHdr then
    ads.tradeHdr:ClearAllPoints()
    ads.tradeHdr:SetPoint("TOPLEFT", ads.sep2 or genLastBtn, "BOTTOMLEFT", 0, -6)
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

  -- Re-anchor separator + Save row below the Trade editor's last button row.
  if ads.sep3 and tradeLastBtn then
    ads.sep3:ClearAllPoints()
    ads.sep3:SetPoint("TOPLEFT", tradeLastBtn, "BOTTOMLEFT", 0, -4)
    ads.sep3:SetPoint("RIGHT", ads.content, "RIGHT", -PAD_R, 0)
  end
  if ads.save then
    ads.save:ClearAllPoints()
    ads.save:SetPoint("TOPLEFT", ads.sep3 or tradeLastBtn, "BOTTOMLEFT", 0, -6)
  end

  -- Bottom action row: Save + Refill Queue + Send Next Post
  -- Save(70) + Refill Queue(100) + Send Next Post(110) + gaps(16) = ~296px
  local narrow2 = usable < 310
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
  ads.title:SetText(L["Recruitment Posts"])

  ads.enabled = W.CreateCheckbox(a, L["Enable scheduler (queues messages every interval)"], function(btn)
    local cfg = GRIP:GetCfg()
    if not cfg then
      GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."])
      btn:SetChecked(false)
      return
    end
    cfg.postEnabled = btn:GetChecked() and true or false
    GRIP:Print((L["Post scheduler: %s"]):format(cfg.postEnabled and L["ON"] or L["OFF"]))
    GRIP:StartPostScheduler()
    GRIP:UpdateUI()
  end)
  ads.enabled:SetPoint("TOPLEFT", a, "TOPLEFT", PAD_L, -24)

  ads.intLbl, ads.intEdit = W.CreateLabeledEdit(a, L["Interval (minutes)"], 70)
  ads.intLbl:SetPoint("TOPLEFT", ads.enabled, "BOTTOMLEFT", 0, -10)
  ads.intEdit:SetPoint("LEFT", ads.intLbl, "RIGHT", 8, 0)

  ads.apply = W.CreateUIButton(a, L["Apply"], 70, 20, function()
    local cfg = GRIP:GetCfg()
    if not cfg then
      GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."])
      return
    end

    ads.intEdit:ClearFocus()
    local n = tonumber(ads.intEdit:GetText())
    if not n then
      GRIP:Print(L["Interval must be a number."])
      return
    end
    cfg.postIntervalMinutes = GRIP:Clamp(n, 1, 180)
    W.ClearDirty(ads.intEdit)
    GRIP:Print((L["Post interval set to %d minutes."]):format(cfg.postIntervalMinutes))
    GRIP:StartPostScheduler()
    GRIP:UpdateUI()
  end)
  ads.apply:SetPoint("TOPLEFT", ads.intLbl, "BOTTOMLEFT", 0, -8)
  GRIP:AttachTooltip(ads.enabled, L["Enable Scheduler"],
      L["Automatically queues one General + one Trade post\nevery interval. Posts still require a hardware event to send."]) -- luacheck: ignore 631
  GRIP:AttachTooltip(ads.apply, L["Apply Interval"], L["Save the post interval."])

  -- Separator: enable/interval → General editor
  ads.sep1 = a:CreateTexture(nil, "ARTWORK")
  ads.sep1:SetHeight(1)
  ads.sep1:SetPoint("TOPLEFT", ads.apply, "BOTTOMLEFT", 0, -6)
  ads.sep1:SetPoint("RIGHT", a, "RIGHT", -PAD_R, 0)
  ads.sep1:SetColorTexture(1, 1, 1, 0.08)

  -- =======================================================================
  -- General message editor
  -- =======================================================================
  ads.generalHdr = a:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ads.generalHdr:SetPoint("TOPLEFT", ads.sep1, "BOTTOMLEFT", 0, -6)
  ads.generalHdr:SetText(L["General message (supports {guild} {guildlink})"])

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
  ads.genInsertGuild = W.CreateUIButton(a, L["Insert {guild}"], 110, 20, function()
    if not HasCfg() then GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."]) return end
    local ok = TryInsertTokenAtCursor(ads, ads.genEdit, "{guild}", "gen")
    if not ok then
      GRIP:Print(L["No room to insert {guild} (max 255 after expansion)."])
    end
  end)
  ads.genInsertGuild:SetPoint("TOPLEFT", ads.genSF, "BOTTOMLEFT", 0, -6)
  GRIP:AttachTooltip(ads.genInsertGuild, L["Insert {guild}"], L["Inserts your guild name at cursor."])

  ads.genInsertLink = W.CreateUIButton(a, L["Insert {guildlink}"], 140, 20, function()
    if not HasCfg() then GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."]) return end
    local ok = TryInsertTokenAtCursor(ads, ads.genEdit, "{guildlink}", "gen")
    if not ok then
      GRIP:Print(L["No room to insert {guildlink} (max 255 after expansion)."])
    end
  end)
  ads.genInsertLink:SetPoint("LEFT", ads.genInsertGuild, "RIGHT", 8, 0)
  GRIP:AttachTooltip(ads.genInsertLink, L["Insert {guildlink}"], L["Inserts a clickable Guild Finder link at cursor."])

  ads.genPreview = W.CreateUIButton(a, L["Preview"], 80, 20, function()
    if not HasCfg() then GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."]) return end
    UpdateEditorBudgetUI(ads, "gen")
    local bytes = EstimateChannelRenderedBytes(ads.genEdit:GetText() or "")
    if bytes > MAX_CHANNEL_BYTES then
      GRIP:Print(L["General message is too long after token expansion (max 255)."])
      return
    end
    local msg = GRIP:ApplyTemplate(ads.genEdit:GetText() or "", nil)
    GRIP:Print((L["General preview: %s"]):format(msg))
  end)
  ads.genPreview:SetPoint("LEFT", ads.genInsertLink, "RIGHT", 8, 0)
  GRIP:AttachTooltip(ads.genPreview, L["Preview"], L["Expands tokens and prints the message to chat."])

  -- Separator: General editor → Trade editor
  ads.sep2 = a:CreateTexture(nil, "ARTWORK")
  ads.sep2:SetHeight(1)
  ads.sep2:SetPoint("TOPLEFT", ads.genInsertGuild, "BOTTOMLEFT", 0, -6)
  ads.sep2:SetPoint("RIGHT", a, "RIGHT", -PAD_R, 0)
  ads.sep2:SetColorTexture(1, 1, 1, 0.08)

  -- =======================================================================
  -- Trade message editor
  -- =======================================================================
  ads.tradeHdr = a:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ads.tradeHdr:SetPoint("TOPLEFT", ads.sep2, "BOTTOMLEFT", 0, -6)
  ads.tradeHdr:SetText(L["Trade message (supports {guild} {guildlink})"])

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
  ads.tradeInsertGuild = W.CreateUIButton(a, L["Insert {guild}"], 110, 20, function()
    if not HasCfg() then GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."]) return end
    local ok = TryInsertTokenAtCursor(ads, ads.tradeEdit, "{guild}", "trade")
    if not ok then
      GRIP:Print(L["No room to insert {guild} (max 255 after expansion)."])
    end
  end)
  ads.tradeInsertGuild:SetPoint("TOPLEFT", ads.tradeSF, "BOTTOMLEFT", 0, -6)
  GRIP:AttachTooltip(ads.tradeInsertGuild, L["Insert {guild}"], L["Inserts your guild name at cursor."])

  ads.tradeInsertLink = W.CreateUIButton(a, L["Insert {guildlink}"], 140, 20, function()
    if not HasCfg() then GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."]) return end
    local ok = TryInsertTokenAtCursor(ads, ads.tradeEdit, "{guildlink}", "trade")
    if not ok then
      GRIP:Print(L["No room to insert {guildlink} (max 255 after expansion)."])
    end
  end)
  ads.tradeInsertLink:SetPoint("LEFT", ads.tradeInsertGuild, "RIGHT", 8, 0)
  GRIP:AttachTooltip(ads.tradeInsertLink, L["Insert {guildlink}"],
      L["Inserts a clickable Guild Finder link at cursor."])

  ads.tradePreview = W.CreateUIButton(a, L["Preview"], 80, 20, function()
    if not HasCfg() then GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."]) return end
    UpdateEditorBudgetUI(ads, "trade")
    local bytes = EstimateChannelRenderedBytes(ads.tradeEdit:GetText() or "")
    if bytes > MAX_CHANNEL_BYTES then
      GRIP:Print(L["Trade message is too long after token expansion (max 255)."])
      return
    end
    local msg = GRIP:ApplyTemplate(ads.tradeEdit:GetText() or "", nil)
    GRIP:Print((L["Trade preview: %s"]):format(msg))
  end)
  ads.tradePreview:SetPoint("LEFT", ads.tradeInsertLink, "RIGHT", 8, 0)
  GRIP:AttachTooltip(ads.tradePreview, L["Preview"], L["Expands tokens and prints the message to chat."])

  -- Separator: Trade editor → bottom action row
  ads.sep3 = a:CreateTexture(nil, "ARTWORK")
  ads.sep3:SetHeight(1)
  ads.sep3:SetPoint("TOPLEFT", ads.tradeInsertGuild, "BOTTOMLEFT", 0, -4)
  ads.sep3:SetPoint("RIGHT", a, "RIGHT", -PAD_R, 0)
  ads.sep3:SetColorTexture(1, 1, 1, 0.08)

  -- =======================================================================
  -- Bottom row: Save (both editors) + Queue + Post
  -- =======================================================================
  ads.save = W.CreateUIButton(a, L["Save"], 70, 20, function()
    local cfg = GRIP:GetCfg()
    if not cfg then
      GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."])
      return
    end

    -- Final budget check before saving.
    local genBytes = EstimateChannelRenderedBytes(ads.genEdit:GetText() or "")
    local tradeBytes = EstimateChannelRenderedBytes(ads.tradeEdit:GetText() or "")
    if genBytes > MAX_CHANNEL_BYTES or tradeBytes > MAX_CHANNEL_BYTES then
      GRIP:Print(L["One or both messages exceed 255 bytes after token expansion. Please shorten them first."])
      return
    end

    ads.genEdit:ClearFocus()
    ads.tradeEdit:ClearFocus()
    cfg.postMessageGeneral = ads.genEdit:GetText() or cfg.postMessageGeneral
    cfg.postMessageTrade = ads.tradeEdit:GetText() or cfg.postMessageTrade
    W.ClearDirty(ads.genEdit, ads.tradeEdit)
    GRIP:Print(L["Ad messages saved."])
    GRIP:UpdateUI()
  end)
  ads.save:SetPoint("TOPLEFT", ads.sep3, "BOTTOMLEFT", 0, -6)
  GRIP:AttachTooltip(ads.save, L["Save"], L["Save both General and Trade messages to SavedVariables."])

  ads.queueNow = W.CreateUIButton(a, L["Refill Queue"], 100, 20, function()
    if not HasCfg() then
      GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."])
      return
    end
    GRIP:QueuePostCycle("manual-ui")
    GRIP:Print(L["Queued one General + one Trade message. Use Send Next Post to send."])
    GRIP:UpdateUI()
  end)
  ads.queueNow:SetPoint("LEFT", ads.save, "RIGHT", 8, 0)
  GRIP:AttachTooltip(ads.queueNow, L["Refill Queue"],
      L["Immediately queues one General + one Trade post.\nUse Send Next Post to send them."])

  ads.postNext = W.CreateUIButton(a, L["Send Next Post"], 110, 20, function()
    if not HasCfg() then
      GRIP:Print(L["Ads settings unavailable yet (DB not initialized)."])
      return
    end

    -- Small UI-local cooldown to discourage spam clicking (posting module still enforces minPostInterval).
    if state.ui then
      local left = GRIP:SecondsLeft(state.ui._postCooldownUntil)
      if left > 0 then
        GRIP:Print((L["Please wait %.1fs before posting again."]):format(left))
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
  GRIP:AttachTooltip(ads.postNext, L["Send Next Post"],
      L["Sends the next queued channel post.\nRequires a keybind or button click (hardware event)."])

  -- Button accent underlines
  W.AddButtonAccent(ads.apply, 1, 0.82, 0)
  W.AddButtonAccent(ads.save, 1, 0.82, 0)
  W.AddButtonAccent(ads.queueNow, 1, 0.82, 0)
  W.AddButtonAccent(ads.postNext, 1, 0.82, 0)

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

  local cfg = GRIP:GetCfg()
  if not cfg then
    LockUI(a, L["Initializing… (database not ready yet)"])
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
  local left = GRIP:SecondsLeft(state.ui and state.ui._postCooldownUntil or 0)
  if left > 0 then
    a.postNext:Disable()
    a.postNext:SetText((L["Post (%.0fs)"]):format(math.ceil(left)))
  else
    a.postNext:Enable()
    a.postNext:SetText(L["Send Next Post"])
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
