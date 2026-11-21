-- Custom scales: your own named stat weights (theorycrafting), chosen instead of the spec preset.
-- Shared as Pawn-style strings:  ( Pawn: v1: "Name": Strength=1, Agility=0.8, CritRating=14 )
local _, ns = ...
local Sc = {}
ns.Scales = Sc

-- Pawn stat names <-> ours. First name per stat is the one used when exporting.
local PAWN = {
  { "STR", "Strength" }, { "AGI", "Agility" }, { "STA", "Stamina" }, { "INT", "Intellect" }, { "SPI", "Spirit" },
  { "ARMOR", "Armor" }, { "AP", "Ap", "AttackPower" }, { "RAP", "Rap", "RangedAttackPower" },
  { "SP", "SpellDamage", "SpellPower" }, { "HEAL", "Healing" }, { "MP5", "Mp5" },
  { "CRIT", "CritRating", "Crit" }, { "HIT", "HitRating", "Hit" },
  { "SPELLCRIT", "SpellCritRating", "SpellCrit" }, { "SPELLHIT", "SpellHitRating", "SpellHit" },
  { "DPS", "Dps", "MeleeDps", "MainHandDps", "RangedDps" },
  { "DEF", "DefenseRating", "Defense" }, { "DODGE", "DodgeRating", "Dodge" }, { "PARRY", "ParryRating", "Parry" },
  { "BLOCK", "BlockRating", "Block" }, { "BLOCKVALUE", "BlockValue" },
}
local FROM_PAWN, TO_PAWN = {}, {}
for _, row in ipairs(PAWN) do
  TO_PAWN[row[1]] = row[2]
  for i = 2, #row do FROM_PAWN[row[i]:lower()] = row[1] end
end

-- the scale in use: its name and weights, or nil when the spec preset is in use
function Sc.Active()
  local name = ns.db.scale
  local w = name and ns.db.scales[name]
  if w then return name, w end
  return nil
end

function Sc.Names()
  local t = {}
  for name in pairs(ns.db.scales) do t[#t + 1] = name end
  table.sort(t)
  return t
end

-- a new scale named `name` (made unique), starting from `weights`; it becomes the active one
function Sc.Create(name, weights)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = "My scale" end
  local base, n = name, 2
  while ns.db.scales[name] do name = format("%s %d", base, n); n = n + 1 end
  ns.db.scales[name] = ns.Copy(weights or {})
  ns.db.scale = name
  return name
end

function Sc.Delete(name)
  ns.db.scales[name] = nil
  if ns.db.scale == name then ns.db.scale = nil end
end

-- "( Pawn: v1: "Name": Strength=1, ... )" -> name, weights, ignored stat names (or nil, why)
function Sc.Parse(text)
  if type(text) ~= "string" or not text:find("Pawn") then return nil, "that isn't a Pawn-style scale string" end
  local name = text:match('v%d+:%s*"([^"]+)"') or "Imported scale"
  local body = text:match('v%d+:%s*"[^"]*"%s*:(.*)') or text
  local weights, ignored, count = {}, {}, 0
  for k, v in body:gmatch("([%a_]+)%s*=%s*(%-?[%d%.]+)") do
    local key = FROM_PAWN[k:lower()]
    local num = tonumber(v)
    if key and num then
      weights[key] = num; count = count + 1
    elseif num and k:lower() ~= "class" and k:lower() ~= "spec" then
      ignored[#ignored + 1] = k
    end
  end
  if count == 0 then return nil, "no stats it knows were found in it" end
  return name, ns.ToImportance(weights), ignored -- Pawn values are points per unit
end

-- a scale as a Pawn-style string
function Sc.Export(name, weights)
  local parts = {}
  for _, key in ipairs(ns.STAT_ORDER) do
    local v = ns.PointsPer(key, weights[key]) -- importance -> points per unit, as Pawn expects
    if v ~= 0 then parts[#parts + 1] = format("%s=%s", TO_PAWN[key], tostring(math.floor(v * 1000 + 0.5) / 1000)) end
  end
  return format('( Pawn: v1: "%s": %s )', name, table.concat(parts, ", "))
end
