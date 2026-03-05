-- GRIP: Sync
-- Officer blacklist sync via AceComm-3.0 over GUILD channel (set-union merge).

local ADDON_NAME, GRIP = ...

-- Lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs, pcall, wipe = pairs, pcall, wipe
local format = string.format
local time = time

-- Constants
local SYNC_PREFIX       = "GRIP"
local SYNC_COOLDOWN     = 3600    -- 1 hour between broadcasts
local SYNC_STARTUP_DELAY = 10     -- seconds after ADDON_LOADED before first broadcast
local SYNC_PRIORITY     = "BULK"  -- ChatThrottleLib priority (queues at ~1/sec)

-- Library handles (resolved at init)
local AceComm
local LibSerialize
local LibDeflate

-- =========================================================================
-- Hash helper — deterministic hash of the permanent blacklist
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

-- =========================================================================
-- Serialize + compress the permanent blacklist
-- =========================================================================
local function SerializeBlacklist()
  if not LibSerialize or not LibDeflate then return nil end
  if not _G.GRIPDB or type(GRIPDB.blacklistPerm) ~= "table" then return nil end

  local ok, serialized = pcall(LibSerialize.Serialize, LibSerialize, GRIPDB.blacklistPerm)
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
    GRIP:Debug("Sync: encode failed")
    return nil
  end

  return encoded
end

-- =========================================================================
-- Deserialize + decompress incoming blacklist data
-- =========================================================================
local function DeserializeBlacklist(encoded)
  if not LibSerialize or not LibDeflate then return nil end
  if type(encoded) ~= "string" or encoded == "" then return nil end

  local compressed = LibDeflate:DecodeForWoWAddonChannel(encoded)
  if not compressed then
    GRIP:Debug("Sync: decode failed")
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

  -- Parse message type
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
-- Broadcast our hash to GUILD
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

  local hash = ComputeBlacklistHash()
  self:Debug("Sync: broadcasting HASH:", hash)

  AceComm:SendCommMessage(SYNC_PREFIX, "HASH:" .. hash, "GUILD", nil, SYNC_PRIORITY)
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
  local enabled = _G.GRIPDB and GRIPDB.syncEnabled ~= false
  local libsOk = AceComm ~= nil and LibSerialize ~= nil and LibDeflate ~= nil
  local lastSync = (_G.GRIPDB and tonumber(GRIPDB.lastSyncAt)) or 0
  local inGuild = IsInGuild and IsInGuild() or false

  return {
    enabled = enabled,
    libsLoaded = libsOk,
    lastSyncAt = lastSync,
    inGuild = inGuild,
    hash = ComputeBlacklistHash(),
  }
end
