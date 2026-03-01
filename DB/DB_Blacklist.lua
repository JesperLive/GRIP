-- GRIP: DB Blacklist
-- Temp/perm blacklist, BL_ExecutionGate (last-line defense), no-response counters.

local ADDON_NAME, GRIP = ...

local function EnsureBlacklistTables()
  if not _G.GRIPDB then _G.GRIPDB = {} end
  GRIPDB.blacklist = GRIPDB.blacklist or {}
  GRIPDB.blacklistPerm = GRIPDB.blacklistPerm or {}
  GRIPDB.counters = GRIPDB.counters or { noResponse = {} }
  GRIPDB.counters.noResponse = GRIPDB.counters.noResponse or {}
end

local function NormalizePermEntry(v)
  if v == true then
    return { at = 0, reason = "permanent" }
  end
  if type(v) == "table" then
    v.at = tonumber(v.at) or 0
    v.reason = tostring(v.reason or "permanent")
    return v
  end
  return nil
end

-- Normalize "FullName-Realm" and "FullName" behavior at the gate.
-- If callers pass "Name" without realm, we still check:
--   1) exact
--   2) Name-Realm (if realm available)
--   3) Name (base) when fullName includes "-Realm"
local function CollectBlacklistKeys(self, fullName)
  local keys = { fullName }

  -- Expand base/full variants for safety.
  local nameOnly, realm = strsplit("-", fullName)
  if nameOnly and nameOnly ~= "" then
    if realm and realm ~= "" then
      -- fullName likely already has realm; also check base
      if nameOnly ~= fullName then
        keys[#keys + 1] = nameOnly
      end
    else
      -- No realm in input; if we know player realm, also check Name-Realm
      local myRealm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
      if myRealm and myRealm ~= "" then
        keys[#keys + 1] = nameOnly .. "-" .. myRealm
      end
    end
  end

  -- Deduplicate
  local seen, out = {}, {}
  for _, k in ipairs(keys) do
    if k and k ~= "" and not seen[k] then
      seen[k] = true
      out[#out + 1] = k
    end
  end
  return out
end

-- ------------------------------------------------------------
-- Trace helpers (safe)
-- ------------------------------------------------------------
local function IsGateTraceEnabled(self, context)
  -- Opt-in via context table:
  if type(context) == "table" then
    if context.trace == true or context.traceGate == true then
      return true
    end
  end

  -- Opt-in via config flag:
  if _G.GRIPDB and type(GRIPDB.config) == "table" and GRIPDB.config.traceExecutionGate == true then
    return true
  end

  return false
end

local function ContextToString(context)
  if context == nil then return "" end
  if type(context) == "string" or type(context) == "number" or type(context) == "boolean" then
    return tostring(context)
  end
  if type(context) ~= "table" then
    return tostring(context)
  end

  -- Shallow, stable-ish representation; avoids recursion/surprises.
  local parts, n = {}, 0
  for k, v in pairs(context) do
    n = n + 1
    if n > 12 then
      parts[#parts + 1] = "…"
      break
    end
    local kk = tostring(k)
    local vv
    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" then
      vv = tostring(v)
    else
      vv = "<" .. tv .. ">"
    end
    parts[#parts + 1] = kk .. "=" .. vv
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ",") .. "}"
end

local function GetBlacklistHit(self, key)
  -- Returns:
  --   kind: "perm" | "temp" | nil
  --   remaining: number (seconds) for temp, else nil
  EnsureBlacklistTables()

  if _G.GRIPDB and type(GRIPDB.blacklistPerm) == "table" and GRIPDB.blacklistPerm[key] ~= nil then
    -- Treat any present perm entry as a perm hit (legacy boolean tolerated elsewhere)
    return "perm", nil
  end

  if _G.GRIPDB and type(GRIPDB.blacklist) == "table" then
    local exp = GRIPDB.blacklist[key]
    if type(exp) == "number" then
      local now = self:Now()
      if exp > now then
        return "temp", math.max(0, math.floor(exp - now))
      end
    end
  end

  return nil, nil
end

-- Unified trace emission:
-- - If trace mode is enabled and GateTrace exists, use it (prints even if debug is off).
-- - Otherwise, fall back to Debug() when available (respects debug enable/verbosity).
local function EmitGateLog(self, traceEnabled, ...)
  if traceEnabled and self and self.GateTrace then
    self:GateTrace(...)
    return
  end
  if self and self.Debug then
    self:Debug(...)
  end
end

function GRIP:IsPermanentlyBlacklisted(fullName)
  if not fullName or fullName == "" then return false end
  if not _G.GRIPDB or type(GRIPDB.blacklistPerm) ~= "table" then return false end

  local v = GRIPDB.blacklistPerm[fullName]
  if v == nil then return false end

  local norm = NormalizePermEntry(v)
  if not norm then
    -- Unknown junk value; remove it
    GRIPDB.blacklistPerm[fullName] = nil
    return false
  end

  -- If this was a legacy boolean, normalize it on-read so future code can rely on shape.
  if v == true then
    GRIPDB.blacklistPerm[fullName] = norm
  end

  return true
end

function GRIP:BlacklistPermanent(fullName, reason)
  if not fullName or fullName == "" then return end
  EnsureBlacklistTables()

  -- store a little metadata (safe for future UI)
  GRIPDB.blacklistPerm[fullName] = {
    at = self:Now(),
    reason = tostring(reason or "permanent"),
  }

  self:Debug("Blacklist PERM set:", fullName, "reason=", tostring(reason or "permanent"))
end

function GRIP:UnblacklistPermanent(fullName)
  if not fullName or fullName == "" then return false end
  EnsureBlacklistTables()

  if GRIPDB.blacklistPerm[fullName] ~= nil then
    GRIPDB.blacklistPerm[fullName] = nil
    self:Debug("Blacklist PERM removed:", fullName)
    return true
  end
  return false
end

function GRIP:ClearPermanentBlacklist()
  EnsureBlacklistTables()

  local removed = self:Count(GRIPDB.blacklistPerm)
  wipe(GRIPDB.blacklistPerm)

  self:Debug("Blacklist PERM cleared:", removed)
  return removed
end

function GRIP:GetPermanentBlacklistNames()
  EnsureBlacklistTables()

  local names = {}
  local junk = {}
  for name, v in pairs(GRIPDB.blacklistPerm) do
    local norm = NormalizePermEntry(v)
    if norm ~= nil then
      names[#names + 1] = name
      -- normalize legacy boolean entries as we discover them
      if v == true then
        GRIPDB.blacklistPerm[name] = norm
      end
    else
      junk[#junk + 1] = name
    end
  end
  for _, name in ipairs(junk) do
    GRIPDB.blacklistPerm[name] = nil
  end
  table.sort(names)
  return names
end

function GRIP:IsBlacklisted(fullName)
  if not fullName or fullName == "" then return false end
  EnsureBlacklistTables()

  if GRIPDB.blacklistPerm[fullName] ~= nil then
    -- Keep it simple here; IsPermanentlyBlacklisted() is the hardened version if you want cleanup.
    return true
  end

  local exp = GRIPDB.blacklist[fullName]
  if not exp then return false end

  if type(exp) ~= "number" then
    -- unknown junk value; remove it
    GRIPDB.blacklist[fullName] = nil
    return false
  end

  if exp <= self:Now() then
    GRIPDB.blacklist[fullName] = nil
    return false
  end

  return true
end

-- ------------------------------------------------------------
-- Centralized "last-line defense" execution gate
-- ------------------------------------------------------------
-- Returns:
--   ok:boolean    true => allowed to execute; false => MUST NOT execute
--   reason:string diagnostic for logs/UI
--
-- IMPORTANT:
-- - This function MUST be called immediately before any whisper/invite/recruit/post-to execution.
-- - It does not perform any Blizzard-restricted action; it only blocks.
-- - Behavior is conservative: if any reasonable key variant is blacklisted, execution is blocked.
function GRIP:BL_ExecutionGate(fullName, context)
  if not fullName or fullName == "" then
    return false, "missing-name"
  end
  EnsureBlacklistTables()

  local trace = IsGateTraceEnabled(self, context)
  local ctxStr = trace and ContextToString(context) or nil

  local keys = CollectBlacklistKeys(self, fullName)
  for _, k in ipairs(keys) do
    if self:IsBlacklisted(k) then
      -- Identify perm vs temp + remaining seconds (temp) without changing behavior.
      local kind, remaining = GetBlacklistHit(self, k)
      local variant = (k == fullName) and "input" or "expanded"
      local ctxOut = tostring(ctxStr or context or "")

      if kind == "temp" then
        EmitGateLog(
          self,
          trace,
          "EXECUTION GATE blocked:",
          "key=", tostring(k),
          "variant=", variant,
          "kind=temp",
          "remaining_s=", tostring(remaining or 0),
          "ctx=", ctxOut
        )
      elseif kind == "perm" then
        EmitGateLog(
          self,
          trace,
          "EXECUTION GATE blocked:",
          "key=", tostring(k),
          "variant=", variant,
          "kind=perm",
          "ctx=", ctxOut
        )
      else
        -- Fallback (should be rare): treat as blacklisted with unknown kind.
        EmitGateLog(
          self,
          trace,
          "EXECUTION GATE blocked:",
          "key=", tostring(k),
          "variant=", variant,
          "kind=unknown",
          "ctx=", ctxOut
        )
      end

      return false, "blacklisted"
    end
  end

  return true, "ok"
end

function GRIP:PurgeBlacklist(opts)
  EnsureBlacklistTables()
  opts = type(opts) == "table" and opts or {}

  local now = self:Now()
  local removed = 0
  local toRemove = {}
  for name, exp in pairs(GRIPDB.blacklist) do
    if type(exp) ~= "number" or exp <= now then
      toRemove[#toRemove + 1] = name
    end
  end
  for _, name in ipairs(toRemove) do
    GRIPDB.blacklist[name] = nil
    removed = removed + 1
  end
  if removed > 0 then
    self:Debug("PurgeBlacklist removed:", removed)
  end

  -- Optional hygiene: prune noResponse counters if they're not in potential anymore.
  -- IMPORTANT: only do this when Potential table exists, otherwise we'd risk wiping counters during early init.
  if opts.pruneNoResponse
    and GRIPDB.counters and type(GRIPDB.counters.noResponse) == "table"
    and _G.GRIPDB and type(GRIPDB.potential) == "table"
  then
    local pruned = 0
    local pot = GRIPDB.potential
    local stale = {}
    for name in pairs(GRIPDB.counters.noResponse) do
      if not pot[name] then
        stale[#stale + 1] = name
      end
    end
    for _, name in ipairs(stale) do
      GRIPDB.counters.noResponse[name] = nil
      pruned = pruned + 1
    end
    if pruned > 0 then
      self:Debug("PurgeBlacklist pruned noResponse counters:", pruned)
    end
  end
end

function GRIP:Blacklist(fullName, days)
  if not fullName or fullName == "" then return end
  EnsureBlacklistTables()

  days = tonumber(days) or (GRIPDB.config and GRIPDB.config.blacklistDays) or 7
  days = self:Clamp(days, 1, 365)

  local exp = self:Now() + (days * 86400)
  GRIPDB.blacklist[fullName] = exp

  self:Debug("Blacklist set:", fullName, "days=", days, "expires=", date("%Y-%m-%d %H:%M:%S", exp))
end

function GRIP:BlacklistForSeconds(fullName, seconds)
  if not fullName or fullName == "" then return end
  EnsureBlacklistTables()

  seconds = tonumber(seconds) or 0
  if seconds < 1 then seconds = 1 end

  local exp = self:Now() + seconds
  GRIPDB.blacklist[fullName] = exp

  self:Debug("Blacklist set (seconds):", fullName, "secs=", seconds, "expires=", date("%Y-%m-%d %H:%M:%S", exp))
end

-- ------------------------------------------------------------
-- No-response counters (Invite module escalation)
-- ------------------------------------------------------------
function GRIP:GetNoResponseCount(fullName)
  if not fullName or fullName == "" then return 0 end
  EnsureBlacklistTables()
  return tonumber(GRIPDB.counters.noResponse[fullName]) or 0
end

function GRIP:ResetNoResponseCount(fullName)
  if not fullName or fullName == "" then return false end
  EnsureBlacklistTables()
  if GRIPDB.counters.noResponse[fullName] ~= nil then
    GRIPDB.counters.noResponse[fullName] = nil
    return true
  end
  return false
end