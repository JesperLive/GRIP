-- GRIP: Stats Page
-- Recruitment statistics display with daily/weekly/monthly summaries and conversion rates.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring = type, tostring
local ipairs, pairs = ipairs, pairs
local format = string.format
local max = math.max

local L = LibStub("AceLocale-3.0"):GetLocale("GRIP")
local abs = math.abs

local W = GRIP.UIW

-- =========================================================================
-- Helpers
-- =========================================================================

local STAT_KEYS = { "whispers", "invites", "accepted", "declined", "optOuts", "posts", "scans" }
local STAT_LABELS = {
  whispers = L["Whispers"],
  invites  = L["Invites"],
  accepted = L["Accepted"],
  declined = L["Declined"],
  optOuts  = L["Opt-Outs"],
  posts    = L["Posts"],
  scans    = L["Scans"],
}

local function EmptyRow()
  local r = {}
  for _, k in ipairs(STAT_KEYS) do r[k] = 0 end
  return r
end

local function SumDays(days, n, today)
  local totals = EmptyRow()
  if not days or type(days) ~= "table" then
    -- Just today
    if today and type(today) == "table" then
      for _, k in ipairs(STAT_KEYS) do
        totals[k] = (today[k] or 0)
      end
    end
    return totals
  end

  -- Include today
  if today and type(today) == "table" then
    for _, k in ipairs(STAT_KEYS) do
      totals[k] = (today[k] or 0)
    end
  end

  -- Sum most recent n-1 entries from days array (today already counted above)
  local historyCount = n - 1
  local startIdx = max(1, #days - historyCount + 1)

  for i = startIdx, #days do
    local day = days[i]
    if day and type(day) == "table" then
      for _, k in ipairs(STAT_KEYS) do
        totals[k] = totals[k] + (day[k] or 0)
      end
    end
  end

  return totals
end

local function FormatRate(accepted, whispers)
  if not whispers or whispers == 0 then return L["N/A"] end
  return format("%.1f%%", (accepted / whispers) * 100)
end

local function FindPeakHour(days, n, today)
  local hourTotals = {}
  -- Sum today's hours
  if today and type(today) == "table" and type(today.hours) == "table" then
    for h, count in pairs(today.hours) do
      hourTotals[h] = (hourTotals[h] or 0) + count
    end
  end
  -- Sum history hours (last n-1 entries)
  if days and type(days) == "table" then
    local historyCount = n - 1
    local startIdx = max(1, #days - historyCount + 1)
    for i = startIdx, #days do
      local day = days[i]
      if day and type(day) == "table" and type(day.hours) == "table" then
        for h, count in pairs(day.hours) do
          hourTotals[h] = (hourTotals[h] or 0) + count
        end
      end
    end
  end
  -- Find peak
  local peakHour, peakCount = nil, 0
  for h, count in pairs(hourTotals) do
    if count > peakCount then
      peakHour = h
      peakCount = count
    end
  end
  return peakHour, peakCount
end

local function FormatHour(h)
  if not h then return L["N/A"] end
  if h == 0 then return "12am"
  elseif h < 12 then return h .. "am"
  elseif h == 12 then return "12pm"
  else return (h - 12) .. "pm"
  end
end

-- =========================================================================
-- Page creation
-- =========================================================================

function GRIP:CreateStatsPage(parent)
  local page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints(parent)

  local _, content = W.CreateScrollPage(page)

  local Y_START = -8
  local ROW_HEIGHT = 18
  local PANEL_X = 4
  local PANEL_HEIGHT = 196
  local SECTION_GAP = 12
  local INNER_LABEL_X = 16
  local INNER_VALUE_X = 114

  -- Title
  local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", content, "TOPLEFT", 12, Y_START)
  title:SetText(L["Recruitment Statistics"])

  local y = Y_START - 28

  -- Helper: create a stat section inside a themed panel card
  local function CreateSection(sectionTitle)
    local section = {}

    local panel = W.CreateThemedPanel(content, sectionTitle)
    panel:SetPoint("TOPLEFT", content, "TOPLEFT", PANEL_X, y)
    panel:SetPoint("RIGHT", content, "RIGHT", -PANEL_X, 0)
    panel:SetHeight(PANEL_HEIGHT)
    section._panel = panel

    local innerY = -28

    section.rows = {}
    for _, key in ipairs(STAT_KEYS) do
      local row = {}
      row.label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      row.label:SetPoint("TOPLEFT", panel, "TOPLEFT", INNER_LABEL_X, innerY)
      row.label:SetText(STAT_LABELS[key] or key)
      row.label:SetTextColor(unpack(GRIP.COLORS.LIGHT_GREY))

      row.value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.value:SetPoint("TOPLEFT", panel, "TOPLEFT", INNER_VALUE_X, innerY)
      row.value:SetText("0")

      section.rows[key] = row
      innerY = innerY - ROW_HEIGHT
    end

    -- Accept rate row
    section.rateLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section.rateLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", INNER_LABEL_X, innerY)
    section.rateLabel:SetText(L["Accept Rate"])
    section.rateLabel:SetTextColor(unpack(GRIP.COLORS.GREEN))

    section.rateValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    section.rateValue:SetPoint("TOPLEFT", panel, "TOPLEFT", INNER_VALUE_X, innerY)
    section.rateValue:SetText(L["N/A"])

    innerY = innerY - ROW_HEIGHT

    -- Peak Hour row
    section.peakLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section.peakLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", INNER_LABEL_X, innerY)
    section.peakLabel:SetText(L["Peak Hour"])
    section.peakLabel:SetTextColor(unpack(GRIP.COLORS.LIGHT_BLUE))

    section.peakValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    section.peakValue:SetPoint("TOPLEFT", panel, "TOPLEFT", INNER_VALUE_X, innerY)
    section.peakValue:SetText(L["N/A"])

    GRIP:AttachTooltip(section.peakLabel, L["Peak Hour"],
        L["GRIP_STATS_PEAK_TOOLTIP"])

    y = y - (PANEL_HEIGHT + SECTION_GAP)

    function section:Update(data, peakHour, peakCount)
      for _, key in ipairs(STAT_KEYS) do
        local row = self.rows[key]
        if row and row.value then
          row.value:SetText(tostring(data[key] or 0))
        end
      end
      self.rateValue:SetText(FormatRate(data.accepted or 0, data.whispers or 0))
      if peakHour then
        self.peakValue:SetText((L["%s (%d actions)"]):format(FormatHour(peakHour), peakCount))
      else
        self.peakValue:SetText(L["N/A"])
      end
    end

    return section
  end

  page._sectionToday = CreateSection(L["Today"])
  page._section7d    = CreateSection(L["Last 7 Days"])
  page._section30d   = CreateSection(L["Last 30 Days"])

  content:SetHeight(abs(y) + 8)

  -- LayoutForWidth hook (no-op — vertical layout fits fine)
  function page:LayoutForWidth(_w) end

  return page
end

-- =========================================================================
-- Refresh
-- =========================================================================

function GRIP:UpdateStatsPage()
  local f = GRIP.state.ui
  if not f or not f.stats then return end
  local page = f.stats

  if not _G.GRIPDB_CHAR or type(GRIPDB_CHAR.stats) ~= "table" then
    local empty = EmptyRow()
    if page._sectionToday then page._sectionToday:Update(empty) end
    if page._section7d then page._section7d:Update(empty) end
    if page._section30d then page._section30d:Update(empty) end
    return
  end

  local stats = GRIPDB_CHAR.stats
  local today = stats.today
  local days = stats.days

  -- Today: just the today bucket
  local todayData = EmptyRow()
  if today and type(today) == "table" then
    for _, k in ipairs(STAT_KEYS) do
      todayData[k] = today[k] or 0
    end
  end
  local todayPeakH, todayPeakC = FindPeakHour(nil, 1, today)
  if page._sectionToday then page._sectionToday:Update(todayData, todayPeakH, todayPeakC) end

  -- 7 days: today + last 6 from history
  local data7 = SumDays(days, 7, today)
  local peak7H, peak7C = FindPeakHour(days, 7, today)
  if page._section7d then page._section7d:Update(data7, peak7H, peak7C) end

  -- 30 days: today + last 29 from history
  local data30 = SumDays(days, 30, today)
  local peak30H, peak30C = FindPeakHour(days, 30, today)
  if page._section30d then page._section30d:Update(data30, peak30H, peak30C) end
end
