-- Test characters for every class and spec at level 60 (milestone 5), for offline checks only.
-- Primary stats: the spec's median in the logged raid fights (FixtureSpecs.lua, Warcraft Logs).
-- Everything else a character sheet would show is made up here with Classic's conversions and
-- typical level-60 gear (attack power from Strength / Agility, crit from Agility / Intellect, a weapon
-- of 60 DPS, 500 spell damage for casters, 800 healing for healers): the addon itself never uses
-- these, it reads the real sheet. They exist to run every class's code paths and check that the
-- values come out sensible.
FOREVER_SPECS = {
  WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
  HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
  PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
  MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
  DRUID = { "Balance", "Feral Combat", "Restoration" },
}
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local function hasBit(m, b) return math.floor(m / b) % 2 == 1 end

function MakeClassProfile(ns, class, tree)
  local Ev = ns.Evaluator
  local kind = Ev.SpecKind(class, tree)
  local st = FIXTURE_SPECS[class .. ":" .. tree]
  if not st then for k, v in pairs(FIXTURE_SPECS) do if k:find("^" .. class .. ":") then st = v end end end
  st = st or { Strength = 150, Agility = 150, Stamina = 400, Intellect = 300, Spirit = 200, Armor = 3000 }
  local STR, AGI, STA, INT, SPI = st.Strength or 100, st.Agility or 100, st.Stamina or 400, st.Intellect or 100, st.Spirit or 100
  local apS = (class == "ROGUE" or class == "HUNTER") and 1 or 2
  local apA = (class == "ROGUE" or class == "HUNTER") and 1 or 0
  local ap = STR * apS + AGI * apA + (kind == "melee" and 300 or 0)
  local rap = class == "HUNTER" and (AGI * 2 + 300) or 0
  local crit = 5 + AGI / 20
  local twoHand = class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN" or class == "DRUID" or class == "HUNTER"
  local wdps, wspeed = kind == "melee" and 60 or 40, twoHand and 3.6 or 2.6
  local swing = (wdps + ap / 14) * wspeed
  local sp = kind == "caster" and 500 or 0
  local heal = kind == "healer" and 800 or 0
  local v = {
    ["stat.STR.effective"] = STR, ["stat.AGI.effective"] = AGI, ["stat.STA.effective"] = STA, ["stat.INT.effective"] = INT, ["stat.SPI.effective"] = SPI,
    ["ap.base"] = ap, ["crit.melee"] = crit, ["critSpell.spell"] = 5 + INT / 60, ["healing.bonus"] = heal,
    ["health.max"] = STA * 10 + 1500, ["armor.effective"] = st.Armor or 3000, ["defense.base"] = 300,
    ["dodge.chance"] = 5 + AGI / 20, ["melee.min"] = swing * 0.9, ["melee.max"] = swing * 1.1, ["speed.mainHand"] = wspeed,
    ["apFromStat.STR"] = STR * apS, ["apFromStat.AGI"] = AGI * apA, ["critFromStat.AGI"] = AGI / 20 / 100,
    ["spellCritFromStat.INT"] = INT / 60 / 100, ["dodgeFromAgi.chance"] = AGI / 20 / 100, ["hpPerStamina.value"] = 10,
  }
  for _, s in ipairs({ "HOLY", "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE" }) do v["spellDamage." .. s] = sp end
  if class ~= "WARRIOR" and class ~= "ROGUE" then
    -- mana (test-only numbers): the pool from Intellect, regen from Spirit, a little kept while casting + 20 MP5 gear
    v["manaMax.value"] = 1000 + INT * 15
    v["regen.base"], v["manaFromSpirit.value"] = SPI / 5, SPI / 5
    v["regen.casting"] = SPI / 5 * 0.15 + 4
  end
  local slots = {}
  for _, id in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }) do slots[id] = { slot = id, empty = true } end
  slots[16] = { slot = 16, loaded = true, name = "Test Weapon", itemID = 90016, link = "item:90016", classID = 2,
    subclassID = twoHand and 5 or 7, equipLoc = twoHand and "INVTYPE_2HWEAPON" or "INVTYPE_WEAPON",
    stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = wdps }, weapon = { dps = wdps, speed = wspeed }, effects = {}, modeled = {} }
  if class == "HUNTER" then
    local rswing = (50 + rap / 14) * 3.0 + 10
    v["rap.base"], v["ranged.min"], v["ranged.max"], v["speed.ranged"] = rap, rswing * 0.9, rswing * 1.1, 3.0
    v["rapFromStat.AGI"], v["critRanged.ranged"] = AGI * 2, crit
    slots[18] = { slot = 18, loaded = true, name = "Test Bow", itemID = 90018, link = "item:90018", classID = 2, subclassID = 2,
      equipLoc = "INVTYPE_RANGED", stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 50 }, weapon = { dps = 50, speed = 3.0 }, effects = {}, modeled = {} }
  end
  -- spells: the logged rotation's (or all the class's damage / heal spells), highest rank to level 60
  local G = ns.GENERATED.spells
  local want = {}
  local logs = ns.ROTATIONS[class .. ":" .. tree]
  for _, list in ipairs(logs and { logs.damage or {}, logs.healing or {} } or {}) do for _, a in ipairs(list) do want[a.name] = true end end
  local best = {}
  for id, d in pairs(G) do
    if d.classMask and hasBit(d.classMask, CLASS_BIT[class]) and d.level <= 60 and (not logs or want[d.name])
      and (kind == "healer") == (d.kind == "heal") then
      if not best[d.name] or d.level > G[best[d.name]].level then best[d.name] = id end
    end
  end
  local known, casts = {}, {}
  for name, id in pairs(best) do known[id] = name; casts[name] = { spellID = id } end
  -- the logged spec's physical abilities are in its spellbook too (ids only for this test)
  local fake = 900000
  for name in pairs(want) do
    local ph = ns.GENERATED.physical[name]
    if ph and ph.classes[class] then fake = fake + 1; known[fake] = name .. " (Rank 1)" end
  end
  return {
    identity = { class = class, level = 60, name = "Test" },
    stats = { values = v, weaponSkills = { [16] = { rank = 300, modifier = 0 } }, skillByLine = {} },
    equipment = { slots = slots, pending = {} },
    talents = { primaryTree = tree, nodes = {}, trees = {}, totalPoints = 51 },
    buffs = { helpful = {} }, spells = { known = known, count = 0 },
    abilities = { spells = {}, imbues = {}, casts = casts },
    calc = { ratingPct = { CR_CRIT_MELEE = 1 / 14, CR_CRIT_RANGED = 1 / 14, CR_CRIT_SPELL = 1 / 14, CR_HIT_MELEE = 0.1,
      CR_HIT_RANGED = 0.1, CR_HIT_SPELL = 0.1, CR_HASTE_MELEE = 0.1, CR_HASTE_RANGED = 0.1, CR_HASTE_SPELL = 0.1,
      CR_DODGE = 1 / 12, CR_PARRY = 1 / 15, CR_BLOCK = 0.2, CR_DEFENSE_SKILL = 1, CR_EXPERTISE = 0.1 } },
    bags = {}, meta = {}, issues = {},
  }
end
