-- GRIP: Import/Export
-- Clipboard import/export for permanent blacklists and whisper templates (FE8).

local ADDON_NAME, GRIP = ...

local type, tostring, pairs, ipairs = type, tostring, pairs, ipairs
local time = time

-- Constants
local PREFIX_BL  = "!GRIP:BL:"
local PREFIX_TPL = "!GRIP:TPL:"
local FORMAT_VERSION = "1"
local MAX_TEMPLATES = 10

-- =========================================================================
-- Export
-- =========================================================================

function GRIP:ExportBlacklist()
  if not _G.GRIPDB or type(GRIPDB.blacklistPerm) ~= "table" then return nil end
  if not self.EncodeForClipboard then return nil end

  local encoded = self.EncodeForClipboard(GRIPDB.blacklistPerm)
  if not encoded then return nil end

  return PREFIX_BL .. FORMAT_VERSION .. ":" .. encoded
end

function GRIP:ExportTemplates()
  if not _G.GRIPDB_CHAR or type(GRIPDB_CHAR.config) ~= "table" then return nil end
  if not self.EncodeForClipboard then return nil end

  local cfg = GRIPDB_CHAR.config
  local data = {
    templates = cfg.whisperMessages or {},
    rotation = cfg.whisperRotation or "sequential",
  }

  local encoded = self.EncodeForClipboard(data)
  if not encoded then return nil end

  return PREFIX_TPL .. FORMAT_VERSION .. ":" .. encoded
end

-- =========================================================================
-- Import
-- =========================================================================

function GRIP:ImportBlacklist(str)
  if type(str) ~= "string" then return nil end
  str = str:gsub("^%s+", ""):gsub("%s+$", "")

  if str:sub(1, #PREFIX_BL) ~= PREFIX_BL then return nil end
  if not self.DecodeFromClipboard then return nil end

  -- Extract version and payload: "!GRIP:BL:<ver>:<payload>"
  local afterPrefix = str:sub(#PREFIX_BL + 1)
  local version, payload = afterPrefix:match("^(%d+):(.*)")
  if not version or not payload then return nil end
  if version ~= FORMAT_VERSION then
    self:Print("Unsupported import version: " .. version)
    return nil
  end

  local data = self.DecodeFromClipboard(payload)
  if type(data) ~= "table" then return nil end

  -- Ensure target table
  if not _G.GRIPDB then return nil end
  GRIPDB.blacklistPerm = GRIPDB.blacklistPerm or {}

  -- Set-union merge (add-only, never overwrite existing)
  local added, existing = 0, 0
  for name, entry in pairs(data) do
    if type(name) == "string" and name ~= "" then
      if GRIPDB.blacklistPerm[name] ~= nil then
        existing = existing + 1
      else
        -- Normalize entry
        if type(entry) == "table" then
          GRIPDB.blacklistPerm[name] = {
            at = tonumber(entry.at) or time(),
            reason = tostring(entry.reason or "imported"),
          }
        else
          GRIPDB.blacklistPerm[name] = { at = time(), reason = "imported" }
        end
        added = added + 1
      end
    end
  end

  return { added = added, existing = existing, total = added + existing }
end

function GRIP:ImportTemplates(str)
  if type(str) ~= "string" then return nil end
  str = str:gsub("^%s+", ""):gsub("%s+$", "")

  if str:sub(1, #PREFIX_TPL) ~= PREFIX_TPL then return nil end
  if not self.DecodeFromClipboard then return nil end

  local afterPrefix = str:sub(#PREFIX_TPL + 1)
  local version, payload = afterPrefix:match("^(%d+):(.*)")
  if not version or not payload then return nil end
  if version ~= FORMAT_VERSION then
    self:Print("Unsupported import version: " .. version)
    return nil
  end

  local data = self.DecodeFromClipboard(payload)
  if type(data) ~= "table" then return nil end
  if type(data.templates) ~= "table" or #data.templates == 0 then return nil end

  local cfg = _G.GRIPDB_CHAR and GRIPDB_CHAR.config
  if not cfg then return nil end

  -- Validate and cap at MAX_TEMPLATES
  local imported = {}
  for i = 1, math.min(#data.templates, MAX_TEMPLATES) do
    local t = data.templates[i]
    if type(t) == "string" and t ~= "" then
      imported[#imported + 1] = t
    end
  end
  if #imported == 0 then return nil end

  cfg.whisperMessages = imported

  if data.rotation == "sequential" or data.rotation == "random" then
    cfg.whisperRotation = data.rotation
  end

  -- Keep whisperMessage alias in sync
  cfg.whisperMessage = cfg.whisperMessages[1] or ""

  -- Mark as edited (triggers sync if enabled)
  cfg.templatesEditedAt = time()

  return { count = #imported, rotation = cfg.whisperRotation }
end
