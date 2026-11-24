-- Stat weights. Each spec starts from Forever Upgrades' weights (Guides.lua); the presets below are
-- the fallback. Both are written as points per unit (the main stat is 1; crit and hit
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
-- What a stat's weight means, in words (the tooltip on each stat in /eqt): at 5 for everyone, then
-- with your weights, measured against the primary stat you weight most.
local PRIMARY = { "STR", "AGI", "INT" }
local function Short(x) x = math.floor(x * 10 + 0.5) / 10; return (x == math.floor(x)) and tostring(x) or format("%.1f", x) end
-- a weight as typed: 3.75 -> "3.75", 4.5 -> "4.5", 5 -> "5"
local function Wt(x) return (format("%.2f", x or 0):gsub("0+$", ""):gsub("%.$", "")) end
local function Unit(key)
  if key == "DPS" then return "+1 weapon DPS" end
  if (ns.STAT_NAMES[key] or ""):find("%%") then return "+1%" end
  return "+1"
end
function ns.WeightInfo(key, weights)
  local lines = {}
  local name = ns.STAT_NAMES[key] or key
  local unit = Unit(key)
  local label = (unit == "+1%" or unit == "+1") and (unit .. " " .. name:gsub(" %%$", "")) or unit
  local isPrimary = key == "STR" or key == "AGI" or key == "INT"
  local at5 = ns.NORM[key] or 0
  if isPrimary then
    lines[1] = format("At 5, %s counts as 1 point: the yardstick the other stats are measured against.", label)
  elseif key == "STA" or key == "SPI" then
    lines[1] = format("At 5, %s counts as 1 point, as much as +1 of a primary stat (Strength, Agility or Intellect) at 5.", label)
  else
    lines[1] = format("At 5, %s counts as much as +%s of a primary stat (Strength, Agility or Intellect) at 5.", label, Short(at5))
  end
  local mine = weights and weights[key] or 0
  local pts = ns.PointsPer(key, mine)
  if pts <= 0 then
    lines[2] = "Your weight is 0: it's ignored."
  else
    -- your most-weighted primary stat
    local best, bestPts
    for _, k in ipairs(PRIMARY) do
      local p = ns.PointsPer(k, weights[k])
      if p > 0 and (not bestPts or p > bestPts) then best, bestPts = k, p end
    end
    if best and best ~= key then
      lines[2] = format("With your weights: %s (%s) is worth as much as +%s %s (%s).", label, Wt(mine), Short(pts / bestPts),
        ns.STAT_NAMES[best], Wt(weights[best]))
    else
      lines[2] = format("With your weight (%s): %s = %s points.", Wt(mine), label, Short(pts))
    end
  end
  if key == "DPS" then lines[#lines + 1] = "Only counts on weapons. Damage procs and extra attacks are counted through this too." end
  lines[#lines + 1] = "0 ignores a stat; 5 means it matters as much as it can."
  return lines
end

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
---------------------------------------------------------------------------
-- Skills: your damage split (auto attack and each skill) comes from Rotation.lua. An item effect on a
-- skill ("+10% Stormstrike") counts by that skill's share of your output: +10% to a skill that's 20% of
-- it is +2% output, and +1% output counts as ns.OUTPUT_PTS points (as much as +1% crit at 5).
---------------------------------------------------------------------------
ns.OUTPUT_PTS = 14
-- Specs without a guide rotation (Rotation.lua) use these: the part of your output from skills (melee
-- ~50%, the rest white hits; hunters ~60%, the rest Auto Shot; casters and healers ~95%), split by weight.
local MELEE_PART, HUNTER_PART, CASTER_PART = 50, 60, 95
ns.SKILL_PART = {
  WARRIOR = { MELEE_PART, MELEE_PART, MELEE_PART }, ROGUE = { MELEE_PART, MELEE_PART, MELEE_PART },
  PALADIN = { CASTER_PART, MELEE_PART, MELEE_PART }, HUNTER = { HUNTER_PART, HUNTER_PART, HUNTER_PART },
  SHAMAN = { CASTER_PART, MELEE_PART, CASTER_PART }, DRUID = { CASTER_PART, MELEE_PART, CASTER_PART },
}

local S5 = function(...) local t = {} for i = 1, select("#", ...), 2 do t[#t + 1] = { (select(i, ...)), (select(i + 1, ...)) } end return t end
ns.PRESET_SKILLS = {
  WARRIOR = { S5("Mortal Strike", 5, "Overpower", 3, "Heroic Strike", 3, "Whirlwind", 2),
              S5("Bloodthirst", 5, "Whirlwind", 4, "Heroic Strike", 3, "Execute", 2),
              S5("Shield Slam", 5, "Revenge", 4, "Sunder Armor", 3, "Heroic Strike", 2) },
  PALADIN = { S5("Holy Light", 5, "Flash of Light", 4, "Holy Shock", 3),
              S5("Holy Shield", 4, "Consecration", 4, "Judgement", 3),
              S5("Judgement", 5, "Seal of Command", 4, "Crusader Strike", 4, "Consecration", 2, "Exorcism", 2) },
  HUNTER  = { S5("Multi-Shot", 4, "Arcane Shot", 3, "Serpent Sting", 2),
              S5("Aimed Shot", 5, "Multi-Shot", 4, "Arcane Shot", 3, "Serpent Sting", 2),
              S5("Multi-Shot", 4, "Arcane Shot", 3, "Serpent Sting", 2, "Raptor Strike", 2) },
  ROGUE   = { S5("Eviscerate", 5, "Sinister Strike", 4, "Rupture", 3),
              S5("Sinister Strike", 5, "Eviscerate", 4, "Slice and Dice", 3),
              S5("Backstab", 5, "Hemorrhage", 4, "Eviscerate", 4) },
  PRIEST  = { S5("Power Word: Shield", 5, "Greater Heal", 4, "Flash Heal", 4, "Renew", 3),
              S5("Greater Heal", 5, "Flash Heal", 4, "Renew", 4, "Prayer of Healing", 3),
              S5("Mind Blast", 5, "Mind Flay", 5, "Shadow Word: Pain", 4) },
  SHAMAN  = { S5("Lightning Bolt", 5, "Chain Lightning", 4, "Earth Shock", 3, "Flame Shock", 3),
              S5("Stormstrike", 5, "Lightning Bolt", 3, "Earth Shock", 2, "Flame Shock", 2),
              S5("Healing Wave", 5, "Chain Heal", 5, "Lesser Healing Wave", 4) },
  MAGE    = { S5("Arcane Missiles", 5, "Arcane Explosion", 3, "Frostbolt", 2),
              S5("Fireball", 5, "Fire Blast", 3, "Scorch", 3, "Pyroblast", 3),
              S5("Frostbolt", 5, "Cone of Cold", 2, "Fire Blast", 2) },
  WARLOCK = { S5("Corruption", 5, "Curse of Agony", 4, "Shadow Bolt", 4, "Drain Life", 2),
              S5("Shadow Bolt", 5, "Corruption", 3, "Immolate", 3),
              S5("Shadow Bolt", 5, "Immolate", 4, "Conflagrate", 3) },
  DRUID   = { S5("Wrath", 5, "Starfire", 5, "Moonfire", 3),
              S5("Shred", 4, "Claw", 4, "Ferocious Bite", 4, "Rip", 3, "Maul", 3),
              S5("Healing Touch", 5, "Rejuvenation", 5, "Regrowth", 4) },
}

-- the label shown with verdicts: the custom scale's name, else the spec's
function ns.ScoringLabel()
  local name = ns.Scales.Active()
  return name or ns.SpecName(ns.SpecKey())
end

-- a spec's preset, as importance (0-5), and the factor it was scaled by
function ns.PresetImportance(key)
  local class, tree = key:match("^(%u+):(%d)$")
  local p = class and ns.PRESETS[class] and ns.PRESETS[class][tonumber(tree)]
  -- Forever Upgrades' stat weights for the spec (Guides.lua), else the built-in ones
  local g = ns.GUIDE and ns.GUIDE[key] and ns.GUIDE[key].weights
  return ns.ToImportance((g and next(g)) and g or (p and p[2]) or MELEE)
end

-- the weights (importance 0-5) in use for a spec: your edits over the preset
function ns.Weights(key)
  key = key or ns.SpecKey()
  local w = ns.PresetImportance(key)
  for k, v in pairs(ns.db.weights[key] or {}) do w[k] = v end
  return w
end
