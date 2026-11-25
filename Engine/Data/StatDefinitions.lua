-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- StatDefinitions: item stat keys (as C_Item.GetItemStats gives them) -> the engine's stat names, and
-- which combat rating each rating stat feeds. Pure data. The key list follows what Forever items use
-- (checked against the released Equip This! and the in-game dump: ITEM_MOD_CRIT_RATING_SHORT,
-- ITEM_MOD_PHYSICAL_DAMAGE_DONE_SHORT...).
local _, ns = ...; ns = ns.Engine
local SD = ns and ns.Module and ns.Module("StatDefs") or {}

SD.ITEM_KEYS = {
  ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
  ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI",
  RESISTANCE0_NAME = "ARMOR",
  RESISTANCE1_NAME = "RES_HOLY", RESISTANCE2_NAME = "RES_FIRE", RESISTANCE3_NAME = "RES_NATURE",
  RESISTANCE4_NAME = "RES_FROST", RESISTANCE5_NAME = "RES_SHADOW", RESISTANCE6_NAME = "RES_ARCANE",
  ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
  ITEM_MOD_SPELL_POWER_SHORT = "SPELLPOWER",         -- damage and healing
  ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
  ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
  ITEM_MOD_HEALTH_REGEN_SHORT = "HP5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
  ITEM_MOD_HEALTH_SHORT = "HEALTH", ITEM_MOD_HEALTH = "HEALTH",
  ITEM_MOD_CRIT_RATING_SHORT = "CRIT_RATING", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT_MELEE_RATING",
  ITEM_MOD_CRIT_SPELL_RATING_SHORT = "CRIT_SPELL_RATING", ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CRIT_RANGED_RATING",
  ITEM_MOD_HIT_RATING_SHORT = "HIT_RATING", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT_MELEE_RATING",
  ITEM_MOD_HIT_SPELL_RATING_SHORT = "HIT_SPELL_RATING", ITEM_MOD_HIT_RANGED_RATING_SHORT = "HIT_RANGED_RATING",
  ITEM_MOD_HASTE_RATING_SHORT = "HASTE_RATING", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE_MELEE_RATING",
  ITEM_MOD_HASTE_SPELL_RATING_SHORT = "HASTE_SPELL_RATING",
  ITEM_MOD_EXPERTISE_RATING_SHORT = "EXPERTISE_RATING",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEFENSE_RATING", ITEM_MOD_DODGE_RATING_SHORT = "DODGE_RATING",
  ITEM_MOD_PARRY_RATING_SHORT = "PARRY_RATING", ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK_RATING",
  ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCK_VALUE",
  ITEM_MOD_SPELL_PENETRATION_SHORT = "SPELL_PEN",
  ITEM_MOD_PHYSICAL_DAMAGE_DONE_SHORT = "WEAPON_DMG",  -- "+N weapon damage": added to each weapon hit
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "WEAPON_DPS",
}

-- rating stat -> the combat ratings (CR_ constant names) it raises. A plain "crit rating" counts for
-- melee, ranged and spells on Forever (the dump: 7 crit rating gave CR_CRIT_MELEE, _RANGED and _SPELL 7).
SD.RATINGS = {
  CRIT_RATING = { "CR_CRIT_MELEE", "CR_CRIT_RANGED", "CR_CRIT_SPELL" },
  CRIT_MELEE_RATING = { "CR_CRIT_MELEE" }, CRIT_SPELL_RATING = { "CR_CRIT_SPELL" }, CRIT_RANGED_RATING = { "CR_CRIT_RANGED" },
  -- (assumed like crit until a hit-rating item is seen in game: see DEVELOPMENT.md)
  HIT_RATING = { "CR_HIT_MELEE", "CR_HIT_RANGED", "CR_HIT_SPELL" },
  HIT_MELEE_RATING = { "CR_HIT_MELEE" }, HIT_SPELL_RATING = { "CR_HIT_SPELL" }, HIT_RANGED_RATING = { "CR_HIT_RANGED" },
  HASTE_RATING = { "CR_HASTE_MELEE", "CR_HASTE_RANGED", "CR_HASTE_SPELL" },
  HASTE_MELEE_RATING = { "CR_HASTE_MELEE" }, HASTE_SPELL_RATING = { "CR_HASTE_SPELL" },
  EXPERTISE_RATING = { "CR_EXPERTISE" }, DEFENSE_RATING = { "CR_DEFENSE_SKILL" },
  DODGE_RATING = { "CR_DODGE" }, PARRY_RATING = { "CR_PARRY" }, BLOCK_RATING = { "CR_BLOCK" },
}

-- Item stats (as the game gives them) -> engine stats { STR = 12, CRIT_RATING = 7, ... }, and the
-- keys it didn't recognise (so they're reported, not silently dropped).
function SD.Normalize(itemStats)
  local out, unknown = {}, {}
  for k, v in pairs(itemStats or {}) do
    local s = SD.ITEM_KEYS[k]
    if s then out[s] = (out[s] or 0) + v
    elseif k:find("^EMPTY_SOCKET") then -- sockets aren't stats
    else unknown[#unknown + 1] = k end
  end
  if out.SPELLPOWER then
    out.SP = (out.SP or 0) + out.SPELLPOWER
    out.HEAL = (out.HEAL or 0) + out.SPELLPOWER
    out.SPELLPOWER = nil
  end
  return out, unknown
end

-- a + sign * b, for stat tables
function SD.Add(a, b, sign)
  local out = {}
  for k, v in pairs(a or {}) do out[k] = v end
  for k, v in pairs(b or {}) do out[k] = (out[k] or 0) + (sign or 1) * v end
  return out
end

SD.NAMES = {
  STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit", ARMOR = "Armor",
  AP = "Attack Power", RAP = "Ranged AP", SP = "Spell Damage", HEAL = "Healing", MP5 = "Mana per 5",
  SP_HOLY = "Holy Spell Damage", SP_FIRE = "Fire Spell Damage", SP_NATURE = "Nature Spell Damage", SP_FROST = "Frost Spell Damage",
  SP_SHADOW = "Shadow Spell Damage", SP_ARCANE = "Arcane Spell Damage",
  HP5 = "Health per 5", HEALTH = "Health", CRIT_RATING = "Crit Rating", HIT_RATING = "Hit Rating",
  HASTE_RATING = "Haste Rating", EXPERTISE_RATING = "Expertise Rating", DEFENSE_RATING = "Defense Rating",
  DODGE_RATING = "Dodge Rating", PARRY_RATING = "Parry Rating", BLOCK_RATING = "Block Rating",
  BLOCK_VALUE = "Block Value", SPELL_PEN = "Spell Penetration", WEAPON_DMG = "Weapon Damage",
  WEAPON_DPS = "Weapon DPS", RES_HOLY = "Holy Res.", RES_FIRE = "Fire Res.", RES_NATURE = "Nature Res.",
  RES_FROST = "Frost Res.", RES_SHADOW = "Shadow Res.", RES_ARCANE = "Arcane Res.",
}

-- weapon subclass (Enum.ItemWeaponSubclass in Forever's docs: Axe1H 0, Axe2H 1, Bows 2, Guns 3, Mace1H 4,
-- Mace2H 5, Polearm 6, Sword1H 7, Sword2H 8, Staff 10, Unarmed 13, Dagger 15, Thrown 16, Crossbow 18,
-- Wand 19) -> weapon skill line (Blizzard's Camelot paper doll map)
SD.WEAPON_SKILL = { [7] = 43, [0] = 44, [2] = 45, [3] = 46, [4] = 54, [8] = 55, [10] = 136, [5] = 160, [1] = 172,
  [15] = 173, [16] = 176, [18] = 226, [19] = 228, [6] = 229, [13] = 162 }
SD.TWO_HAND = { [1] = true, [5] = true, [6] = true, [8] = true, [10] = true }
SD.SHIELD = { class = 4, subclass = 6 }   -- (Enum.ItemArmorSubclass.Shield = 6)
