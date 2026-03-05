-- GRIP: Raider.IO Integration
-- Optional M+ score lookup via Raider.IO addon API (FE3).

local ADDON_NAME, GRIP = ...

-- WoW API
local GetNormalizedRealmName = GetNormalizedRealmName

-- Check if Raider.IO addon is available
function GRIP:IsRaiderIOAvailable()
  return _G.RaiderIO and type(_G.RaiderIO.GetProfile) == "function"
end

-- Get M+ score for a player. Returns number or nil.
-- fullName: "Name-Realm" format
function GRIP:GetRaiderIOScore(fullName)
  if not self:IsRaiderIOAvailable() then return nil end

  local name, realm = fullName:match("^([^%-]+)%-(.+)$")
  if not name then
    name = fullName
    realm = GetNormalizedRealmName()
  end
  if not name or not realm then return nil end

  local profile = _G.RaiderIO.GetProfile(name, realm)
  if not profile then return nil end

  local mkp = profile.mythicKeystoneProfile
  if not mkp or not mkp.hasRenderableData then return nil end

  return mkp.currentScore or nil
end

-- Filter check: does this candidate pass the M+ score threshold?
-- Returns true if candidate passes (or if RIO not available/no threshold set).
function GRIP:RaiderIOFilterAllows(fullName)
  local cfg = self:GetCfg()
  if not cfg then return true end

  local minScore = cfg.rioMinScore or 0
  if minScore <= 0 then return true end  -- filter disabled
  if not self:IsRaiderIOAvailable() then return true end  -- no RIO = skip filter

  local score = self:GetRaiderIOScore(fullName)
  if score == nil then return true end  -- no data = don't block

  return score >= minScore
end
