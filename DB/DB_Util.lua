-- Rev 2
-- GRIP – DB utilities (shared helpers)
--
-- CHANGED (Rev 2):
-- - Harden Merge against accidental self-referential tables (cycle guard).
-- - Add minimal type safety for list helpers to avoid SV-corruption crashes.

local ADDON_NAME, GRIP = ...

GRIP.DBUtil = GRIP.DBUtil or {}
local U = GRIP.DBUtil

function U.Merge(dst, src, _seen)
  if type(dst) ~= "table" or type(src) ~= "table" then return end
  _seen = _seen or {}
  if _seen[src] then return end
  _seen[src] = true

  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      U.Merge(dst[k], v, _seen)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function U.EnsureInList(list, value)
  if type(list) ~= "table" then return end
  if not value or value == "" then return end
  for _, v in ipairs(list) do
    if v == value then return end
  end
  list[#list + 1] = value
end

function U.SortUnique(list)
  if type(list) ~= "table" then return {} end
  table.sort(list)
  local out = {}
  local last
  for _, v in ipairs(list) do
    if v ~= last then
      out[#out + 1] = v
      last = v
    end
  end
  return out
end

function U.PruneFilterKeys(filterTbl, validList)
  if type(filterTbl) ~= "table" or type(validList) ~= "table" then return end
  local valid = {}
  for _, v in ipairs(validList) do valid[v] = true end
  for k in pairs(filterTbl) do
    if not valid[k] then
      filterTbl[k] = nil
    end
  end
end

function U.AnySelected(t)
  if type(t) ~= "table" then return false end
  for _, v in pairs(t) do
    if v == true then return true end
  end
  return false
end