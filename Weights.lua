-- Stat values. Each spec's come from Forever Upgrades' weights (Guides.lua); the presets below are
-- the fallback. You set priorities on top (Normal / Higher / Highest / Ignore, or a goal: see
-- "Priorities" below). Values are written as points per unit (the main stat is 1; crit and hit
-- per 1%; DPS is weapon damage per second, only on weapons), then shown and edited as importance
-- 0-5 (see ns.NORM). Starting points to tune in /eqt, not gospel.
local _, ns = ...

-- stat keys: what the tooltip line and /eqt item show
ns.STAT_NAMES = {
  STR = "Strength", AGI = "Agility", STA = "Stamina", HEALTH = "Health", INT = "Intellect", SPI = "Spirit",
  ARMOR = "Armor", AP = "Attack Power", RAP = "Ranged Attack Power",
  SP = "Spell Damage", HEAL = "Healing", MP5 = "Mana per 5 sec",
  CRIT = "Crit %", HIT = "Hit %", HASTE = "Haste %", EXPERTISE = "Expertise %", SPELLPEN = "Spell Penetration",
  HP5 = "Health per 5 sec", SPELLCRIT = "Spell Crit %", SPELLHIT = "Spell Hit %",
  DPS = "Weapon DPS", DEF = "Defense", DODGE = "Dodge %", PARRY = "Parry %", BLOCK = "Block %", BLOCKVALUE = "Block Value",
}
ns.STAT_ORDER = { "STR", "AGI", "STA", "HEALTH", "INT", "SPI", "AP", "RAP", "SP", "HEAL", "MP5", "HP5", "CRIT", "HIT", "HASTE", "EXPERTISE",
  "SPELLCRIT", "SPELLHIT", "SPELLPEN", "DPS", "ARMOR", "DEF", "DODGE", "PARRY", "BLOCK", "BLOCKVALUE" }

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
ns.NORM = { STR = 1, AGI = 1, STA = 1, HEALTH = 0.1, INT = 1, SPI = 1, AP = 0.5, RAP = 0.4, SP = 1, HEAL = 0.6, MP5 = 2,
  CRIT = 14, HIT = 12, HASTE = 10, EXPERTISE = 12, SPELLPEN = 1, HP5 = 2, SPELLCRIT = 10, SPELLHIT = 10, DPS = 4, ARMOR = 0.02, DEF = 1.2, DODGE = 12,
  PARRY = 12, BLOCK = 6, BLOCKVALUE = 0.5 }
local function round2(x) return math.floor(x * 100 + 0.5) / 100 end
local PRIMARY = { "STR", "AGI", "INT" }
local function Short(x) x = math.floor(x * 10 + 0.5) / 10; return (x == math.floor(x)) and tostring(x) or format("%.1f", x) end
-- a weight as typed: 3.75 -> "3.75", 4.5 -> "4.5", 5 -> "5"
local function Wt(x) return (format("%.2f", x or 0):gsub("0+$", ""):gsub("%.$", "")) end
local function Unit(key)
  if key == "DPS" then return "+1 weapon DPS" end
  if (ns.STAT_NAMES[key] or ""):find("%%") then return "+1%" end
  return "+1"
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

-- What gear is scored with: your spec's values, with your priorities
function ns.CurrentWeights() return ns.Weights() end
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

-- a spec's preset, as importance (0-5), and the factor it was scaled by
function ns.PresetImportance(key)
  local class, tree = key:match("^(%u+):(%d)$")
  local p = class and ns.PRESETS[class] and ns.PRESETS[class][tonumber(tree)]
  -- Forever Upgrades' stat weights for the spec (Guides.lua), else the built-in ones
  local g = ns.GUIDE and ns.GUIDE[key] and ns.GUIDE[key].weights
  return ns.ToImportance((g and next(g)) and g or (p and p[2]) or MELEE)
end

---------------------------------------------------------------------------
-- Priorities: what you want more of, in two layers.
--  1. A goal sets the base. Auto (the default): Leveling below the level cap, Damage at it.
--     Leveling raises what keeps you alive and drinking less: Stamina and Health x3, Armor,
--     Intellect, Spirit and mana per 5 x2 (Pawn Forever's leveling multipliers, from GearQuest).
--     Damage: Forever Upgrades' values as they are. Survival / Mana / Balanced lift a few stats.
--  2. Your own changes, stat by stat, on top: Ignore / Normal (Forever Upgrades' value) / Higher
--     (halfway to your spec's most valued stat) / Highest (above every Normal stat). Default
--     leaves the stat to the goal. Your changes stay when the goal changes (Auto at the cap too).
---------------------------------------------------------------------------
ns.LEVELS = { { "goal", "Default" }, { "ignore", "Ignore" }, { "normal", "Normal" }, { "higher", "Higher" }, { "highest", "Highest" } }
local LEVEL_NAME = {}
for _, l in ipairs(ns.LEVELS) do LEVEL_NAME[l[1]] = l[2] end
ns.LEVEL_NAME = LEVEL_NAME
local TOP = 5         -- a spec's most valued stat (its values are scaled so it's 5)
local HIGHEST = 7.5   -- above any Normal or Higher stat

ns.GOALS = {
  { "auto", "Auto", "Leveling until the level cap, then Damage. Switches by itself." },
  { "leveling", "Leveling", "Forever Upgrades' values, with Stamina and Health x3 and Armor, Intellect, Spirit and mana per 5 x2: easier fights, less drinking." },
  { "damage", "Damage", "Forever Upgrades' values for your spec, as they are." },
  { "survival", "Survival", "More health and armor to take more hits: Stamina and Health first, then Armor, health regeneration and avoidance." },
  { "mana", "Mana", "Longer before you drink: Intellect first, then Spirit and mana per 5 sec." },
  { "balanced", "Balanced", "A bit of everything: more Stamina, Health and Armor, and Intellect and mana per 5 sec if you use mana." },
}
local GOAL_NAME = {}
for _, g in ipairs(ns.GOALS) do GOAL_NAME[g[1]] = g[2] end
-- Leveling: these stats' values multiplied
local LEVELING = { STA = 3, HEALTH = 3, ARMOR = 2, INT = 2, SPI = 2, MP5 = 2 }
ns.LEVELING = LEVELING
-- the other goals: priority levels
local GOAL_LEVELS = {
  survival = { STA = "highest", HEALTH = "highest", ARMOR = "higher", HP5 = "higher", DEF = "higher", DODGE = "higher", PARRY = "higher", BLOCK = "higher" },
  mana = { INT = "highest", SPI = "higher", MP5 = "higher" },
  balanced = { STA = "higher", HEALTH = "higher", ARMOR = "higher", HP5 = "higher", INT = "higher", MP5 = "higher" },
}
local MANA_STATS = { INT = true, SPI = true, MP5 = true }
local NO_MANA = { WARRIOR = true, ROGUE = true }
-- the goals that make sense for your class (no Mana goal for warriors and rogues)
function ns.Goals()
  local list = {}
  for _, g in ipairs(ns.GOALS) do
    if not (g[1] == "mana" and NO_MANA[ns.Class()]) then list[#list + 1] = g end
  end
  return list
end

-- the level cap (Auto switches from Leveling to Damage there)
function ns.MaxLevel()
  local cap = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or (GetMaxPlayerLevel and GetMaxPlayerLevel())
  return (type(cap) == "number" and cap > 0) and cap or 60
end

-- your priorities for a spec: { goal = "auto" | "leveling" | ..., levels = { STAT = level } } (your changes)
function ns.Priorities(key)
  key = key or ns.SpecKey()
  ns.db.priorities = ns.db.priorities or {}
  local p = ns.db.priorities[key]
  if p and p.goal == "custom" then p.goal = "damage" end -- (2.5.0's "your own mix": your changes over Damage)
  return p or { goal = "auto", levels = {} }
end
-- the goal in effect: Auto as Leveling or Damage
function ns.Goal(key)
  local g = ns.Priorities(key).goal or "auto"
  if g == "auto" then
    local level = UnitLevel and UnitLevel("player") or 1
    return (level < ns.MaxLevel()) and "leveling" or "damage", true
  end
  return g, false
end
local function Save(key, p) ns.db.priorities = ns.db.priorities or {}; ns.db.priorities[key] = p end
function ns.SetGoal(goal, key)
  key = key or ns.SpecKey()
  local p = ns.Copy(ns.Priorities(key))
  p.goal = goal
  Save(key, p)
end
function ns.Level(stat, key) return ns.Priorities(key).levels[stat] or "goal" end
function ns.SetLevel(stat, level, key)
  key = key or ns.SpecKey()
  local p = ns.Copy(ns.Priorities(key))
  p.levels[stat] = (level ~= "goal") and level or nil
  Save(key, p)
end
function ns.HasChanges(key) return next(ns.Priorities(key).levels) ~= nil end
function ns.ResetPriorities(key) if ns.db.priorities then ns.db.priorities[key or ns.SpecKey()] = nil end end

-- a stat's value (importance) at a priority level, from its Normal value
local function AtLevel(base, level)
  if level == "ignore" then return 0 end
  if level == "higher" then return (base + TOP) / 2 end
  if level == "highest" then return HIGHEST + base / 10 end -- (several at Highest keep the site's order)
  return base
end

-- the values in use for a spec: Forever Upgrades' (Normal), the goal, then your changes
function ns.Weights(key)
  key = key or ns.SpecKey()
  local site = ns.PresetImportance(key)
  site.HEALTH = site.HEALTH or site.STA -- (10 Health = 1 Stamina: the same importance)
  local w = ns.Copy(site)
  local goal = ns.Goal(key)
  if goal == "leveling" then
    -- (Armor: most damage specs' values leave it out; from Pawn's Forever scales, 1 Armor is worth
    -- about 0.005 of your main stat, before the x2)
    if (w.ARMOR or 0) <= 0 then
      local main = 0
      for _, k in ipairs(PRIMARY) do main = math.max(main, ns.PointsPer(k, w[k])) end
      if main > 0 and ns.NORM.ARMOR > 0 then w.ARMOR = 0.005 * main * 5 / ns.NORM.ARMOR end
    end
    for stat, m in pairs(LEVELING) do if w[stat] then w[stat] = w[stat] * m end end
  else
    for stat, level in pairs(GOAL_LEVELS[goal] or {}) do
      if not (MANA_STATS[stat] and NO_MANA[ns.Class()]) then w[stat] = AtLevel(site[stat] or 0, level) end
    end
  end
  for stat, level in pairs(ns.Priorities(key).levels) do w[stat] = AtLevel(site[stat] or 0, level) end
  return w
end

-- the label shown with verdicts: the spec, the goal (if not plain Damage) and "your changes"
function ns.ScoringLabel()
  local goal = ns.Goal()
  local label = ns.SpecName(ns.SpecKey())
  if goal ~= "damage" then label = label .. ", " .. (GOAL_NAME[goal] or goal) end
  if ns.HasChanges() then label = label .. (goal ~= "damage" and " + your changes" or ", your changes") end
  return label
end

-- The tooltip on a stat in /eqt, in short parts: what it's worth, what the levels do,
-- and how items are scored.
function ns.PriorityInfo(key)
  local lines = {}
  local name = (ns.STAT_NAMES[key] or key):gsub(" %%$", "")
  local unit = Unit(key)
  local label = (unit == "+1%" or unit == "+1") and (unit .. " " .. name) or unit
  local spec = ns.SpecKey()
  local weights = ns.Weights(spec)
  local pts = ns.PointsPer(key, weights[key])
  local Sim = ns.Sim
  if Sim and Sim.Active() and Sim.MODEL[key] then
    -- worked out from your spells and numbers (Sim.lua)
    local ok, per = pcall(Sim.PerUnit, key)
    if ok and per then
      local n = (unit == "+1%" or key == "DPS") and 1 or 10
      local label10 = (n == 10) and ("+10 " .. name) or label
      lines[#lines + 1] = format("Worth: %s = %+.2f%% %s for you now (from your spells and numbers).", label10, per * n, Sim.Unit())
    end
    if ns.Level(key) ~= "goal" or (weights[key] or 0) ~= (ns.PresetImportance(spec)[key] or 0) then
      lines[#lines + 1] = "Your priority scales that up or down."
    end
  elseif pts <= 0 then
    lines[#lines + 1] = "Items get nothing for it."
  else
    local best, bestPts
    for _, k in ipairs(PRIMARY) do
      local p = ns.PointsPer(k, weights[k])
      if p > 0 and (not bestPts or p > bestPts) then best, bestPts = k, p end
    end
    if best and best ~= key then
      lines[#lines + 1] = format("Worth: %s counts as much as +%s %s.", label, Short(pts / bestPts), ns.STAT_NAMES[best])
    else
      lines[#lines + 1] = format("Worth: your main stat; other stats are measured against %s.", label)
    end
  end
  if key == "DPS" then lines[#lines + 1] = "Only on weapons. Damage procs and extra attacks count through it too." end
  if key == "HEALTH" then lines[#lines + 1] = "Items with \"+Health\". 10 Health is about 1 Stamina." end
  local goal, auto = ns.Goal(spec)
  local gname = (GOAL_NAME[goal] or goal) .. (auto and " (Auto)" or "")
  if ns.Level(key) ~= "goal" then
    lines[#lines + 1] = format("Your change: %s. Default puts it back to your goal, %s.", LEVEL_NAME[ns.Level(key)], gname)
  elseif goal == "leveling" and LEVELING[key] then
    lines[#lines + 1] = format("Default: your goal, %s, counts it x%d while you level.", gname, LEVELING[key])
  else
    lines[#lines + 1] = format("Default: as your goal, %s, has it.", gname)
  end
  lines[#lines + 1] = "Normal: Forever Upgrades' value. Higher: halfway to your spec's most valued stat. Highest: worth more than every Normal stat, so items with more of it win. Ignore: worth nothing."
  lines[#lines + 1] = (Sim and Sim.Active())
    and format("An item's value: the change in your %s from wearing it, plus its other stats (Stamina, Intellect...) by these values, plus its effects.", Sim.Unit())
    or "An item's score adds up its stats by these values, plus its effects. \"Upgrade +2%\": your whole gear scores 2% higher with it."
  return lines
end
