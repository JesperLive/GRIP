-- GRIP: Sync
-- Officer sync via AceComm-3.0 over GUILD channel (blacklist set-union + template LWW merge).

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, pcall = pairs, pcall
local format = string.format
local time = time

-- Constants
local SYNC_PREFIX       = "GRIP"
local SYNC_COOLDOWN     = 3600    -- 1 hour between broadcasts
local SYNC_STARTUP_DELAY = 10     -- seconds after ADDON_LOADED before first broadcast
local SYNC_PRIORITY     = "BULK"  -- ChatThrottleLib priority (queues at ~1/sec)
local LWW_TOLERANCE     = 300     -- 5 minutes clock skew tolerance for template LWW

-- Library handles (resolved at init)
local AceComm
local LibSerialize
local LibDeflate

-- =========================================================================
-- Generic codec helpers (shared by blacklist + template sync, FE8 prep)
-- =========================================================================

--- Encode a Lua table for transmission over the WoW addon channel.
-- @return encoded string, or nil on failure
local function EncodeForAddonChannel(data)
  if not LibSerialize or not LibDeflate then return nil end

  local ok, serialized = pcall(LibSerialize.Serialize, LibSerialize, data)
  if not ok or not serialized then
    GRIP:Debug("Sync: serialize failed:", tostring(serialized))
    return nil
  end

  local compressed = LibDeflate:CompressDeflate(serialized)
  if not compressed then
    GRIP:Debug("Sync: compress failed")
    return nil
  end

  local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
  if not encoded then
    GRIP:Debug("Sync: addon-channel encode failed")
    return nil
  end

  return encoded
end

--- Decode an addon-channel string back into a Lua table.
-- @return table, or nil on failure
local function DecodeFromAddonChannel(encoded)
  if not LibSerialize or not LibDeflate then return nil end
  if type(encoded) ~= "string" or encoded == "" then return nil end

  local compressed = LibDeflate:DecodeForWoWAddonChannel(encoded)
  if not compressed then
    GRIP:Debug("Sync: addon-channel decode failed")
    return nil
  end

  local serialized = LibDeflate:DecompressDeflate(compressed)
  if not serialized then
    GRIP:Debug("Sync: decompress failed")
    return nil
  end

  local ok, data = pcall(LibSerialize.Deserialize, LibSerialize, serialized)
  if not ok or type(data) ~= "table" then
    GRIP:Debug("Sync: deserialize failed:", tostring(data))
    return nil
  end

  return data
end

--- Encode a Lua table for clipboard (printable string, FE8 import/export prep).
-- @return printable string, or nil on failure
local function EncodeForClipboard(data)
  if not LibSerialize or not LibDeflate then return nil end

  local ok, serialized = pcall(LibSerialize.Serialize, LibSerialize, data)
  if not ok or not serialized then
    GRIP:Debug("Sync: clipboard serialize failed:", tostring(serialized))
    return nil
  end

  local compressed = LibDeflate:CompressDeflate(serialized)
  if not compressed then
    GRIP:Debug("Sync: clipboard compress failed")
    return nil
  end

  local encoded = LibDeflate:EncodeForPrint(compressed)
  if not encoded then
    GRIP:Debug("Sync: clipboard encode failed")
    return nil
  end

  return encoded
end

--- Decode a clipboard (printable) string back into a Lua table.
-- @return table, or nil on failure
local function DecodeFromClipboard(str)
  if not LibSerialize or not LibDeflate then return nil end
  if type(str) ~= "string" or str == "" then return nil end

  local compressed = LibDeflate:DecodeForPrint(str)
  if not compressed then
    GRIP:Debug("Sync: clipboard decode failed")
    return nil
  end

  local serialized = LibDeflate:DecompressDeflate(compressed)
  if not serialized then
    GRIP:Debug("Sync: clipboard decompress failed")
    return nil
  end

  local ok, data = pcall(LibSerialize.Deserialize, LibSerialize, serialized)
  if not ok or type(data) ~= "table" then
    GRIP:Debug("Sync: clipboard deserialize failed:", tostring(data))
    return nil
  end

  return data
end

-- Expose clipboard helpers on the GRIP table for FE8 import/export
GRIP.EncodeForClipboard = EncodeForClipboard
GRIP.DecodeFromClipboard = DecodeFromClipboard

-- =========================================================================
-- Blacklist hash, serialize, deserialize (thin wrappers over generic codec)
-- =========================================================================

local function ComputeBlacklistHash()
  if not _G.GRIPDB or type(GRIPDB.blacklistPerm) ~= "table" then return "empty" end

  local keys = {}
  for k in pairs(GRIPDB.blacklistPerm) do
    keys[#keys + 1] = k
  end
  if #keys == 0 then return "empty" end

  table.sort(keys)

  -- djb2 hash
  local h = 5381
  for i = 1, #keys do
    local s = keys[i]
    for j = 1, #s do
      h = (h * 33 + s:byte(j)) % 2^32
    end
  end
  return tostring(h)
end

local function SerializeBlacklist()
  if not _G.GRIPDB or type(GRIPDB.blacklistPerm) ~= "table" then return nil end
  return EncodeForAddonChannel(GRIPDB.blacklistPerm)
end

local function DeserializeBlacklist(encoded)
  return DecodeFromAddonChannel(encoded)
end

-- =========================================================================
-- Set-union merge: add entries from remote that we don't have (never remove)
-- =========================================================================
local function MergeBlacklist(remoteData)
  if type(remoteData) ~= "table" then return 0 end
  if not _G.GRIPDB then return 0 end
  GRIPDB.blacklistPerm = GRIPDB.blacklistPerm or {}

  local added = 0
  for name, entry in pairs(remoteData) do
    if type(name) == "string" and name ~= "" and GRIPDB.blacklistPerm[name] == nil then
      -- Normalize incoming entry
      if type(entry) == "table" then
        GRIPDB.blacklistPerm[name] = {
          at = tonumber(entry.at) or time(),
          reason = tostring(entry.reason or "synced"),
        }
      elseif entry == true then
        GRIPDB.blacklistPerm[name] = { at = time(), reason = "synced" }
      else
        GRIPDB.blacklistPerm[name] = { at = time(), reason = "synced" }
      end
      added = added + 1
    end
  end

  return added
end

-- =========================================================================
-- Template hash, serialize, deserialize, merge (v2)
-- =========================================================================

local function ComputeTemplateHash()
  local cfg = _G.GRIPDB_CHAR and GRIPDB_CHAR.config
  if not cfg or type(cfg.whisperMessages) ~= "table" then return "empty" end
  if #cfg.whisperMessages == 0 then return "empty" end

  -- djb2 hash of all template strings concatenated + rotation mode
  local h = 5381
  for i = 1, #cfg.whisperMessages do
    local s = cfg.whisperMessages[i] or ""
    for j = 1, #s do
      h = (h * 33 + s:byte(j)) % 2^32
    end
  end
  local rot = cfg.whisperRotation or "sequential"
  for j = 1, #rot do
    h = (h * 33 + rot:byte(j)) % 2^32
  end
  return tostring(h)
end

local function SerializeTemplates()
  local cfg = _G.GRIPDB_CHAR and GRIPDB_CHAR.config
  if not cfg or type(cfg.whisperMessages) ~= "table" then return nil end
  local payload = {
    updatedAt = tonumber(cfg.templatesEditedAt) or 0,
    templates = cfg.whisperMessages,
    rotation = cfg.whisperRotation or "sequential",
  }
  return EncodeForAddonChannel(payload)
end

local function MergeTemplates(remoteData, sender)
  if type(remoteData) ~= "table" then return false end
  if type(remoteData.templates) ~= "table" then return false end
  if #remoteData.templates == 0 then return false end

  local cfg = _G.GRIPDB_CHAR and GRIPDB_CHAR.config
  if not cfg then return false end

  -- Check per-collection opt-in
  if cfg.syncTemplates == false then return false end

  local remoteAt = tonumber(remoteData.updatedAt) or 0
  local localAt = tonumber(cfg.templatesSyncedAt) or 0
  local localEditAt = tonumber(cfg.templatesEditedAt) or 0

  -- Use the more recent of synced-at and edited-at as our "version"
  local localVersion = localAt > localEditAt and localAt or localEditAt

  -- LWW: only accept if remote is newer (beyond tolerance)
  if remoteAt <= (localVersion + LWW_TOLERANCE) then
    GRIP:Debug("Sync: TPL from", sender, "not newer (remote=", remoteAt,
      "local=", localVersion, "tolerance=", LWW_TOLERANCE, ")")
    return false
  end

  -- Accept remote templates
  cfg.whisperMessages = {}
  for i = 1, #remoteData.templates do
    cfg.whisperMessages[i] = tostring(remoteData.templates[i])
  end

  -- Cap at 10
  while #cfg.whisperMessages > 10 do
    table.remove(cfg.whisperMessages)
  end

  cfg.whisperRotation = (remoteData.rotation == "random") and "random" or "sequential"
  cfg.templatesSyncedAt = remoteAt

  -- Keep whisperMessage alias in sync (always = whisperMessages[1])
  if #cfg.whisperMessages > 0 then
    cfg.whisperMessage = cfg.whisperMessages[1]
  end

  return true
end

-- =========================================================================
-- GM Config hash, serialize, merge (FP-2 -- V3 extension)
-- =========================================================================

local function ComputeGMConfigHash()
  local gmc = _G.GRIPDB and GRIPDB.gmConfig
  if not gmc or type(gmc.version) ~= "number" or gmc.version == 0 then
    return "empty"
  end
  return tostring(gmc.version)
end

local function SerializeGMConfig()
  local gmc = _G.GRIPDB and GRIPDB.gmConfig
  if not gmc or gmc.version == 0 then return nil end
  -- Only send if we're the GM
  if not (GRIP.IsGuildLeader and GRIP:IsGuildLeader()) then return nil end
  local payload = {
    version = gmc.version,
    force = gmc.force,
    values = gmc.values,
  }
  return EncodeForAddonChannel(payload)
end

local function MergeGMConfig(remoteData, sender)
  if type(remoteData) ~= "table" then return false end
  if type(remoteData.version) ~= "number" then return false end
  if remoteData.version == 0 then return false end

  -- Don't accept GM config if WE are the GM
  if GRIP.IsGuildLeader and GRIP:IsGuildLeader() then return false end

  if not _G.GRIPDB then return false end
  local received = GRIPDB.gmConfigReceived
  if not received then return false end

  local localVersion = tonumber(received.version) or 0
  -- LWW: only accept if remote is newer
  if remoteData.version <= localVersion then
    GRIP:Debug("Sync: CFG from", sender, "not newer (remote=",
      remoteData.version, "local=", localVersion, ")")
    return false
  end

  -- Validate force table: only accept whitelisted keys
  local validForce = {}
  local validValues = {}
  if type(remoteData.force) == "table" and type(remoteData.values) == "table" then
    for key, _ in pairs(remoteData.force) do
      if GRIP.FORCEABLE_SETTINGS and GRIP.FORCEABLE_SETTINGS[key] then
        validForce[key] = true
        validValues[key] = remoteData.values[key]
      end
    end
  end

  received.version = remoteData.version
  received.force = validForce
  received.values = validValues
  GRIPDB.gmConfigReceivedAt = time()

  GRIP:Debug("Sync: CFG merged from", sender, "version=", remoteData.version)
  return true
end

-- =========================================================================
-- Sync protocol handler (V2 + V3)
-- protocolVersion: 2 or 3 (determines which collections are in scope)
-- =========================================================================

local function HandleSync(cmd, payload, sender, protocolVersion)
  if cmd == "HASH" then
    -- V3 payload = "<bl_hash>:<tpl_hash>:<cfg_hash>"
    -- V2 payload = "<bl_hash>:<tpl_hash>"
    local remoteBlHash, remoteTplHash, remoteCfgHash
    if protocolVersion >= 3 then
      remoteBlHash, remoteTplHash, remoteCfgHash = payload:match("^([^:]+):([^:]+):([^:]+)$")
    end
    if not remoteBlHash then
      -- V2 format (or V3 parse failed — fall back)
      remoteBlHash, remoteTplHash = payload:match("^([^:]+):([^:]+)")
      remoteCfgHash = nil
    end
    if not remoteBlHash then return end

    local localBlHash = ComputeBlacklistHash()
    local localTplHash = ComputeTemplateHash()
    local cfg = _G.GRIPDB_CHAR and GRIPDB_CHAR.config

    local needBl = (remoteBlHash ~= localBlHash)
    local needTpl = (remoteTplHash ~= localTplHash) and (cfg and cfg.syncTemplates ~= false)
    local needCfg = false
    if protocolVersion >= 3 and remoteCfgHash then
      local localCfgHash = ComputeGMConfigHash()
      needCfg = (remoteCfgHash ~= localCfgHash)
    end

    local prefix = protocolVersion >= 3 and "V3" or "V2"
    GRIP:Debug("Sync:", prefix, ":HASH from", sender,
      "bl:", remoteBlHash, "vs", localBlHash, needBl and "DIFF" or "same",
      "tpl:", remoteTplHash, "vs", localTplHash, needTpl and "DIFF" or "same",
      remoteCfgHash and ("cfg: " .. remoteCfgHash .. " " .. (needCfg and "DIFF" or "same")) or "")

    -- Build request using the sender's protocol version
    local reqPrefix = prefix .. ":REQ:"
    if needBl and needTpl and needCfg then
      AceComm:SendCommMessage(SYNC_PREFIX, reqPrefix .. "ALL", "GUILD", nil, SYNC_PRIORITY)
    elseif needBl and needTpl then
      AceComm:SendCommMessage(SYNC_PREFIX, reqPrefix .. "ALL", "GUILD", nil, SYNC_PRIORITY)
    elseif needBl and needCfg then
      -- Request both individually
      AceComm:SendCommMessage(SYNC_PREFIX, reqPrefix .. "BL", "GUILD", nil, SYNC_PRIORITY)
      AceComm:SendCommMessage(SYNC_PREFIX, reqPrefix .. "CFG", "GUILD", nil, SYNC_PRIORITY)
    elseif needTpl and needCfg then
      AceComm:SendCommMessage(SYNC_PREFIX, reqPrefix .. "TPL", "GUILD", nil, SYNC_PRIORITY)
      AceComm:SendCommMessage(SYNC_PREFIX, reqPrefix .. "CFG", "GUILD", nil, SYNC_PRIORITY)
    elseif needBl then
      AceComm:SendCommMessage(SYNC_PREFIX, reqPrefix .. "BL", "GUILD", nil, SYNC_PRIORITY)
    elseif needTpl then
      AceComm:SendCommMessage(SYNC_PREFIX, reqPrefix .. "TPL", "GUILD", nil, SYNC_PRIORITY)
    elseif needCfg then
      AceComm:SendCommMessage(SYNC_PREFIX, reqPrefix .. "CFG", "GUILD", nil, SYNC_PRIORITY)
    end
    return
  end

  if cmd == "REQ" then
    -- payload = "BL" | "TPL" | "CFG" | "ALL"
    local prefix = protocolVersion >= 3 and "V3" or "V2"
    if payload == "BL" or payload == "ALL" then
      local encoded = SerializeBlacklist()
      if encoded then
        AceComm:SendCommMessage(SYNC_PREFIX, prefix .. ":DATA:BL:" .. encoded, "GUILD", nil, SYNC_PRIORITY)
      end
    end
    if payload == "TPL" or payload == "ALL" then
      local encoded = SerializeTemplates()
      if encoded then
        AceComm:SendCommMessage(SYNC_PREFIX, prefix .. ":DATA:TPL:" .. encoded, "GUILD", nil, SYNC_PRIORITY)
      end
    end
    if (payload == "CFG" or payload == "ALL") and protocolVersion >= 3 then
      local encoded = SerializeGMConfig()
      if encoded then
        AceComm:SendCommMessage(SYNC_PREFIX, prefix .. ":DATA:CFG:" .. encoded, "GUILD", nil, SYNC_PRIORITY)
      end
    end
    return
  end

  if cmd == "DATA" then
    -- payload = "BL:<encoded>" or "TPL:<encoded>" or "CFG:<encoded>"
    local collection, encoded = payload:match("^(%u+):(.*)")
    if not collection then return end

    if collection == "BL" then
      local remoteData = DeserializeBlacklist(encoded)
      if remoteData then
        local added = MergeBlacklist(remoteData)
        if added > 0 then
          GRIP:Info("Sync: added", added, "blacklist entries from", sender)
          GRIP:UpdateUI()
        end
      end
    elseif collection == "TPL" then
      local remoteData = DecodeFromAddonChannel(encoded)
      if remoteData then
        local ok = MergeTemplates(remoteData, sender)
        if ok then
          GRIP:Info("Sync: updated whisper templates from", sender)
          GRIP:UpdateUI()
        end
      end
    elseif collection == "CFG" and protocolVersion >= 3 then
      local remoteData = DecodeFromAddonChannel(encoded)
      if remoteData then
        local ok = MergeGMConfig(remoteData, sender)
        if ok then
          GRIP:Info("Sync: updated GM forced settings from", sender)
          GRIP:UpdateUI()
        end
      end
    end
    return
  end
end

-- =========================================================================
-- Message handler (incoming AceComm messages)
-- =========================================================================
local function OnCommReceived(prefix, message, distribution, sender)
  if prefix ~= SYNC_PREFIX then return end
  if distribution ~= "GUILD" then return end

  -- Ignore messages from self
  local me = UnitName("player")
  local myRealm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
  local myFull = me and myRealm and myRealm ~= "" and (me .. "-" .. myRealm) or me
  if sender == me or sender == myFull then return end

  -- Check if sync is enabled
  if not _G.GRIPDB or GRIPDB.syncEnabled == false then return end

  GRIP:Debug("Sync: received from", sender, "len=", #message)

  -- Try V3 first
  local v3cmd, v3payload = message:match("^V3:(%u+):(.*)")
  if v3cmd then
    HandleSync(v3cmd, v3payload, sender, 3)
    return
  end

  -- Try V2
  local v2cmd, v2payload = message:match("^V2:(%u+):(.*)")
  if v2cmd then
    HandleSync(v2cmd, v2payload, sender, 2)
    return
  end

  -- Fall through to v1 handling (backward compat)
  local msgType, payload = message:match("^(%u+):?(.*)")
  if not msgType then return end

  if msgType == "HASH" then
    -- Compare hashes; if different, send a request
    local remoteHash = payload or ""
    local localHash = ComputeBlacklistHash()

    GRIP:Debug("Sync: HASH from", sender, "remote=", remoteHash, "local=", localHash)

    if remoteHash ~= localHash then
      GRIP:Debug("Sync: hashes differ, sending REQ to", sender)
      AceComm:SendCommMessage(SYNC_PREFIX, "REQ", "GUILD")
    end
    return
  end

  if msgType == "REQ" then
    -- Someone requested our data; send it
    local encoded = SerializeBlacklist()
    if encoded then
      GRIP:Debug("Sync: sending DATA in response to REQ from", sender, "bytes=", #encoded)
      AceComm:SendCommMessage(SYNC_PREFIX, "DATA:" .. encoded, "GUILD", nil, SYNC_PRIORITY)
    end
    return
  end

  if msgType == "DATA" then
    local remoteData = DeserializeBlacklist(payload)
    if not remoteData then
      GRIP:Debug("Sync: failed to deserialize DATA from", sender)
      return
    end

    local added = MergeBlacklist(remoteData)
    GRIP:Debug("Sync: merged DATA from", sender, "added=", added)

    if added > 0 then
      GRIP:Info("Sync: added", added, "blacklist entries from", sender)
      GRIP:UpdateUI()
    end
    return
  end
end

-- =========================================================================
-- Broadcast our hash to GUILD (V3 + V2 fallback)
-- =========================================================================
function GRIP:SyncBroadcastHash()
  if not AceComm then return end
  if not _G.GRIPDB or GRIPDB.syncEnabled == false then return end
  if not IsInGuild or not IsInGuild() then return end

  local now = time()
  local lastSync = tonumber(GRIPDB.lastSyncAt) or 0
  if (now - lastSync) < SYNC_COOLDOWN then
    self:Debug("Sync: cooldown active, skipping broadcast (",
      math.floor(SYNC_COOLDOWN - (now - lastSync)), "s remaining)")
    return
  end

  local blHash = ComputeBlacklistHash()
  local tplHash = ComputeTemplateHash()
  local cfgHash = ComputeGMConfigHash()

  -- V3 broadcast (for V3-aware clients)
  local v3msg = format("V3:HASH:%s:%s:%s", blHash, tplHash, cfgHash)
  self:Debug("Sync: broadcasting", v3msg)
  AceComm:SendCommMessage(SYNC_PREFIX, v3msg, "GUILD", nil, SYNC_PRIORITY)

  -- V2 broadcast (backward compat for older GRIP clients)
  local v2msg = format("V2:HASH:%s:%s", blHash, tplHash)
  AceComm:SendCommMessage(SYNC_PREFIX, v2msg, "GUILD", nil, SYNC_PRIORITY)

  GRIPDB.lastSyncAt = now
end

-- =========================================================================
-- Force sync (bypass cooldown)
-- =========================================================================
function GRIP:SyncForceNow()
  if not AceComm then
    self:Print("Sync: libraries not loaded.")
    return
  end
  if not _G.GRIPDB or GRIPDB.syncEnabled == false then
    self:Print("Sync: disabled. Enable with /grip sync on")
    return
  end
  if not IsInGuild or not IsInGuild() then
    self:Print("Sync: not in a guild.")
    return
  end

  -- Reset cooldown so broadcast goes through
  GRIPDB.lastSyncAt = 0
  self:SyncBroadcastHash()
  self:Print("Sync: hash broadcast sent.")
end

-- =========================================================================
-- Init: resolve libraries, register prefix, register callback
-- =========================================================================
function GRIP:InitSync()
  -- Resolve libraries via LibStub
  if not LibStub then
    self:Debug("Sync: LibStub not found, sync disabled.")
    return false
  end

  local ok1, lib1 = pcall(LibStub, LibStub, "AceComm-3.0")
  if not ok1 or not lib1 then
    self:Debug("Sync: AceComm-3.0 not found.")
    return false
  end
  AceComm = lib1

  local ok2, lib2 = pcall(LibStub, LibStub, "LibSerialize")
  if not ok2 or not lib2 then
    self:Debug("Sync: LibSerialize not found.")
    return false
  end
  LibSerialize = lib2

  local ok3, lib3 = pcall(LibStub, LibStub, "LibDeflate")
  if not ok3 or not lib3 then
    self:Debug("Sync: LibDeflate not found.")
    return false
  end
  LibDeflate = lib3

  -- Check if sync is enabled in config
  if not _G.GRIPDB or GRIPDB.syncEnabled == false then
    self:Debug("Sync: disabled in config.")
    return false
  end

  -- Register addon message prefix
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)
  end

  -- Register AceComm callback
  AceComm.RegisterComm(AceComm, SYNC_PREFIX, OnCommReceived)

  -- Schedule initial hash broadcast after startup delay
  if C_Timer and C_Timer.After then
    C_Timer.After(SYNC_STARTUP_DELAY, function()
      if _G.GRIPDB and GRIPDB.syncEnabled ~= false then
        GRIP:SyncBroadcastHash()
      end
    end)
  end

  self:Debug("Sync: initialized (prefix=", SYNC_PREFIX, "delay=", SYNC_STARTUP_DELAY, "s)")
  return true
end

-- =========================================================================
-- Status helper (for /grip sync and UI)
-- =========================================================================
function GRIP:GetSyncStatus()
  local cfg = _G.GRIPDB_CHAR and GRIPDB_CHAR.config
  return {
    enabled = _G.GRIPDB and GRIPDB.syncEnabled ~= false,
    libsLoaded = AceComm ~= nil and LibSerialize ~= nil and LibDeflate ~= nil,
    lastSyncAt = (_G.GRIPDB and tonumber(GRIPDB.lastSyncAt)) or 0,
    inGuild = IsInGuild and IsInGuild() or false,
    blHash = ComputeBlacklistHash(),
    tplHash = ComputeTemplateHash(),
    cfgHash = ComputeGMConfigHash(),
    syncTemplates = cfg and cfg.syncTemplates ~= false or false,
    isGM = GRIP.IsGuildLeader and GRIP:IsGuildLeader() or false,
    gmConfigVersion = (_G.GRIPDB and GRIPDB.gmConfig and tonumber(GRIPDB.gmConfig.version)) or 0,
    gmConfigReceivedVersion = (_G.GRIPDB and GRIPDB.gmConfigReceived
        and tonumber(GRIPDB.gmConfigReceived.version)) or 0,
  }
end
