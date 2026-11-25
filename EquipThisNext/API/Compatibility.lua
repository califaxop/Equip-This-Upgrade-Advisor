-- Compatibility: the only place that calls into the game's API.
--
--  * Compat.Call("C_Item.GetItemInfo", ...) looks the function up by name, calls it inside pcall and
--    returns ok, results... Missing functions and errors never throw.
--  * Secret values (Forever hides some values from addons, e.g. in combat) are replaced by the
--    marker Compat.SECRET before anything else sees them, so no other code ever holds a secret.
--  * Every API this addon uses is listed in Compat.KNOWN with where it was verified to exist for
--    Forever build 1.60.1.71091, and Compat.status records what happened when it was called
--    (/eqn api shows both).
--
-- Verification sources:
--   docs  Blizzard_APIDocumentationGenerated in Blizzard's Forever UI source (build 71091)
--   ui    called by Blizzard's own Forever UI code (Camelot paper doll, containers...)
--   eqt   used by the released Equip This! in Forever and working for players
local _, ns = ...
local Compat = ns.Module("Compat")

Compat.SECRET = setmetatable({}, { __tostring = function() return "<hidden>" end })
Compat.status = {}   -- path -> { ok = n, missing = n, error = n, secret = n, last = text }

Compat.KNOWN = {
  -- identity
  ["UnitClass"] = "docs", ["UnitRace"] = "docs", ["UnitLevel"] = "docs", ["UnitName"] = "docs",
  ["UnitSex"] = "docs", ["UnitGUID"] = "docs", ["GetRealmName"] = "docs", ["GetBuildInfo"] = "docs",
  ["GetLocale"] = "docs", ["UnitAffectingCombat"] = "docs", ["InCombatLockdown"] = "ui",
  -- secrecy
  ["C_Secrets.ShouldUnitStatsBeSecret"] = "docs", ["C_Secrets.ShouldAurasBeSecret"] = "docs",
  ["C_Secrets.ShouldUnitPowerMaxBeSecret"] = "docs", ["C_Secrets.ShouldUnitHealthMaxBeSecret"] = "docs",
  -- character stats (all "SecretWhenUnitStatsRestricted" in the docs)
  ["UnitStat"] = "docs", ["UnitArmor"] = "docs", ["UnitAttackPower"] = "docs", ["UnitRangedAttackPower"] = "docs",
  ["UnitDamage"] = "docs", ["UnitRangedDamage"] = "docs", ["UnitAttackSpeed"] = "docs", ["UnitHealthMax"] = "docs",
  ["UnitPowerType"] = "docs", ["UnitPowerMax"] = "docs", ["UnitResistance"] = "docs", ["UnitDefenseSkill"] = "docs",
  ["UnitSpellHaste"] = "docs", ["UnitHPPerStamina"] = "docs", ["UnitEffectiveLevel"] = "docs",
  ["GetCritChance"] = "docs", ["GetRangedCritChance"] = "docs", ["GetSpellCritChance"] = "docs",
  ["GetHitModifier"] = "docs", ["GetSpellHitModifier"] = "docs", ["GetRangedHitModifier"] = "docs",
  ["GetOffhandHitModifier"] = "docs", ["GetCombatRating"] = "docs", ["GetCombatRatingBonus"] = "docs",
  ["GetExpertise"] = "docs", ["GetHaste"] = "docs", ["GetMeleeHaste"] = "docs", ["GetRangedHaste"] = "docs",
  ["GetSpellBonusDamage"] = "docs", ["GetSpellBonusHealing"] = "docs", ["GetManaRegen"] = "docs",
  ["GetSpellPenetration"] = "docs", ["GetArmorPenetration"] = "docs", ["GetDodgeChance"] = "docs",
  ["GetParryChance"] = "docs", ["GetBlockChance"] = "docs", ["GetShieldBlock"] = "docs",
  ["CanDualWield"] = "docs",
  -- calculators (milestone 2): the game's own numbers for any value
  ["GetCombatRatingBonusForCombatRatingValue"] = "docs", ["C_PaperDollInfo.GetArmorEffectiveness"] = "docs",
  ["GetGlancingBlowChance"] = "docs", ["GetGlancingBlowPenalty"] = "docs",
  ["C_Spell.GetSpellDescription"] = "docs", ["C_TooltipInfo.GetHyperlink"] = "docs",
  -- milestone 3: bags, uniqueness
  ["C_Container.GetContainerNumSlots"] = "docs", ["C_Container.GetContainerItemLink"] = "docs",
  ["C_Item.GetItemUniquenessByID"] = "docs",
  -- (GetGlancingBlowChance([playerWeaponSkill], targetDefenseSkill) is a calculator for the
  --  performance model, milestone 4: not a character sheet value, so not scanned)
  -- the game's own stat conversions (the paper doll uses them)
  ["GetCritChanceFromStat"] = "docs", ["GetSpellCritChanceFromStat"] = "docs", ["GetAttackPowerForStat"] = "docs",
  ["GetRangedAttackPowerForStat"] = "docs", ["GetDodgeChanceFromAttribute"] = "docs",
  ["GetManaRegenFromSpirit"] = "docs", ["GetHealthRegenFromSpirit"] = "docs",
  ["C_SkillInfo.GetSkillLineInfoByID"] = "docs", ["C_SpecializationInfo.GetSpecialization"] = "docs",
  -- equipment and items
  ["GetInventoryItemLink"] = "ui", ["GetInventoryItemID"] = "ui", ["GetInventorySlotInfo"] = "ui",
  ["C_Item.GetItemInfo"] = "docs", ["C_Item.GetItemInfoInstant"] = "docs", ["C_Item.GetItemStats"] = "docs",
  ["C_Item.IsItemDataCachedByID"] = "docs", ["C_Item.RequestLoadItemDataByID"] = "docs",
  ["C_Item.GetItemSetInfo"] = "docs", ["C_Item.GetItemNumSockets"] = "docs", ["C_Item.GetItemGem"] = "docs",
  ["C_Item.GetWeaponEnchantInfo"] = "docs", ["C_Item.GetDetailedItemLevelInfo"] = "docs",
  ["C_Item.GetItemSpell"] = "docs", ["C_PlayerInfo.CanUseItem"] = "docs",
  -- talents (Forever: Retail's trait system holding the three Classic trees)
  ["C_ClassTalents.GetActiveConfigID"] = "docs", ["C_Traits.GetConfigInfo"] = "docs",
  ["C_Traits.GetTreeNodes"] = "docs", ["C_Traits.GetNodeInfo"] = "docs", ["C_Traits.GetEntryInfo"] = "docs",
  ["C_Traits.GetDefinitionInfo"] = "docs", ["C_Traits.GetGroupDisplayInfoByTreeID"] = "eqt",
  ["C_Traits.GetGroupCurrencyInfo"] = "eqt",
  -- spells and auras
  ["C_Spell.GetSpellName"] = "docs", ["C_Spell.GetSpellInfo"] = "docs", ["C_SpellBook.IsSpellKnown"] = "docs",
  ["C_SpellBook.GetNumSpellBookSkillLines"] = "docs", ["C_SpellBook.GetSpellBookSkillLineInfo"] = "docs",
  ["C_SpellBook.GetSpellBookItemInfo"] = "docs", ["C_UnitAuras.GetAuraDataByIndex"] = "docs",
}

local function resolve(path)
  local t = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end

local issecret = issecretvalue
local issecrettable = issecrettable
function Compat.IsSecret(v)
  if v == Compat.SECRET then return true end
  if issecret and issecret(v) then return true end
  if issecrettable and type(v) == "table" and issecrettable(v) then return true end
  return false
end

-- the value, or nil when it's hidden (the marker) or not a plain value
function Compat.Plain(v)
  if v == Compat.SECRET then return nil end
  return v
end

local function note(path, kind, text)
  local s = Compat.status[path]
  if not s then s = { ok = 0, missing = 0, error = 0, secret = 0 }; Compat.status[path] = s end
  s[kind] = s[kind] + 1
  if text then s.last = text end
end

function Compat.Has(path)
  return type(resolve(path)) == "function"
end

-- ok, results...   (ok = false: missing function or an error; the second value says which)
function Compat.Call(path, ...)
  local fn = resolve(path)
  if type(fn) ~= "function" then
    note(path, "missing", "not in this client")
    return false, "missing"
  end
  local r = ns.pack(pcall(fn, ...))
  if not r[1] then
    note(path, "error", tostring(r[2]))
    return false, "error", r[2]
  end
  local anySecret = false
  for i = 2, r.n do
    if Compat.IsSecret(r[i]) then r[i] = Compat.SECRET; anySecret = true end
  end
  note(path, anySecret and "secret" or "ok")
  return true, unpack(r, 2, r.n)
end

-- One value: the first return, or nil (with why: "missing", "error", "secret", "nil").
function Compat.Value(path, ...)
  local ok, v = Compat.Call(path, ...)
  if not ok then return nil, v end
  if v == Compat.SECRET then return nil, "secret" end
  if v == nil then return nil, "nil" end
  return v
end

-- A field of a table the game returned, guarded against hidden fields.
function Compat.Field(t, key)
  if type(t) ~= "table" or t == Compat.SECRET then return nil end
  local ok, v = pcall(function() return t[key] end)
  if not ok or Compat.IsSecret(v) then return nil end
  return v
end

function Compat.InCombat()
  local v = Compat.Value("UnitAffectingCombat", "player")
  if v ~= nil then return v and true or false end
  return Compat.Value("InCombatLockdown") and true or false
end
