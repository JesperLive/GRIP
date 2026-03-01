-- Rev 5
-- GRIP – UI: Ads page
--
-- Changed (Rev 2):
-- - Add GRIPDB/config nil-safety guards (avoid edge-case errors if UI is opened before EnsureDB()).
-- - Disable controls gracefully until config is available.
-- - Mirror a short UI-local post cooldown after "Post Next" to reduce spam-clicking.
--
-- CHANGED (Rev 3):
-- - Use the same “Initializing…” hint + lock/unlock pattern as UI_Settings.lua (less UI churn than retitling).
-- - Harden all callbacks consistently (early-return when DB/config missing).
-- - Add a small optional polish: Post Next button shows a countdown label during UI-local cooldown.
--
-- CHANGED (Rev 4):
-- - Make layout responsive to the resizable main frame (no hard-coded 512px editor widths).
-- - Add GRIP:UI_LayoutAds() hook used by UI.lua on resize/tab switch.
-- - Avoid horizontal button overlap on narrow widths by splitting actions into two rows.
-- - Move "Apply" to its own row to prevent overlap in smaller window sizes.
--
-- CHANGED (Rev 5):
-- - Anchor multiline editors to both LEFT and RIGHT edges (natural resize, less width micromanagement).
-- - Add narrow-width button reflow (stack Save/Post Next under their left partner when needed).
-- - Auto-size scroll child height from content (prevents clipping at the bottom on various window sizes).

local ADDON_NAME, GRIP = ...
local state = GRIP.state
local W = GRIP.UIW

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

local function AppendToken(eb, token)
  if not eb then return end
  local t = eb:GetText() or ""
  if t:find(token, 1, true) then return end

  t = (t:gsub("%s+$", "")) .. " " .. token
  ProgrammaticSet(eb, t)
  eb._gripDirty = true

  eb:SetFocus()
  if eb.SetCursorPosition then
    eb:SetCursorPosition(#t)
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

  if widget.SetAlpha then
    widget:SetAlpha(enabled and 1 or 0.6)
  end
end

local function SecondsLeft(untilT)
  local now = GetTime()
  local left = (untilT or 0) - now
  if left < 0 then left = 0 end
  return left
end

local function LockUI(a, why)
  if not a then return end

  if a._initHint then
    a._initHint:Show()
    if why and why ~= "" then
      a._initHint:SetText(tostring(why))
    else
      a._initHint:SetText("Initializing… (database not ready yet)")
    end
  elseif a.content then
    a._initHint = a.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    a._initHint:SetPoint("TOPLEFT", a.title, "BOTTOMLEFT", 0, -4)
    a._initHint:SetText((why and why ~= "") and tostring(why) or "Initializing… (database not ready yet)")
    a._initHint:Show()
  end

  SetEnabledSafe(a.enabled, false)
  SetEnabledSafe(a.intEdit, false)
  SetEnabledSafe(a.apply, false)
  SetEnabledSafe(a.genEdit, false)
  SetEnabledSafe(a.tradeEdit, false)
  SetEnabledSafe(a.appendLink, false)
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
  SetEnabledSafe(a.appendLink, true)
  SetEnabledSafe(a.save, true)
  SetEnabledSafe(a.queueNow, true)
  SetEnabledSafe(a.postNext, true)
end

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
  consider(ads.appendLink)
  consider(ads.tradeSF)
  consider(ads.tradeHdr)
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

-- Responsive layout hook (called by UI.lua on size changes/tab switch)
function GRIP:UI_LayoutAds()
  if not state.ui or not state.ui.ads then return end
  local ads = state.ui.ads
  if not ads.content then return end

  local a = ads.content
  local w = tonumber(a:GetWidth()) or 0
  if w <= 0 then return end

  local usable = w - PAD_L - PAD_R
  if usable < 200 then usable = 200 end

  -- Ensure multiline editors stretch with the content width.
  -- (Primary sizing is via TOPLEFT+TOPRIGHT anchors; width mirroring helps internal edit wrapping.)
  if ads.genSF and ads.genSF.SetWidth then ads.genSF:SetWidth(usable) end
  if ads.tradeSF and ads.tradeSF.SetWidth then ads.tradeSF:SetWidth(usable) end

  if ads.genEdit and ads.genEdit.SetWidth and ads.genSF and ads.genSF.GetWidth then
    ads.genEdit:SetWidth(ads.genSF:GetWidth())
  end
  if ads.tradeEdit and ads.tradeEdit.SetWidth and ads.tradeSF and ads.tradeSF.GetWidth then
    ads.tradeEdit:SetWidth(ads.tradeSF:GetWidth())
  end

  -- Button reflow for narrow widths: stack the right-hand button under the left.
  local narrow1 = usable < 260

  if ads.appendLink and ads.save then
    ads.save:ClearAllPoints()
    if narrow1 then
      ads.save:SetPoint("TOPLEFT", ads.appendLink, "BOTTOMLEFT", 0, -6)
    else
      ads.save:SetPoint("LEFT", ads.appendLink, "RIGHT", 8, 0)
    end
  end

  if ads.queueNow and ads.postNext then
    ads.postNext:ClearAllPoints()
    if narrow1 then
      ads.postNext:SetPoint("TOPLEFT", ads.queueNow, "BOTTOMLEFT", 0, -6)
    else
      ads.postNext:SetPoint("LEFT", ads.queueNow, "RIGHT", 8, 0)
    end
  end

  UpdateScrollChildHeight(ads)
end

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

  -- Put Apply on its own row to avoid overlap on narrow widths.
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

  ads.generalHdr = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ads.generalHdr:SetPoint("TOPLEFT", ads.apply, "BOTTOMLEFT", 0, -12)
  ads.generalHdr:SetText("General message (supports {guild} {guildlink})")

  -- Create with a tiny initial width; anchors + UI_LayoutAds will size it properly.
  ads.genSF, ads.genEdit = W.CreateMultilineEdit(a, 1, 70)
  ads.genSF:ClearAllPoints()
  ads.genSF:SetPoint("TOPLEFT", ads.generalHdr, "BOTTOMLEFT", 0, -6)
  ads.genSF:SetPoint("TOPRIGHT", a, "TOPRIGHT", -PAD_R, 0)

  ads.tradeHdr = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ads.tradeHdr:SetPoint("TOPLEFT", ads.genSF, "BOTTOMLEFT", 0, -10)
  ads.tradeHdr:SetText("Trade message (supports {guild} {guildlink})")

  ads.tradeSF, ads.tradeEdit = W.CreateMultilineEdit(a, 1, 70)
  ads.tradeSF:ClearAllPoints()
  ads.tradeSF:SetPoint("TOPLEFT", ads.tradeHdr, "BOTTOMLEFT", 0, -6)
  ads.tradeSF:SetPoint("TOPRIGHT", a, "TOPRIGHT", -PAD_R, 0)

  -- Row 1: token + save
  ads.appendLink = W.CreateUIButton(a, "Append {guildlink}", 140, 20, function()
    if not HasCfg() then
      GRIP:Print("Ads settings unavailable yet (DB not initialized).")
      return
    end
    AppendToken(ads.genEdit, "{guildlink}")
    AppendToken(ads.tradeEdit, "{guildlink}")
  end)
  ads.appendLink:SetPoint("TOPLEFT", ads.tradeSF, "BOTTOMLEFT", 0, -6)

  ads.save = W.CreateUIButton(a, "Save", 70, 20, function()
    local cfg = GetCfg()
    if not cfg then
      GRIP:Print("Ads settings unavailable yet (DB not initialized).")
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
  ads.save:SetPoint("LEFT", ads.appendLink, "RIGHT", 8, 0)

  -- Row 2: queue + post (prevents button row overlap on narrow widths)
  ads.queueNow = W.CreateUIButton(a, "Queue Now", 90, 20, function()
    if not HasCfg() then
      GRIP:Print("Ads settings unavailable yet (DB not initialized).")
      return
    end
    GRIP:QueuePostCycle("manual-ui")
    GRIP:Print("Queued one General + one Trade message. Use Post Next to send.")
    GRIP:UpdateUI()
  end)
  ads.queueNow:SetPoint("TOPLEFT", ads.appendLink, "BOTTOMLEFT", 0, -6)

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

function GRIP:UI_UpdateAds()
  if not state.ui or not state.ui.ads or not state.ui.ads:IsShown() then return end
  local a = state.ui.ads

  local cfg = GetCfg()
  if not cfg then
    LockUI(a, "Initializing… (database not ready yet)")
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

  -- Reflect UI-local post cooldown in the button state + label (optional polish).
  local left = SecondsLeft(state.ui and state.ui._postCooldownUntil or 0)
  if left > 0 then
    a.postNext:Disable()
    a.postNext:SetText(("Post (%.0fs)"):format(math.ceil(left)))
  else
    a.postNext:Enable()
    a.postNext:SetText("Post Next")
  end

  UpdateScrollChildHeight(a)
end