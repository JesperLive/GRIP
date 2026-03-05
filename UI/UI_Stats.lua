-- GRIP: Stats Page
-- Recruitment statistics display with daily/weekly/monthly summaries and conversion rates.

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local ipairs, pairs = ipairs, pairs
local format = string.format
local max, floor = math.max, math.floor

local W = GRIP.UIW

-- =========================================================================
-- Helpers
-- =========================================================================

local STAT_KEYS = { "whispers", "invites", "accepted", "declined", "optOuts", "posts", "scans" }
local STAT_LABELS = {
  whispers = "Whispers",
  invites = "Invites",
  accepted = "Accepted",
  declined = "Declined",
  optOuts = "Opt-Outs",
  posts = "Posts",
  scans = "Scans",
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

  -- Sum most recent n entries from days array (newest at end)
  local startIdx = max(1, #days - n + 1)
  -- But if today is counted, we already have 1 day, so take n-1 from history
  local historyCount = n - 1
  startIdx = max(1, #days - historyCount + 1)

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
  if not whispers or whispers == 0 then return "N/A" end
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
  if not h then return "N/A" end
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

  local Y_START = -8
  local ROW_HEIGHT = 18
  local SECTION_GAP = 14
  local LABEL_X = 12
  local VALUE_X = 110

  -- Title
  local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_X, Y_START)
  title:SetText("Recruitment Statistics")

  local y = Y_START - 28

  -- Helper: create a stat section (title + 7 stat rows + accept rate)
  local function CreateSection(sectionTitle)
    local section = {}

    section.header = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section.header:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_X, y)
    section.header:SetText(sectionTitle)
    section.header:SetTextColor(1, 0.82, 0, 1)
    y = y - ROW_HEIGHT - 2

    section.rows = {}
    for _, key in ipairs(STAT_KEYS) do
      local row = {}
      row.label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      row.label:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_X + 8, y)
      row.label:SetText(STAT_LABELS[key] or key)
      row.label:SetTextColor(0.8, 0.8, 0.8, 1)

      row.value = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.value:SetPoint("TOPLEFT", page, "TOPLEFT", VALUE_X, y)
      row.value:SetText("0")

      section.rows[key] = row
      y = y - ROW_HEIGHT
    end

    -- Accept rate row
    section.rateLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section.rateLabel:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_X + 8, y)
    section.rateLabel:SetText("Accept Rate")
    section.rateLabel:SetTextColor(0.4, 1, 0.4, 1)

    section.rateValue = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    section.rateValue:SetPoint("TOPLEFT", page, "TOPLEFT", VALUE_X, y)
    section.rateValue:SetText("N/A")

    y = y - ROW_HEIGHT

    -- Peak Hour row
    section.peakLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section.peakLabel:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_X + 8, y)
    section.peakLabel:SetText("Peak Hour")
    section.peakLabel:SetTextColor(0.6, 0.8, 1, 1)

    section.peakValue = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    section.peakValue:SetPoint("TOPLEFT", page, "TOPLEFT", VALUE_X, y)
    section.peakValue:SetText("N/A")

    y = y - ROW_HEIGHT - SECTION_GAP

    function section:Update(data, peakHour, peakCount)
      for _, key in ipairs(STAT_KEYS) do
        local row = self.rows[key]
        if row and row.value then
          row.value:SetText(tostring(data[key] or 0))
        end
      end
      self.rateValue:SetText(FormatRate(data.accepted or 0, data.whispers or 0))
      if peakHour then
        self.peakValue:SetText(format("%s (%d actions)", FormatHour(peakHour), peakCount))
      else
        self.peakValue:SetText("N/A")
      end
    end

    return section
  end

  page._sectionToday = CreateSection("Today")
  page._section7d = CreateSection("Last 7 Days")
  page._section30d = CreateSection("Last 30 Days")

  -- LayoutForWidth hook (no-op for now — vertical layout fits fine)
  function page:LayoutForWidth(w) end

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
