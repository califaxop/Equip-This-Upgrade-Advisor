-- AuraAPI: buffs and debuffs on the player. Forever hides auras from addons while
-- C_Secrets.ShouldAurasBeSecret() is true (in combat); reading one then throws ("Auras cannot be
-- accessed when secret"), so nothing is read at those times.
local _, ns = ...
local Aura = ns.Module("AuraAPI")
local Compat = ns.Compat

function Aura.Restricted()
  local v, why = Compat.Value("C_Secrets.ShouldAurasBeSecret")
  if why == "missing" then return false end
  return v ~= false   -- (hidden or unknown answer: treat as restricted)
end

-- The aura table at index i ("HELPFUL" or "HARMFUL"), with only readable fields; nil past the last.
local FIELDS = { "name", "spellId", "icon", "applications", "duration", "expirationTime", "sourceUnit",
  "isFromPlayerOrPlayerPet", "isHelpful", "isHarmful", "dispelName", "auraInstanceID" }
function Aura.Get(index, filter)
  local ok, a = Compat.Call("C_UnitAuras.GetAuraDataByIndex", "player", index, filter)
  if not ok then return nil, "error" end
  if a == nil then return nil end
  if a == Compat.SECRET then return { hidden = true } end
  local out = {}
  for _, f in ipairs(FIELDS) do out[f] = Compat.Field(a, f) end
  local pts = Compat.Field(a, "points")
  if type(pts) == "table" then
    out.points = {}
    for i, x in ipairs(pts) do if type(x) == "number" then out.points[i] = x end end
  end
  return out
end
