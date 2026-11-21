-- Stat weights. The presets below are written as points per unit (the main stat is 1; crit and hit
-- per 1%; DPS is weapon damage per second, only on weapons), then shown and edited as importance
-- 0-5 (see ns.NORM). Starting points to tune in /eqt, not gospel.
local _, ns = ...

-- stat keys: what the tooltip line and /eqt item show
ns.STAT_NAMES = {
  STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit",
  ARMOR = "Armor", AP = "Attack Power", RAP = "Ranged Attack Power",
  SP = "Spell Damage", HEAL = "Healing", MP5 = "Mana per 5 sec",
  CRIT = "Crit %", HIT = "Hit %", SPELLCRIT = "Spell Crit %", SPELLHIT = "Spell Hit %",
  DPS = "Weapon DPS", DEF = "Defense", DODGE = "Dodge %", PARRY = "Parry %", BLOCK = "Block %", BLOCKVALUE = "Block Value",
}
ns.STAT_ORDER = { "STR", "AGI", "STA", "INT", "SPI", "AP", "RAP", "SP", "HEAL", "MP5", "CRIT", "HIT",
  "SPELLCRIT", "SPELLHIT", "DPS", "ARMOR", "DEF", "DODGE", "PARRY", "BLOCK", "BLOCKVALUE" }

local MELEE    = { STR = 1, AGI = 0.75, STA = 0.2, AP = 0.5, CRIT = 14, HIT = 12, DPS = 4, ARMOR = 0.01 }
local AGILE    = { AGI = 1, STR = 0.5, STA = 0.2, AP = 0.5, CRIT = 14, HIT = 14, DPS = 4, ARMOR = 0.01 }
local HUNTER   = { AGI = 1, RAP = 0.45, AP = 0.35, STA = 0.2, INT = 0.3, CRIT = 14, HIT = 12, DPS = 4, ARMOR = 0.01 }
local CASTER   = { SP = 1, INT = 0.6, SPI = 0.2, STA = 0.2, SPELLCRIT = 8, SPELLHIT = 10, MP5 = 1, ARMOR = 0.005 }
local HEALER   = { INT = 1, SPI = 0.5, HEAL = 0.6, SP = 0.6, MP5 = 1.5, SPELLCRIT = 6, STA = 0.2, ARMOR = 0.005 }
local TANK     = { STA = 1, ARMOR = 0.05, DEF = 1.2, DODGE = 12, PARRY = 12, BLOCK = 6, BLOCKVALUE = 0.3,
                   STR = 0.5, AGI = 0.6, HIT = 4, DPS = 1 }

-- Weights are importance, 0 (ignore) to 5 (most), the same scale for every stat. Each stat comes
-- in its own unit, so importance is turned into points with a fixed factor: what 1 unit of the
-- stat is worth next to 1 point of a main stat, at full importance (5). E.g. 1% crit ~ 14 Strength.
ns.NORM = { STR = 1, AGI = 1, STA = 1, INT = 1, SPI = 1, AP = 0.5, RAP = 0.4, SP = 1, HEAL = 0.6, MP5 = 2,
  CRIT = 14, HIT = 12, SPELLCRIT = 10, SPELLHIT = 10, DPS = 4, ARMOR = 0.02, DEF = 1.2, DODGE = 12,
  PARRY = 12, BLOCK = 6, BLOCKVALUE = 0.5 }
local function round2(x) return math.floor(x * 100 + 0.5) / 100 end
-- points per unit of a stat, for an importance
function ns.PointsPer(key, importance) return (importance or 0) * (ns.NORM[key] or 0) / 5 end
-- points-per-unit weights (Pawn-style) -> importance 0-5, the top stat at 5; and the factor used
function ns.ToImportance(points)
  local raw, top = {}, 0
  for k, v in pairs(points) do
    if ns.NORM[k] then raw[k] = v / ns.NORM[k]; if raw[k] > top then top = raw[k] end end
  end
  local f = top > 0 and 5 / top or 0
  local out = {}
  for k, v in pairs(raw) do out[k] = round2(v * f) end
  return out, f
end
function ns.ToPoints(importance)
  local out = {}
  for k, v in pairs(importance) do out[k] = ns.PointsPer(k, v) end
  return out
end

local function with(base, changes)
  local t = ns.Copy(base)
  for k, v in pairs(changes or {}) do t[k] = v end
  return t
end

-- [CLASS] = { { spec name, weights } x3, in talent-tree order }
ns.PRESETS = {
  WARRIOR = { { "Arms", MELEE }, { "Fury", MELEE }, { "Protection", TANK } },
  PALADIN = { { "Holy", HEALER }, { "Protection", with(TANK, { SP = 0.3, INT = 0.3 }) },
              { "Retribution", with(MELEE, { INT = 0.3 }) } },
  HUNTER  = { { "Beast Mastery", HUNTER }, { "Marksmanship", HUNTER }, { "Survival", with(HUNTER, { STA = 0.3 }) } },
  ROGUE   = { { "Assassination", AGILE }, { "Combat", AGILE }, { "Subtlety", AGILE } },
  PRIEST  = { { "Discipline", with(HEALER, { SPI = 0.8 }) }, { "Holy", with(HEALER, { SPI = 0.8 }) },
              { "Shadow", with(CASTER, { SPI = 0.4, STA = 0.3 }) } },
  SHAMAN  = { { "Elemental", with(CASTER, { INT = 0.7, SPELLCRIT = 9 }) },
              { "Enhancement", with(MELEE, { INT = 0.25, CRIT = 13 }) },
              { "Restoration", with(HEALER, { MP5 = 1.6 }) } },
  MAGE    = { { "Arcane", CASTER }, { "Fire", CASTER }, { "Frost", CASTER } },
  WARLOCK = { { "Affliction", with(CASTER, { STA = 0.5, INT = 0.5 }) }, { "Demonology", with(CASTER, { STA = 0.6, INT = 0.5 }) },
              { "Destruction", with(CASTER, { STA = 0.5, INT = 0.5, SPELLCRIT = 7 }) } },
  DRUID   = { { "Balance", with(CASTER, { INT = 0.7, SPI = 0.3 }) },
              { "Feral", { AGI = 1, STR = 1, STA = 0.6, ARMOR = 0.03, AP = 0.5, CRIT = 12, HIT = 10, DODGE = 10, DEF = 0.6 } },
              { "Restoration", with(HEALER, { SPI = 0.8 }) } },
}

-- before any talents: the tree most players level in
local LEVELING = { WARRIOR = 1, PALADIN = 3, HUNTER = 1, ROGUE = 2, PRIEST = 3, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 2 }
function ns.DefaultTree(class) return LEVELING[class] or 1 end

function ns.SpecName(key)
  local class, tree = key:match("^(%u+):(%d)$")
  local p = class and ns.PRESETS[class] and ns.PRESETS[class][tonumber(tree)]
  return p and p[1] or key
end

-- What gear is scored with: your active custom scale, else your spec's preset (with your edits)
function ns.CurrentWeights()
  local _, w = ns.Scales.Active()
  if w then return ns.Copy(w) end
  return ns.Weights()
end
-- the label shown with verdicts: the custom scale's name, else the spec's
function ns.ScoringLabel()
  local name = ns.Scales.Active()
  return name or ns.SpecName(ns.SpecKey())
end

-- a spec's preset, as importance (0-5), and the factor it was scaled by
function ns.PresetImportance(key)
  local class, tree = key:match("^(%u+):(%d)$")
  local p = class and ns.PRESETS[class] and ns.PRESETS[class][tonumber(tree)]
  return ns.ToImportance(p and p[2] or MELEE)
end

-- the weights (importance 0-5) in use for a spec: your edits over the preset
function ns.Weights(key)
  key = key or ns.SpecKey()
  local w = ns.PresetImportance(key)
  for k, v in pairs(ns.db.weights[key] or {}) do w[k] = v end
  return w
end
