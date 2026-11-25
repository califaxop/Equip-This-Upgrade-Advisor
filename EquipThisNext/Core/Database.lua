-- Database: saved settings (EquipThisNextDB). Snapshots taken with /eqn dump are kept per
-- character so they can be copied out of the SavedVariables file and used as test fixtures.
local _, ns = ...
local DB = ns.Module("Database")

DB.DEFAULTS = {
  debug = false,
  snapshots = {},   -- ["Name-Realm"] = { taken = time, profile = CharacterProfile }
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
DB.Copy = copy

function DB.Load()
  EquipThisNextDB = EquipThisNextDB or {}
  for k, v in pairs(DB.DEFAULTS) do
    if EquipThisNextDB[k] == nil then EquipThisNextDB[k] = copy(v) end
  end
  ns.db = EquipThisNextDB
end
