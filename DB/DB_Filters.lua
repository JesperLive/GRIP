-- Rev 2
-- GRIP – Candidate filtering (excluded zones + allowlists)
--
-- CHANGED (Rev 2):
-- - Nil-safety: tolerate missing GRIPDB/filters tables and nil inputs.
-- - Accept common field variants (raceStr/classStr) defensively.

local ADDON_NAME, GRIP = ...

local function AnySelected(t)
  if type(t) ~= "table" then return false end
  for _, v in pairs(t) do
    if v == true then return true end
  end
  return false
end

function GRIP:FiltersAllowWhoInfo(info)
  if not info then return true end

  -- If DB isn't ready yet, fail-open (don't accidentally filter everything out).
  if not _G.GRIPDB or type(GRIPDB.filters) ~= "table" then
    return true
  end

  local z0 = info.zone or info.area or ""
  if z0 ~= "" and self.ShouldIncludeZoneName and (not self:ShouldIncludeZoneName(z0)) then
    return false
  end

  -- Zones allowlist (if any selected)
  local fz = GRIPDB.filters.zones
  if AnySelected(fz) then
    local z = info.zone or info.area or ""
    if z == "" or not fz[z] then
      return false
    end
  end

  -- Races allowlist
  local fr = GRIPDB.filters.races
  if AnySelected(fr) then
    local r = info.race or info.raceStr or ""
    if r == "" or not fr[r] then
      return false
    end
  end

  -- Classes allowlist
  local fc = GRIPDB.filters.classes
  if AnySelected(fc) then
    local c = info.class or info.classStr or ""
    if c == "" or not fc[c] then
      return false
    end
  end

  return true
end