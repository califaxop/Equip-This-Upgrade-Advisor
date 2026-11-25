-- Stat values: what each stat is worth to you, in points per unit (the spec's main stat at 1; crit, hit
-- and the like per 1%; DPS is a weapon's damage per second). They start from Forever Upgrades' weights
-- for your spec (its simulator's own measure of what each stat does for the spec's DPS, HPS or effective
-- health), scaled by your talents (Talents.lua), with your own changes on top. Your build then mixes
-- damage (or healing) with survival (Score.lua).
local _, ns = ...

-- stat keys: what the tooltip line and /eqt item show
ns.STAT_NAMES = {
  STR = "Strength", AGI = "Agility", STA = "Stamina", HEALTH = "Health", INT = "Intellect", SPI = "Spirit",
  ARMOR = "Armor", AP = "Attack Power", RAP = "Ranged Attack Power",
  SP = "Spell Damage", HEAL = "Healing", MP5 = "Mana per 5 sec",
  CRIT = "Crit %", HIT = "Hit %", HASTE = "Haste %", EXPERTISE = "Expertise %", SPELLPEN = "Spell Penetration",
  HP5 = "Health per 5 sec", SPELLCRIT = "Spell Crit %", SPELLHIT = "Spell Hit %",
  DPS = "Weapon DPS", DEF = "Defense", DODGE = "Dodge %", PARRY = "Parry %", BLOCK = "Block %", BLOCKVALUE = "Block Value",
  RES_FIRE = "Fire Resistance", RES_FROST = "Frost Resistance", RES_NATURE = "Nature Resistance",
  RES_SHADOW = "Shadow Resistance", RES_ARCANE = "Arcane Resistance", RES_HOLY = "Holy Resistance",
}
ns.STAT_ORDER = { "STR", "AGI", "STA", "HEALTH", "INT", "SPI", "AP", "RAP", "SP", "HEAL", "MP5", "HP5", "CRIT", "HIT", "HASTE", "EXPERTISE",
  "SPELLCRIT", "SPELLHIT", "SPELLPEN", "DPS", "ARMOR", "DEF", "DODGE", "PARRY", "BLOCK", "BLOCKVALUE",
  "RES_FIRE", "RES_FROST", "RES_NATURE", "RES_SHADOW", "RES_ARCANE" }

local MELEE    = { STR = 1, AGI = 0.75, STA = 0.2, AP = 0.5, CRIT = 14, HIT = 12, DPS = 4, ARMOR = 0.01 }
local AGILE    = { AGI = 1, STR = 0.5, STA = 0.2, AP = 0.5, CRIT = 14, HIT = 14, DPS = 4, ARMOR = 0.01 }
local HUNTER   = { AGI = 1, RAP = 0.45, AP = 0.35, STA = 0.2, INT = 0.3, CRIT = 14, HIT = 12, DPS = 4, ARMOR = 0.01 }
local CASTER   = { SP = 1, INT = 0.6, SPI = 0.2, STA = 0.2, SPELLCRIT = 8, SPELLHIT = 10, MP5 = 1, ARMOR = 0.005 }
local HEALER   = { INT = 1, SPI = 0.5, HEAL = 0.6, SP = 0.6, MP5 = 1.5, SPELLCRIT = 6, STA = 0.2, ARMOR = 0.005 }
local TANK     = { STA = 1, ARMOR = 0.05, DEF = 1.2, DODGE = 12, PARRY = 12, BLOCK = 6, BLOCKVALUE = 0.3,
                   STR = 0.5, AGI = 0.6, HIT = 4, DPS = 1 }

-- What 1 unit of a stat is worth next to 1 point of a main stat, for a typical spec: only used to
-- compare stats in different units (Higher / Highest: "halfway to your most valued stat").
ns.NORM = { STR = 1, AGI = 1, STA = 1, HEALTH = 0.1, INT = 1, SPI = 1, AP = 0.5, RAP = 0.4, SP = 1, HEAL = 0.6, MP5 = 2,
  CRIT = 14, HIT = 12, HASTE = 10, EXPERTISE = 12, SPELLPEN = 1, HP5 = 2, SPELLCRIT = 10, SPELLHIT = 10, DPS = 4, ARMOR = 0.02, DEF = 1.2, DODGE = 12,
  PARRY = 12, BLOCK = 6, BLOCKVALUE = 0.5 }
local PRIMARY = { "STR", "AGI", "INT" }
local function Short(x) x = math.floor(x * 100 + 0.5) / 100; return (x == math.floor(x)) and tostring(x) or (format("%.2f", x):gsub("0$", "")) end
ns.Short = Short
local function Unit(key)
  if key == "DPS" then return "per 1 weapon DPS" end
  if (ns.STAT_NAMES[key] or ""):find("%%") then return "per 1%" end
  return "per point"
end
ns.UnitOf = Unit
-- (weights are points per unit now; older code asks for them through this)
function ns.PointsPer(_, w) return w or 0 end

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

---------------------------------------------------------------------------
-- Skills: your damage split (auto attack and each skill) comes from Rotation.lua. An item effect on a
-- skill ("+10% Stormstrike") counts by that skill's share of your output: +10% to a skill that's 20% of
-- it is +2% output, and +1% output counts as ns.OUTPUT_PTS points (as much as +1% crit at 5).
---------------------------------------------------------------------------
ns.OUTPUT_PTS = 14 -- (set for each scoring: 1% of your gear's score, Score.lua)
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

-- a spec's weights from Forever Upgrades (Guides.lua), else the built-in ones: points per unit
function ns.SiteWeights(key)
  local class, tree = key:match("^(%u+):(%d)$")
  local p = class and ns.PRESETS[class] and ns.PRESETS[class][tonumber(tree)]
  local g = ns.GUIDE and ns.GUIDE[key] and ns.GUIDE[key].weights
  local w = ns.Copy((g and next(g)) and g or (p and p[2]) or MELEE)
  w.HEALTH = w.HEALTH or (w.STA and w.STA / 10) -- (10 Health = 1 Stamina)
  return w
end

-- the spec's role on Forever Upgrades: "melee", "caster", "ranged", "healer" or "tank"
function ns.Role(key)
  key = key or ns.SpecKey()
  local g = ns.GUIDE and ns.GUIDE[key]
  if g and g.role then return g.role end
  return (ns.PRESETS[key:match("^(%u+)")] and key:match(":(%d)$") and "melee") or "melee"
end
-- a tank: a tank spec, or "I tank" ticked for your spec (a shaman or a Retribution paladin tanking)
function ns.IsTankSpec(key) return ns.Role(key) == "tank" end
function ns.IsTank(key)
  key = key or ns.SpecKey()
  if ns.IsTankSpec(key) then return true end
  local p = ns.db and ns.db.priorities and ns.db.priorities[key]
  return p and p.tank and true or false
end
function ns.SetTanking(on, key)
  key = key or ns.SpecKey()
  local p = ns.Copy(ns.Priorities(key))
  p.tank = on and true or nil
  ns.db.priorities = ns.db.priorities or {}
  ns.db.priorities[key] = p
end
---------------------------------------------------------------------------
-- Your build: what you want more of, in two layers.
--  1. How damage (or healing) and survival mix. A tank's own weights are survival (effective health)
--     and its damage comes from the class's damage spec. Builds: Damage, Leveling, Balanced, Survival
--     (Tanking for tanks), or your own mix. Auto: Leveling until the level cap, then Damage (tanks:
--     Tanking).
--  2. Your own values, stat by stat, on top: a number of your own, or Ignore / Higher (halfway to your
--     most valued stat) / Highest (above every other stat). Default leaves the stat as Forever
--     Upgrades has it for you (with your talents).
---------------------------------------------------------------------------
ns.LEVELS = { { "goal", "Default" }, { "ignore", "Ignore" }, { "higher", "Higher" }, { "highest", "Highest" }, { "custom", "Your value" } }
local LEVEL_NAME = {}
for _, l in ipairs(ns.LEVELS) do LEVEL_NAME[l[1]] = l[2] end
ns.LEVEL_NAME = LEVEL_NAME

-- { id, name, survival share (non-tanks), survival share (tanks), description }
ns.BUILDS = {
  { "auto", "Auto", nil, nil, "Leveling until the level cap, then Damage (tanks: Tanking). Switches by itself." },
  { "damage", "Damage", 0, 0, "All damage (or healing): Forever Upgrades' values for your spec." },
  { "leveling", "Leveling", 0.25, 0.5, "Mostly damage, with a quarter survival (health and armor): easier fights while you level. Tanks: half and half." },
  { "balanced", "Balanced", 0.5, 0.75, "Half damage, half survival." },
  { "survival", "Survival", 1, 1, "All survival: effective health from Stamina, health and armor (tanks: Forever Upgrades' tanking values)." },
  { "custom", "Your mix", nil, nil, "Your own mix of damage and survival (the slider)." },
}
local BUILD = {}
for _, b in ipairs(ns.BUILDS) do BUILD[b[1]] = b end
function ns.BuildName(id, key)
  if id == "survival" and ns.IsTank(key) then return "Tanking" end
  return BUILD[id] and BUILD[id][2] or id
end

-- the level cap (Auto switches there)
function ns.MaxLevel()
  local cap = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or (GetMaxPlayerLevel and GetMaxPlayerLevel())
  return (type(cap) == "number" and cap > 0) and cap or 60
end

-- your choices for a spec: { build = "auto" | "damage" | ..., survival = 0-1 (your mix), levels = { STAT = level },
-- values = { STAT = your number } }
local OLD_GOAL = { mana = "damage", custom = "damage" } -- (2.5-3.x goals)
function ns.Priorities(key)
  key = key or ns.SpecKey()
  ns.db.priorities = ns.db.priorities or {}
  local p = ns.db.priorities[key]
  if p and p.goal then p.build = OLD_GOAL[p.goal] or p.goal; p.goal = nil end
  -- (stat levels and values of your own, from older versions: no more; the slider is the control)
  if p then p.levels = {}; p.values = {} end
  return p or { build = "auto", levels = {}, values = {} }
end
local function Save(key, p) ns.db.priorities = ns.db.priorities or {}; ns.db.priorities[key] = p end

-- the build in effect (Auto as Leveling / Damage / Tanking), and whether it came from Auto
function ns.Build(key)
  key = key or ns.SpecKey()
  local b = ns.Priorities(key).build or "auto"
  if b == "auto" then
    local level = UnitLevel and UnitLevel("player") or 1
    if level < ns.MaxLevel() then return "leveling", true end
    return ns.IsTank(key) and "survival" or "damage", true
  end
  return b, false
end
function ns.SetBuild(id, key)
  key = key or ns.SpecKey()
  local p = ns.Copy(ns.Priorities(key))
  if id == "custom" and p.survival == nil then p.survival = ns.SurvivalShare(key) end
  p.build = id
  Save(key, p)
end
-- how much of your build is survival, 0-1
function ns.SurvivalShare(key)
  key = key or ns.SpecKey()
  local b = ns.Build(key)
  if b == "custom" then return math.max(0, math.min(1, ns.Priorities(key).survival or 0)) end
  local e = BUILD[b]
  return e and ((ns.IsTank(key) and e[4]) or e[3]) or 0
end
function ns.SetSurvivalShare(x, key)
  key = key or ns.SpecKey()
  local p = ns.Copy(ns.Priorities(key))
  p.build, p.survival = "custom", math.max(0, math.min(1, x))
  Save(key, p)
end

function ns.Level(stat, key)
  local p = ns.Priorities(key)
  if p.values[stat] then return "custom" end
  return p.levels[stat] or "goal"
end
function ns.SetLevel(stat, level, key)
  key = key or ns.SpecKey()
  local p = ns.Copy(ns.Priorities(key))
  p.levels[stat] = (level ~= "goal" and level ~= "custom") and level or nil
  if level ~= "custom" then p.values[stat] = nil
  elseif not p.values[stat] then p.values[stat] = ns.Weights(key)[stat] or 0 end
  Save(key, p)
end
-- your own number for a stat (nil: back to Default)
function ns.SetValue(stat, v, key)
  key = key or ns.SpecKey()
  local p = ns.Copy(ns.Priorities(key))
  p.values[stat] = (type(v) == "number" and v >= 0) and v or nil
  p.levels[stat] = nil
  Save(key, p)
end
function ns.HasChanges() return false end
-- (back to Auto; "I tank" stays)
function ns.ResetPriorities(key)
  key = key or ns.SpecKey()
  if not ns.db.priorities then return end
  local tank = ns.db.priorities[key] and ns.db.priorities[key].tank
  ns.db.priorities[key] = tank and { build = "auto", levels = {}, values = {}, tank = true } or nil
end

-- your spec's values before your own changes: Forever Upgrades', with your talents (your current spec)
function ns.BaseWeights(key)
  key = key or ns.SpecKey()
  local w = ns.SiteWeights(key)
  if key == ns.SpecKey() and ns.Talents then
    local f = ns.Talents.Factors(key)
    for stat, x in pairs(f) do if w[stat] then w[stat] = w[stat] * x end end
    if f.STA and w.HEALTH then w.HEALTH = w.HEALTH * f.STA end
  end
  return w
end

-- a stat's value at a level, from its Default value (in its own unit), against the spec's top stat
local function AtLevel(base, level, key, top)
  if level == "ignore" then return 0 end
  local norm = ns.NORM[key] or 1
  local imp = base / norm
  if level == "higher" then return (imp + top) / 2 * norm end
  if level == "highest" then return (top * 1.5 + imp / 10) * norm end -- (several at Highest keep their order)
  return base
end

-- the values in use for a spec (its own side: damage / healing, or a tank's survival): your talents,
-- then your changes
function ns.Weights(key)
  key = key or ns.SpecKey()
  local base = ns.BaseWeights(key)
  local top = 0
  for k, v in pairs(base) do if ns.NORM[k] then top = math.max(top, v / ns.NORM[k]) end end
  local w = ns.Copy(base)
  local p = ns.Priorities(key)
  for stat, level in pairs(p.levels) do w[stat] = AtLevel(base[stat] or 0, level, stat, top) end
  for stat, v in pairs(p.values) do w[stat] = v end
  return w
end
function ns.CurrentWeights() return ns.Weights() end
-- stats you've set to Ignore: nothing on either side of your build
function ns.Ignored(stat, key) return ns.Priorities(key).levels[stat] == "ignore" end

-- the label shown with verdicts: the spec, the build, "your changes"
function ns.ScoringLabel()
  local key = ns.SpecKey()
  local b = ns.Build(key)
  local label = ns.SpecName(key) .. ", " .. ns.BuildName(b, key)
  if b == "custom" then
    local t = ns.SurvivalShare(key)
    label = label .. format(" (%d%% survival)", t * 100 + 0.5)
  end
  if ns.HasChanges() then label = label .. " + your changes" end
  if ns.IsTank(key) and not ns.IsTankSpec(key) and b ~= "survival" then label = label .. " (tanking)" end
  return label
end

-- The tooltip on a stat in /eqt: its value and where it comes from
function ns.PriorityInfo(key)
  local lines = {}
  local spec = ns.SpecKey()
  local site = ns.SiteWeights(spec)[key] or 0
  local base = ns.BaseWeights(spec)[key] or 0
  local now = ns.Weights(spec)[key] or 0
  local unit = Unit(key)
  lines[#lines + 1] = format("Value: %s %s (your main stat is 1).", Short(now), unit)
  lines[#lines + 1] = format("Forever Upgrades: %s %s, from its simulator for %s.", Short(site), unit, ns.SpecName(spec))
  if math.abs(base - site) > 1e-6 then
    local _, why = ns.Talents.Factors(spec)
    local parts = {}
    for _, w in ipairs(why) do
      if w[1] == key then parts[#parts + 1] = format("%s %d/%d", w[2], w[3], w[4]) end
    end
    lines[#lines + 1] = format("Your talents: %s (%s). It rises as you take them.", Short(base), table.concat(parts, ", "))
  end
  local level = ns.Level(key)
  if level ~= "goal" then
    lines[#lines + 1] = format("Your value (Forever Upgrades' with your talents: %s).", Short(base))
  end
  if key == "DPS" then lines[#lines + 1] = "Only on weapons (an off-hand's counts half)." end
  if key == "HEALTH" then lines[#lines + 1] = "Items with \"+Health\". 10 Health is about 1 Stamina." end
  if key == "STA" or key == "HEALTH" or key == "ARMOR" then
    lines[#lines + 1] = "Survival in your build counts it through your effective health, on top of this value."
  end
  lines[#lines + 1] = "Type your own value to weigh it more or less (0: worth nothing). Clear the box to put Forever Upgrades' value back."
  return lines
end
