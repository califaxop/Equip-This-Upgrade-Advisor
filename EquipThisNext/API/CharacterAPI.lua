-- CharacterAPI: who the character is and what the character sheet says. The stat reads are a
-- table (READS) so the scanner, the diagnostics and the tests share one list. Every read here is
-- documented by Blizzard as hidden from addons while unit stats are restricted (in combat and
-- some instances); the scanner checks that first and keeps the last readable values.
local _, ns = ...
local Char = ns.Module("CharacterAPI")
local Compat = ns.Compat

Char.STATS = { "STR", "AGI", "STA", "INT", "SPI" }              -- UnitStat index 1-5
Char.SCHOOLS = { "HOLY", "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE" } -- spell school 2-7, resistance 1-6

-- { key, api, args, { name of each return } }. A return named false is skipped.
Char.READS = {
  { "armor", "UnitArmor", { "player" }, { "base", "effective", "real", "bonus" } },
  { "ap", "UnitAttackPower", { "player" }, { "base", "pos", "neg" } },
  { "rap", "UnitRangedAttackPower", { "player" }, { "base", "pos", "neg" } },
  { "melee", "UnitDamage", { "player" }, { "min", "max", "ohMin", "ohMax", "pos", "neg", "pct" } },
  { "ranged", "UnitRangedDamage", { "player" }, { "speed", "min", "max", "pos", "neg", "pct" } },
  { "speed", "UnitAttackSpeed", { "player" }, { "mainHand", "offHand", "ranged" } },
  { "health", "UnitHealthMax", { "player" }, { "max" } },
  { "power", "UnitPowerType", { "player" }, { "type", "token" } },
  { "defense", "UnitDefenseSkill", { "player" }, { "base", "modifier" } },
  { "crit", "GetCritChance", {}, { "melee" } },
  { "critRanged", "GetRangedCritChance", {}, { "ranged" } },
  { "critSpell", "GetSpellCritChance", {}, { "spell" } },
  { "hit", "GetHitModifier", {}, { "melee" } },
  { "hitRanged", "GetRangedHitModifier", {}, { "ranged" } },
  { "hitOffhand", "GetOffhandHitModifier", {}, { "offHand" } },
  { "hitSpell", "GetSpellHitModifier", {}, { "spell" } },
  { "expertise", "GetExpertise", {}, { "mainHand", "offHand", "ranged" } },
  { "haste", "GetHaste", {}, { "all" } },
  { "hasteMelee", "GetMeleeHaste", {}, { "melee" } },
  { "hasteRanged", "GetRangedHaste", {}, { "ranged" } },
  { "hasteSpell", "UnitSpellHaste", { "player" }, { "spell" } },
  { "healing", "GetSpellBonusHealing", {}, { "bonus" } },
  { "regen", "GetManaRegen", {}, { "base", "casting" } },
  { "spellPen", "GetSpellPenetration", {}, { "value" } },
  { "armorPen", "GetArmorPenetration", {}, { "value" } },
  { "dodge", "GetDodgeChance", {}, { "chance" } },
  { "parry", "GetParryChance", {}, { "chance" } },
  { "block", "GetBlockChance", {}, { "chance" } },
  { "blockValue", "GetShieldBlock", {}, { "value" } },
  { "hpPerStamina", "UnitHPPerStamina", { "player" }, { "value" } },
  { "dodgeFromAgi", "GetDodgeChanceFromAttribute", {}, { "chance" } },
  { "manaFromSpirit", "GetManaRegenFromSpirit", {}, { "value" } },
  { "healthFromSpirit", "GetHealthRegenFromSpirit", {}, { "value" } },
}
-- per primary stat (index 1-5): the stat itself and what the game says it converts to
Char.STAT_READS = {
  { "stat", "UnitStat", function(i) return "player", i end, { "base", "effective", "pos", "neg" } },
}
Char.STAT_CONVERSIONS = {
  { "critFromStat", "GetCritChanceFromStat" },
  { "spellCritFromStat", "GetSpellCritChanceFromStat" },
  { "apFromStat", "GetAttackPowerForStat" },
  { "rapFromStat", "GetRangedAttackPowerForStat" },
}
-- combat ratings, by the game's own CR_ constant names (read from _G, not hardcoded numbers)
Char.RATINGS = { "CR_WEAPON_SKILL", "CR_DEFENSE_SKILL", "CR_DODGE", "CR_PARRY", "CR_BLOCK", "CR_HIT_MELEE",
  "CR_HIT_RANGED", "CR_HIT_SPELL", "CR_CRIT_MELEE", "CR_CRIT_RANGED", "CR_CRIT_SPELL", "CR_HASTE_MELEE",
  "CR_HASTE_RANGED", "CR_HASTE_SPELL", "CR_EXPERTISE", "CR_ARMOR_PENETRATION" }

function Char.RatingIndex(name)
  local v = _G[name]
  return type(v) == "number" and v or nil
end

function Char.Identity()
  local _, className, classFile, classID = Compat.Call("UnitClass", "player")
  local _, raceName, raceFile, raceID = Compat.Call("UnitRace", "player")
  local version, build, _, interface = select(2, Compat.Call("GetBuildInfo"))
  return {
    name = Compat.Value("UnitName", "player"),
    realm = Compat.Value("GetRealmName"),
    guid = Compat.Value("UnitGUID", "player"),
    class = Compat.Plain(classFile), className = Compat.Plain(className), classID = Compat.Plain(classID),
    race = Compat.Plain(raceFile), raceName = Compat.Plain(raceName), raceID = Compat.Plain(raceID),
    level = Compat.Value("UnitLevel", "player"),
    effectiveLevel = Compat.Value("UnitEffectiveLevel", "player"),
    sex = Compat.Value("UnitSex", "player"),
    locale = Compat.Value("GetLocale"),
    client = { version = Compat.Plain(version), build = Compat.Plain(build), interface = Compat.Plain(interface) },
    specIndex = Compat.Value("C_SpecializationInfo.GetSpecialization"),
  }
end

-- true when the game hides stats from addons right now (then the scanner keeps the last readable set)
function Char.StatsRestricted()
  local v, why = Compat.Value("C_Secrets.ShouldUnitStatsBeSecret")
  if why == "missing" then return false end
  return v == true
end

-- A weapon's skill line: { name, rank, modifier, maxRank } from the skill ID Blizzard's paper doll maps
-- the weapon type to (see Scanner/StatScanner for the map).
function Char.SkillLine(skillLineID)
  local ok, info = Compat.Call("C_SkillInfo.GetSkillLineInfoByID", skillLineID)
  if not ok or type(info) ~= "table" then return nil end
  return { name = Compat.Field(info, "name"), rank = Compat.Field(info, "rank"),
    modifier = Compat.Field(info, "modifier"), maxRank = Compat.Field(info, "maxRank") }
end
