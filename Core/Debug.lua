-- GRIP: Debug
-- Logger capture override + SavedVariables ring buffer for debug persistence.

local ADDON_NAME, GRIP = ...
local Logger = GRIP.Logger or {}
GRIP.Logger = Logger

local DEFAULT_PERSIST_MAX = 800

local LEVEL_NAME = {
  [1] = "INFO",
  [2] = "DEBUG",
  [3] = "TRACE",
}

local function Join(...)
  local n = select("#", ...)
  if n == 0 then return "" end
  local t = {}
  for i = 1, n do
    t[i] = tostring(select(i, ...))
  end
  return table.concat(t, " ")
end

local function EnsurePersistTables()
  if not _G.GRIPDB then return nil end
  GRIPDB.debugLog = GRIPDB.debugLog or {}
  GRIPDB.debugLog.lines = GRIPDB.debugLog.lines or {}
  GRIPDB.debugLog.dropped = tonumber(GRIPDB.debugLog.dropped) or 0
  GRIPDB.debugLog.lastAt = GRIPDB.debugLog.lastAt or ""
  return GRIPDB.debugLog
end

local function ClampPersistMax(n)
  n = tonumber(n) or DEFAULT_PERSIST_MAX
  if n < 50 then n = 50 end
  if n > 5000 then n = 5000 end
  return n
end

local function NormalizeCaptureAliases(cfg)
  if type(cfg) ~= "table" then return end

  -- Keep both keys in sync, regardless of which one a caller toggles.
  if cfg.debugCapture == nil and cfg.debugPersist ~= nil then
    cfg.debugCapture = cfg.debugPersist and true or false
  end
  if cfg.debugPersist == nil and cfg.debugCapture ~= nil then
    cfg.debugPersist = cfg.debugCapture and true or false
  end
  local on = (cfg.debugCapture == true) or (cfg.debugPersist == true)
  cfg.debugCapture = on
  cfg.debugPersist = on

  -- Keep max aliases consistent too (prefer debugPersistMax)
  if cfg.debugPersistMax == nil and cfg.debugCaptureMax ~= nil then
    cfg.debugPersistMax = cfg.debugCaptureMax
  end
  if cfg.debugCaptureMax == nil and cfg.debugPersistMax ~= nil then
    cfg.debugCaptureMax = cfg.debugPersistMax
  end

  -- Clamp + write back to both keys (prevents drift / weird values)
  local m = ClampPersistMax(cfg.debugPersistMax or cfg.debugCaptureMax)
  cfg.debugPersistMax = m
  cfg.debugCaptureMax = m
end

local function CaptureEnabled(cfg)
  if not cfg then return false end
  NormalizeCaptureAliases(cfg)
  return (cfg.debugCapture == true)
end

local function GetPersistMax(cfg)
  NormalizeCaptureAliases(cfg)
  return ClampPersistMax(cfg and (cfg.debugPersistMax or cfg.debugCaptureMax))
end

local function PersistAppend(line, ts)
  if type(line) ~= "string" or line == "" then return end
  if not _G.GRIPDB or not GRIPDB.config then return end

  local cfg = GRIPDB.config
  if not CaptureEnabled(cfg) then return end

  local store = EnsurePersistTables()
  if not store then return end

  local lines = store.lines
  lines[#lines + 1] = line

  local maxLines = GetPersistMax(cfg)
  local over = #lines - maxLines
  if over > 0 then
    for _ = 1, over do
      table.remove(lines, 1)
    end
    store.dropped = (tonumber(store.dropped) or 0) + over
  end

  store.lastAt = tostring(ts or store.lastAt or "")
end

-- ------------------------------------------------------------
-- Logger capture hook
-- Core Logger:Log() calls Logger:Capture(...) if present.
-- Signature from Core:
--   Capture(self, level, ts, formattedChatMsg, ...)
-- ------------------------------------------------------------
function Logger:Capture(level, ts, _formattedChatMsg, ...)
  local cfg = self.GetConfig and self:GetConfig() or (_G.GRIPDB and GRIPDB.config)
  if not cfg then return end
  if not CaptureEnabled(cfg) then return end

  local lvl = LEVEL_NAME[tonumber(level) or 2] or tostring(level)
  local raw = Join(...)
  ts = ts or date("%H:%M:%S")

  -- Persist a plain, copy/paste-friendly line (no color codes)
  PersistAppend(("[%s] %s %s"):format(ts, lvl, raw), ts)
end

-- ------------------------------------------------------------
-- Public helpers for Slash/UI
-- ------------------------------------------------------------
function GRIP:GetPersistedDebugLines()
  if not _G.GRIPDB or not GRIPDB.debugLog or type(GRIPDB.debugLog.lines) ~= "table" then
    return {}
  end
  return GRIPDB.debugLog.lines
end

function GRIP:GetPersistedDebugDropped()
  if not _G.GRIPDB or not GRIPDB.debugLog then return 0 end
  return tonumber(GRIPDB.debugLog.dropped) or 0
end

function GRIP:GetPersistedDebugLastAt()
  if not _G.GRIPDB or not GRIPDB.debugLog then return "" end
  return tostring(GRIPDB.debugLog.lastAt or "")
end

function GRIP:ClearPersistedDebugLines()
  if not _G.GRIPDB then return 0 end
  if not GRIPDB.debugLog or type(GRIPDB.debugLog.lines) ~= "table" then
    GRIPDB.debugLog = { lines = {}, dropped = 0, lastAt = "" }
    return 0
  end
  local n = #GRIPDB.debugLog.lines
  wipe(GRIPDB.debugLog.lines)
  GRIPDB.debugLog.dropped = 0
  GRIPDB.debugLog.lastAt = ""
  return n
end

-- Back-compat names used by your Slash.lua
function GRIP:DumpDebugLog(n)
  n = tonumber(n) or 200
  if n < 1 then n = 1 end
  if n > 2000 then n = 2000 end

  local lines = self:GetPersistedDebugLines()
  local total = #lines
  local dropped = self.GetPersistedDebugDropped and self:GetPersistedDebugDropped() or 0

  if total == 0 then
    self:Print("Debug log is empty (enable: /grip debug capture on, and /grip debug on).")
    return
  end

  local start = math.max(1, total - n + 1)
  local shown = total - start + 1
  self:Print(("Debug log: showing %d of %d (dropped %d)"):format(shown, total, dropped))

  if DEFAULT_CHAT_FRAME then
    for i = start, total do
      DEFAULT_CHAT_FRAME:AddMessage(lines[i])
    end
  end
end

function GRIP:ClearDebugLog()
  return self:ClearPersistedDebugLines()
end

function GRIP:UpdateDebugCapture()
  if not _G.GRIPDB or not GRIPDB.config then return end
  NormalizeCaptureAliases(GRIPDB.config)
  if CaptureEnabled(GRIPDB.config) then
    EnsurePersistTables()
  end
end

-- ------------------------------------------------------------
-- Copyable debug output frame (/grip debug copy)
-- ------------------------------------------------------------
function GRIP:ShowDebugCopyFrame(n)
  n = tonumber(n) or 200
  n = self:Clamp(n, 1, 2000)

  local lines = self:GetPersistedDebugLines()
  if type(lines) ~= "table" or #lines == 0 then
    self:Print("Debug log is empty (enable: /grip debug capture on, and /grip debug on).")
    return
  end

  local total = #lines
  local start = math.max(1, total - n + 1)
  local parts = {}
  for i = start, total do
    parts[#parts + 1] = lines[i]
  end
  local text = table.concat(parts, "\n")

  -- Reuse or create the copy frame.
  local f = self._debugCopyFrame
  if not f then
    f = CreateFrame("Frame", "GRIPDebugCopyFrame", UIParent, "BackdropTemplate")
    f:SetSize(600, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("GRIP Debug Log")
    f._title = title

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", "GRIPDebugCopyScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -36)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(540)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(eb)
    f._editBox = eb

    self._debugCopyFrame = f
  end

  f._title:SetText(("GRIP Debug Log (%d of %d lines)"):format(#parts, total))
  f._editBox:SetText(text)
  f._editBox:HighlightText()
  f._editBox:SetCursorPosition(0)
  f:Show()
end