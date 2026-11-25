-- Reading an item's stats and scoring it against what you wear.
local _, ns = ...
local S = {}
ns.Score = S
local Readable = ns.Readable

-- the game's stat keys -> ours
local KEYS = {
  RESISTANCE1_NAME = "RES_HOLY", RESISTANCE2_NAME = "RES_FIRE", RESISTANCE3_NAME = "RES_NATURE",
  RESISTANCE4_NAME = "RES_FROST", RESISTANCE5_NAME = "RES_SHADOW", RESISTANCE6_NAME = "RES_ARCANE",
  ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
  ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI", RESISTANCE0_NAME = "ARMOR",
  ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
  ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
  ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
  ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_HIT_RATING_SHORT = "HIT",
  ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELLCRIT", ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPELLHIT",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF",
  ITEM_MOD_DODGE_RATING_SHORT = "DODGE", ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
  ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK", ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE",
  ITEM_MOD_HASTE_RATING_SHORT = "HASTE", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE",
  ITEM_MOD_HEALTH_SHORT = "HEALTH", ITEM_MOD_HEALTH = "HEALTH",
  ITEM_MOD_EXPERTISE_RATING_SHORT = "EXPERTISE", ITEM_MOD_SPELL_PENETRATION_SHORT = "SPELLPEN",
  ITEM_MOD_HEALTH_REGEN_SHORT = "HP5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
}

-- Classic items often put these on "Equip:" lines instead of in the stat list (English client)
-- (numbers can have decimals: "by 1.0%". Spell-only wordings come first, so "spell critical strike
-- chance" isn't read as plain crit; "the crit chance OF a spell" is an effect, see Effects.lua)
local N = "(%d+%.?%d*)"
-- { pattern, stat key(s) }: the first that matches a line wins
local EQUIP = {
  -- both kinds at once
  { "hit with all spells and attacks by " .. N .. "%%", "HIT", "SPELLHIT" },
  { "critical strike with all spells and attacks by " .. N .. "%%", "CRIT", "SPELLCRIT" },
  -- spells
  { "critical strike with spells by " .. N .. "%%", "SPELLCRIT" },
  { "critical strike with %a+ spells by " .. N .. "%%", "SPELLCRIT" }, -- (a school: "with Holy spells")
  { "critically hit with spells by " .. N .. "%%", "SPELLCRIT" },
  { "hit with %a+ spells by " .. N .. "%%", "SPELLHIT" },
  { "spell critical strike chance by " .. N .. "%%", "SPELLCRIT" },
  { "spell crit chance by " .. N .. "%%", "SPELLCRIT" },
  { "hit with spells by " .. N .. "%%", "SPELLHIT" },
  { "spell hit chance by " .. N .. "%%", "SPELLHIT" },
  -- melee / ranged
  { "critical strike with %a+ weapons by " .. N .. "%%", "CRIT" }, -- ("with missile weapons", "with ranged weapons")
  { "critical strike chance with %a+ weapons by " .. N .. "%%", "CRIT" },
  { "hit with %a+ weapons by " .. N .. "%%", "HIT" },
  { "critical strike with melee attacks by " .. N .. "%%", "CRIT" },
  { "critical strike with ranged attacks by " .. N .. "%%", "CRIT" },
  { "critical effect chance of your %a+ spells by " .. N .. "%%", "SPELLCRIT" },
  { "spell critical chance of all party members within %d+ yards by " .. N .. "%%", "SPELLCRIT" },
  { "critical strike by " .. N .. "%%", "CRIT" },
  { "critically hit by " .. N .. "%%", "CRIT" },
  { "critical strike chance by " .. N .. "%%", "CRIT" },
  { "crit chance by " .. N .. "%%", "CRIT" },
  { "chance to crit by " .. N .. "%%", "CRIT" },
  { "chance to hit by " .. N .. "%%", "HIT" },
  { "hit chance by " .. N .. "%%", "HIT" },
  -- health, health regeneration
  { "maximum health by (%d+)", "HEALTH" },
  { "[Rr]estores (%d+) [Hh]ealth per 5 sec", "HP5" },
  -- expertise, spell penetration
  { "[Rr]educes chance to be [Dd]odged or [Pp]arried by " .. N .. "%%", "EXPERTISE" },
  { "[Dd]ecreases the magical resistances of your spell targets by (%d+)", "SPELLPEN" },
  { "[Yy]our spells pierce (%d+) [Mm]agical [Rr]esistances", "SPELLPEN" },
  -- spell damage and healing (a school's spell damage counts as spell damage)
  { "damage and healing done by magical spells and effects by up to (%d+)", "SP" },
  { "damage and healing done by magical spells and effects of all party members within %d+ yards by up to (%d+)", "SP" },
  { "healing done by magical spells and effects of all party members within %d+ yards by up to (%d+)", "HEAL" },
  { "spell damage and healing by up to (%d+)", "SP" },
  { "damage done by %a+ spells and effects by up to (%d+)", "SP" },
  { "spell damage by up to (%d+)", "SP" },
  { "%+(%d+) [Ss]pell [Dd]amage", "SP" },
  { "%+(%d+) [Ss]pell [Pp]ower", "SP" },
  { "healing done by [%a ]-spells and effects by up to (%d+)", "HEAL" },
  { "healing done by spells by up to (%d+)", "HEAL" },
  { "healing by up to (%d+)", "HEAL" },
  { "%+(%d+) [Hh]ealing", "HEAL" },
  -- mana
  { "[Rr]estores (%d+) [Mm]ana per 5 sec", "MP5" },
  { "(%d+) mana every 5 sec", "MP5" },
  -- attack power (ranged first)
  { "%+(%d+) [Rr]anged [Aa]ttack [Pp]ower", "RAP" },
  { "[Ii]ncreases ranged attack power by (%d+)", "RAP" },
  { "%+(%d+) [Aa]ttack [Pp]ower", "AP" },
  { "[Ii]ncreases [Aa]ttack [Pp]ower by (%d+)", "AP" },
  { "[Ii]ncreases your [Aa]ttack [Pp]ower by (%d+)", "AP" },
  { "[Ii]ncreases melee and ranged attack power by (%d+)", "AP" },
  -- tanking
  { "dodge an attack by " .. N .. "%%", "DODGE" },
  { "parry an attack by " .. N .. "%%", "PARRY" },
  { "block attacks with a shield by " .. N .. "%%", "BLOCK" },
  { "block value of your shield by (%d+)", "BLOCKVALUE" },
  { "[Ii]ncreased [Dd]efense %+(%d+)", "DEF" },
  { "%+(%d+) [Dd]efense", "DEF" },
  { "^Equip: %+(%d+) [Aa]rmor%.?$", "ARMOR" },
  { "[Dd]efense by (%d+)", "DEF" },
}
-- bonuses only against some enemies don't count as the stat all the time
local SITUATIONAL = { "when fighting", "against ", "to undead", "to demons", "undead and demons",
  "pet", "your imp", "your voidwalker", "your succubus", "your felhunter", "minion", "battle ring" }
-- a buff for a while (a proc or a Use), not a stat you always have
local TIMED = { "chance on", "chance when", "chance per", "have a chance", "has a chance", "gives a chance", "%d%% chance",
  "chance to gain", "chance to strike", "chance to deal", "chance to restore", "chance to increase", "chance to grant",
  "for %d+%.?%d* sec", "for %d+ min", "when struck", "when hit" }

local RES_KEY = { holy = "RES_HOLY", fire = "RES_FIRE", nature = "RES_NATURE", frost = "RES_FROST",
  shadow = "RES_SHADOW", arcane = "RES_ARCANE" }
S.RES_KEY = RES_KEY

local function IsRed(c)
  return type(c) == "table" and Readable(c.r) and c.r > 0.9 and c.g < 0.3 and c.b < 0.3
end

-- what the item tooltip says: Equip-line stats, and whether something on it is red
-- (can't use it: armor type, weapon skill, class, level)
-- (also: every line's text, for the effects, and the weapon's speed)
-- (also: whether the item's text could be read at all: right after login, or for an item the game
-- hasn't loaded yet, it can't, and then its effects are missing)
local function TooltipFacts(link)
  local extra, red, texts, speed = {}, false, {}, nil
  if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return extra, red, texts, nil, true end
  local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
  if not (ok and type(data) == "table" and type(data.lines) == "table") then return extra, red, texts, nil, false end
  for i, l in ipairs(data.lines) do
    if i > 1 and (IsRed(l.leftColor) or IsRed(l.rightColor)) then red = true end
    local t = Readable(l.leftText) and l.leftText or ""
    texts[#texts + 1] = t
    local r = Readable(l.rightText) and l.rightText or ""
    speed = speed or tonumber(r:match("^Speed (%d+%.?%d*)") or t:match("Speed (%d+%.?%d*)") or "")
    local lt = t:lower()
    -- "crit chance of Lightning Bolt": an effect (but "chance with ranged weapons" is a stat)
    local perSpell = (lt:find(" chance of ") or lt:find(" chance with ")) and not lt:find(" weapons by ")
      and not lt:find("of your %a+ spells by") and not lt:find("party members")
    local timed = false
    for _, w in ipairs(TIMED) do
      if lt:find(w) then timed = true end
    end
    perSpell = perSpell or timed
    -- resistances ("+10 Fire Resistance", "+5 All Resistances"): when the stat list doesn't have them
    local rn, school = t:match("^%+(%d+) (%a+) Resistance$")
    local all = t:match("^%+(%d+) [Aa]ll [Rr]esistances$")
    if rn and RES_KEY[school:lower()] then extra[RES_KEY[school:lower()]] = (extra[RES_KEY[school:lower()]] or 0) + tonumber(rn) end
    if all then for _, k in pairs(RES_KEY) do extra[k] = (extra[k] or 0) + tonumber(all) end end
    if (t:find("^Equip:") and not perSpell) or t:find("^%+%d+ [Aa]ttack") then
      local lower = t:lower()
      local situational = false
      for _, w in ipairs(SITUATIONAL) do if lower:find(w, 1, true) then situational = true end end
      for _, p in ipairs(situational and {} or EQUIP) do
        local n = t:match(p[1])
        if n then
          for k = 2, #p do extra[p[k]] = (extra[p[k]] or 0) + tonumber(n) end
          break
        end
      end
    end
  end
  -- (only the name so far: its text hasn't loaded)
  return extra, red, texts, speed, #data.lines > 1
end

-- Stats that are a % on the item ("Improves your chance to hit by 1.0%"). WoW: Forever lists them
-- in the item's stats as ratings (that 1% as 10 hit rating), so: the % from the item's own line
-- when it has one; a rating with no such line, turned into a % the way the game does for you.
local PCT_STATS = { HIT = 6, CRIT = 9, SPELLHIT = 8, SPELLCRIT = 11, DODGE = 3, PARRY = 4, BLOCK = 5, HASTE = 18, EXPERTISE = 24 } -- (their combat rating IDs)
-- when the game won't say: rating per 1% at level 60 (wowsims/forever, foreverdb.net)
local RATING_PER_PCT = { HIT = 10, SPELLHIT = 10, CRIT = 14, SPELLCRIT = 14, HASTE = 10, DODGE = 12, PARRY = 15, BLOCK = 5, EXPERTISE = 10 }
S.RATING_PER_PCT = RATING_PER_PCT
local function RatingToPct(key, rating)
  local cr = PCT_STATS[key]
  if GetCombatRatingBonusForCombatRatingValue then -- (the game's own conversion, for any amount)
    local ok, b = pcall(GetCombatRatingBonusForCombatRatingValue, cr, rating)
    if ok and Readable(b) and type(b) == "number" and b > 0 then return b end
  end
  if GetCombatRating and GetCombatRatingBonus then
    local ok1, r = pcall(GetCombatRating, cr)
    local ok2, b = pcall(GetCombatRatingBonus, cr)
    if ok1 and ok2 and Readable(r) and Readable(b) and type(r) == "number" and type(b) == "number" and r > 0 and b > 0 then
      return rating * b / r -- (% per rating for you, from what you wear now)
    end
  end
  return rating / (RATING_PER_PCT[key] or 10)
end

-- Enchants (Enchants.lua: ns.ENCHANTS, from Forever's tables). An item is read without its enchant, then
-- the enchant's own effect is added (so it's never counted twice): stats ("+5 Strength", wizard oil's
-- spell power...), weapon damage (stones, "+3 Damage") and procs (Crusader, Fiery Weapon, poisons).
local function Unenchanted(link) return (link:gsub("(item:%d+):%d*", "%1:", 1)) end
local function EnchantOf(link) return tonumber(link:match("item:%d+:(%d+)") or "") end
-- an enchant's effect added to an item's facts (stats, weapon damage, a proc)
function S.AddEnchant(f, id)
  local e = id and ns.ENCHANTS and ns.ENCHANTS[id]
  if not e then return end
  for k, v in pairs(e[4] or {}) do f.stats[k] = (f.stats[k] or 0) + v end
  if (e[3] or 0) > 0 and f.stats.DPS and f.speed and f.speed > 0 then f.stats.DPS = f.stats.DPS + e[3] / f.speed end
  local pr = e[5]
  if pr then
    local chance = (pr.chance or 0) > 0 and pr.chance or nil -- (none given: about once a minute)
    if pr.damage then
      f.effects[#f.effects + 1] = { kind = "procDamage", avg = pr.damage, trigger = "melee", chance = chance, enchant = true, text = e[1] }
    elseif pr.stat then
      f.effects[#f.effects + 1] = { kind = "procStat", stat = pr.stat, amount = pr.amount, dur = pr.seconds, trigger = "melee", chance = chance, enchant = true, text = e[1] }
    end
  end
end

local cache = {}
-- { stats = { STR = 5, ... }, equipLoc = "INVTYPE_...", usable = bool, sell = copper } or nil (not loaded yet)
-- (with its permanent enchant)
function S.Facts(link)
  if type(link) ~= "string" then return nil end
  if cache[link] then return cache[link] end
  local enchant = EnchantOf(link)
  local full = link
  link = Unenchanted(link)
  local equipLoc = C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(link))
  if not equipLoc or equipLoc == "" then return nil end
  local stats = {}
  local raw = C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link) or (GetItemStats and GetItemStats(link))
  if type(raw) ~= "table" then return nil end -- not loaded yet
  for k, v in pairs(raw) do
    local key = KEYS[k]
    if key and type(v) == "number" then stats[key] = (stats[key] or 0) + v end
  end
  local extra, red, texts, speed, complete = TooltipFacts(link)
  for k, v in pairs(stats) do
    if PCT_STATS[k] and not extra[k] then stats[k] = RatingToPct(k, v) end -- (a rating with no % line)
  end
  -- what the item's own lines say: fills in what the stat list lacks, and gives a %'s true value
  for k, v in pairs(extra) do if not stats[k] or PCT_STATS[k] then stats[k] = v end end
  local sell = select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(link))
  local subType = C_Item and C_Item.GetItemInfoInstant and select(3, C_Item.GetItemInfoInstant(link))
  local f = { id = tonumber(link:match("item:(%d+)")), stats = stats, equipLoc = equipLoc, subType = type(subType) == "string" and subType:lower() or nil, usable = not red, sell = type(sell) == "number" and sell or 0,
    speed = speed, effects = ns.Effects and ns.Effects.Parse(texts) or {} }
  if enchant and enchant > 0 then S.AddEnchant(f, enchant); f.enchant = enchant end
  -- Kept for next time only once the item's text was read: one read before it loads has no effect
  -- lines (a "+10% Stormstrike" weapon would score as if it had none, for the whole session).
  if complete then cache[full] = f end
  return f
end

function S.ClearCache()
  wipe(cache); S.ForgetCompared(); if S.ForgetBags then S.ForgetBags() end
  if ns.Talents then ns.Talents.Forget() end
  if ns.Effects then ns.Effects.ClearCache() end
end

local WEAPON_LOCS = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local RANGED_LOC = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local OFF_LOC = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

-- the slots an item can go in
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
S.SLOTS = SLOTS

local function DualWields()
  if _G.CanDualWield then local ok, v = pcall(_G.CanDualWield); if ok then return v end end
  return false
end

local PAIRED = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }

-- Your best armor type from level 40 (Classic's mail and plate): with the setting on, cloth or leather
-- (and mail, for plate wearers) isn't an upgrade. Off by default: Forever has no armor specialization,
-- so a better-statted lighter piece really is better. Returns "mail" / "plate" when it's lower.
local BEST_ARMOR = { SHAMAN = 3, HUNTER = 3, WARRIOR = 4, PALADIN = 4 } -- (armor subclass: 1 cloth, 2 leather, 3 mail, 4 plate)
local ARMOR_NAME = { [3] = "mail", [4] = "plate" }
function S.LowerArmor(link, equipLoc)
  if not (ns.db and ns.db.bestArmorOnly) then return nil end
  if equipLoc == "INVTYPE_CLOAK" or not (UnitLevel and UnitLevel("player") >= 40) then return nil end
  local _, class = UnitClass("player")
  local bestType = BEST_ARMOR[class]
  if not bestType then return nil end
  local classID, subID = select(6, C_Item.GetItemInfoInstant(link))
  if classID == 4 and type(subID) == "number" and subID >= 1 and subID < bestType then return ARMOR_NAME[bestType] end
end

-- Gear in your bags you could wear: { { link, equipLoc } }, kept until your bags change
local bagItems
function S.ForgetBags() bagItems = nil; S.ForgetCompared() end
local function BagItems()
  if bagItems then return bagItems end
  bagItems = {}
  local C = C_Container
  local slotsOf = (C and C.GetContainerNumSlots) or GetContainerNumSlots
  local linkOf = (C and C.GetContainerItemLink) or GetContainerItemLink
  if not (slotsOf and linkOf) then return bagItems end
  for bag = 0, 4 do
    local ok, n = pcall(slotsOf, bag)
    for slot = 1, (ok and type(n) == "number") and n or 0 do
      local okL, l = pcall(linkOf, bag, slot)
      if okL and type(l) == "string" and l:find("item:", 1, true) then
        local loc = C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(l))
        if loc and SLOTS[loc] then bagItems[#bagItems + 1] = { l, loc, bag, slot } end
      end
    end
  end
  return bagItems
end
-- equip slots that hold the same things (a robe is a chest, a shield an off hand...)
local FAMILY = { INVTYPE_ROBE = "INVTYPE_CHEST", INVTYPE_SHIELD = "INVTYPE_WEAPONOFFHAND", INVTYPE_HOLDABLE = "INVTYPE_WEAPONOFFHAND",
  INVTYPE_WEAPONMAINHAND = "INVTYPE_WEAPON", INVTYPE_RANGEDRIGHT = "INVTYPE_RANGED", INVTYPE_THROWN = "INVTYPE_RANGED" }
local function Family(loc) return FAMILY[loc] or loc end
function S.BagList() return BagItems() end
---------------------------------------------------------------------------
-- Scoring. An item's value is a % of your build's measure, from your gear:
--  - its stats times your values (Weights.lua) plus its effects (Effects.lua), as a % of what your
--    whole gear scores that way; for each side of your build (damage or healing, and for tanks the
--    class's damage spec),
--  - survival: the % it adds to your effective health (health, and armor's cut of physical damage);
--    for tanks, their own values are survival (Forever Upgrades' tanking weights),
--  mixed by your build (Damage, Leveling, Balanced, Survival, or your mix).
-- Hit, spell hit, expertise (and a tank's defense at the level cap) count up to their cap, measured
-- against your gear and talents without the items being replaced.
---------------------------------------------------------------------------
local function Num(v) return (type(v) == "number" and Readable(v)) and v or 0 end
local function Call(fn, ...)
  if not fn then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return select(2, unpack(r))
end

local sides, totals -- (kept until something changes: S.ClearCache)

-- your hit, spell hit and expertise in %, and defense skill from gear and talents, as the game has them
function S.Totals()
  if totals then return totals end
  local function cr(id) return GetCombatRatingBonus and Num(Call(GetCombatRatingBonus, id)) or 0 end
  totals = {
    HIT = cr(CR_HIT_MELEE or 6) + Num(Call(GetHitModifier)),
    SPELLHIT = cr(CR_HIT_SPELL or 8) + Num(Call(GetSpellHitModifier)),
    EXPERTISE = cr(CR_EXPERTISE or 24),
    DEF = Num(select(2, Call(UnitDefense, "player"))),
  }
  return totals
end

-- the caps in force for a spec: { stat = { cap, worth past it (x), for how far past it } }
-- (level cap, against bosses three levels up: melee 9%, spell 16%, dodge 6.5%; a tank's defense +140
-- for crit immunity. Below it, against your level: 5%, 4%, 5%. Dual wielders' white swings miss 19%
-- more, so hit past the cap still helps them a little.)
function S.Caps(key)
  key = key or ns.SpecKey()
  local g = ns.GUIDE and ns.GUIDE[key] or {}
  local atMax = (UnitLevel and UnitLevel("player") or 1) >= ns.MaxLevel()
  local caps = {}
  if g.hitCap ~= false or not g.role then
    local dw = DualWields() and (ns.Class() == "ROGUE" or ns.Class() == "WARRIOR")
    caps.HIT = { atMax and 9 or 5, dw and 0.3 or 0, dw and 19 or 0 }
    caps.SPELLHIT = { atMax and 16 or 4, 0, 0 }
  end
  caps.EXPERTISE = { atMax and 6.5 or 5, 0, 0 }
  if ns.IsTank(key) and atMax then caps.DEF = { 140, 0.2, 1000 } end
  return caps
end
-- how much of x counts at full value under a cap
local function Useful(x, c)
  if x <= c[1] then return math.max(0, x) end
  return c[1] + math.min(x - c[1], c[3]) * c[2]
end
S.Useful = Useful

-- how much of a weapon's DPS counts in a slot: in full in the main hand, half in the off hand; a
-- ranged weapon's only for hunters (and theirs only: a melee weapon's barely, except Survival's)
local function WeaponShare(f, slot)
  if not WEAPON_LOCS[f.equipLoc] then return 0 end
  local hunter = ns.Class() == "HUNTER"
  if RANGED_LOC[f.equipLoc] or slot == 18 then return hunter and 1 or 0 end
  if hunter then return ns.SpecKey() == "HUNTER:3" and 0.5 or 0.1 end
  return slot == 17 and 0.5 or 1
end

-- an item's points with a set of values, in a slot; capped stats against `other` (your totals
-- without the items it replaces). Returns the points and { stat = points }.
local function Points(f, w, slot, other, caps)
  local pts, parts = 0, {}
  for k, v in pairs(f.stats) do
    local x = w[k] or 0
    if x ~= 0 then
      local amount = (k == "DPS") and v * WeaponShare(f, slot) or v
      local c = caps and caps[k]
      local val
      if c and other then
        local o = other[k] or 0
        val = (Useful(o + amount, c) - Useful(o, c)) * x
      else
        val = amount * x
      end
      if val ~= 0 then pts = pts + val; parts[k] = (parts[k] or 0) + val end
    end
  end
  return pts, parts
end

---------------------------------------------------------------------------
-- Effective health (EHP), the way Forever Upgrades works it out for tanks: your health divided by the
-- share of an enemy's raw melee damage you actually take. Each swing rolls once on Classic's table, in
-- order: miss (5% + 0.04% per Defense point over the enemy's weapon skill), dodge, parry, block (with a
-- shield; Shield Block / Holy Shield add to it), crit (5% + 0.04% per point of skill over your Defense:
-- double damage), crushing blow (bosses: 15%, +50%), else a normal hit. Armor cuts all of it
-- (armor / (armor + K), K from the enemy's level), and a block takes your block value off the hit.
-- The enemy: at the level cap a boss three levels up (as the site's sim), below it one of your level.
-- Checked against the site's sim: health, armor's cut, miss and crit chance match its numbers.
-- On top of the site's model (melee only), Equip This! counts magic damage too: a share of the raw
-- damage coming at you is spells. While leveling 20%, split evenly (casters and elementals among the
-- enemies). At the level cap, from Naxxramas (where the site's BiS gear drops), measured on Warcraft
-- Logs (90 kills, 40-player Classic raids): tanks 12% (mostly shadow, fire, nature, frost: the Four
-- Horsemen's marks, Sapphiron, Kel'Thuzad, Loatheb), everyone else 75% (nature, shadow, frost: volleys,
-- Chain Lightning, Inevitable Doom, Frost Aura; bosses seldom melee them). Spells can't be dodged,
-- parried or blocked and armor doesn't touch them; your resistance to the school cuts them by 75% x
-- resistance / (5 x the enemy's level) on average (Classic), at most 75%.
-- { share of raw damage that's magic, { school = part of it } }
S.MAGIC = {
  leveling = { 0.2, { RES_FIRE = 0.2, RES_FROST = 0.2, RES_NATURE = 0.2, RES_SHADOW = 0.2, RES_ARCANE = 0.2 } },
  tank = { 0.12, { RES_SHADOW = 0.36, RES_FIRE = 0.20, RES_NATURE = 0.19, RES_FROST = 0.17, RES_HOLY = 0.04, RES_ARCANE = 0.04 } },
  raid = { 0.75, { RES_NATURE = 0.30, RES_SHADOW = 0.25, RES_FROST = 0.25, RES_FIRE = 0.10, RES_ARCANE = 0.05, RES_HOLY = 0.05 } },
}
local RES_INDEX = { RES_HOLY = 1, RES_FIRE = 2, RES_NATURE = 3, RES_FROST = 4, RES_SHADOW = 5, RES_ARCANE = 6 }
---------------------------------------------------------------------------
local function ArmorK(a) if a > 59 then return 467.5 * a - 22167.5 end return 400 + 85 * a end

local function Known(name)
  if not (C_Spell and C_Spell.GetSpellInfo) then return false end
  local ok, info = pcall(C_Spell.GetSpellInfo, name)
  if not (ok and type(info) == "table" and Readable(info.spellID)) then return false end
  if IsPlayerSpell then local ok2, k = pcall(IsPlayerSpell, info.spellID); if ok2 and Readable(k) then return k and true or false end end
  return true
end

-- you now, for the EHP formula
function S.EHPState()
  local L = UnitLevel and UnitLevel("player") or 60
  local atMax = L >= ns.MaxLevel()
  local base, mod = Call(UnitDefense, "player")
  local st = {
    L = L, a = atMax and L + 3 or L, boss = atMax,
    H = math.max(1, Num(Call(UnitHealthMax, "player"))),
    A = Num(select(2, Call(UnitArmor, "player"))),
    D = Num(base) + Num(mod),
    dodge = Num(Call(GetDodgeChance)), parry = Num(Call(GetParryChance)),
    block = Num(Call(GetBlockChance)), bv = Num(Call(GetShieldBlock)),
  }
  if st.D <= 0 then st.D = 5 * L end
  st.res = {}
  for k, i in pairs(RES_INDEX) do st.res[k] = Num(select(2, Call(UnitResistance, "player", i))) end
  local m = S.MAGIC[(not atMax and "leveling") or (ns.IsTank() and "tank") or "raid"]
  st.magic, st.schools = m[1], m[2]
  st.shield = st.block > 0
  st.extraBlock, st.uptime = 0, 0
  if st.shield then
    -- (Forever: Shield Block +75% block for 6 s or two blocks, every 5 s: up for about 83% of a boss's
    -- swings in the site's sim; Holy Shield +30%, most of the time)
    if ns.Class() == "WARRIOR" and Known("Shield Block") then st.extraBlock, st.uptime = 75, 0.83
    elseif ns.Class() == "PALADIN" and Known("Holy Shield") then st.extraBlock, st.uptime = 30, 0.8 end
  end
  -- a Protection warrior tanks in Defensive Stance: 10% less damage taken
  st.cut = (ns.SpecKey() == "WARRIOR:3" and Known("Defensive Stance")) and 0.9 or 1
  -- an enemy's raw swing: a level 63 boss about 2,000 (the site's sim), a normal enemy about 2 x its level
  st.swing = atMax and 32 * st.a or 2 * st.a
  return st
end

-- EHP for a state, and the share of the enemy's raw damage you take
function S.EHP(st)
  local dr = math.min(st.A / (st.A + ArmorK(st.a)), 0.75)
  local skill = 5 * st.a
  local hit = st.swing * (1 - dr)
  local blocked = math.max(0, 1 - st.bv / math.max(hit, 1)) -- (a block takes your block value off the hit)
  -- one swing's damage, as a share of its raw damage, with a given block chance
  local function swing(blockPct)
    local left = 1
    local function take(p) p = math.max(0, math.min(p, left)); left = left - p; return p end
    take((5 + (st.D - skill) * 0.04) / 100)                -- miss
    take(st.dodge / 100); take(st.parry / 100)              -- dodge, parry
    local block = st.shield and take(blockPct / 100) or 0
    local crit = take((5 + (skill - st.D) * 0.04) / 100)
    local crush = st.boss and take(0.15) or 0
    return (1 - dr) * (left + 2 * crit + 1.5 * crush + block * blocked)
  end
  -- (Shield Block / Holy Shield: up for some swings, down for the rest)
  local melee = swing(st.block) * (1 - st.uptime) + swing(st.block + st.extraBlock) * st.uptime
  -- spells: each school's share, less your resistance's cut
  local spell = 0
  for k, part in pairs(st.schools or {}) do
    spell = spell + part * (1 - math.min(0.75, 0.75 * math.max(0, (st.res and st.res[k]) or 0) / (5 * st.a)))
  end
  local m = st.magic or 0
  local taken = ((1 - m) * melee + m * spell) * (st.cut or 1)
  return st.H / math.max(taken, 0.001), taken, dr, melee, spell
end

-- what a stat on an item changes in that state (per unit: 1 Stamina = 10 health, 1 Agility = 2 armor and
-- about 1% dodge per level/3, 1 Defense = +0.04% dodge, parry and block)
local function AddStat(st, k, n)
  if k == "STA" then st.H = st.H + 10 * n
  elseif k == "HEALTH" then st.H = st.H + n
  elseif k == "ARMOR" then st.A = st.A + n
  elseif k == "AGI" then st.A = st.A + 2 * n; st.dodge = st.dodge + n / math.max(1, st.L / 3)
  elseif k == "DEF" then
    st.D = st.D + n
    st.dodge, st.parry = st.dodge + 0.04 * n, st.parry + 0.04 * n
    if st.shield then st.block = st.block + 0.04 * n end
  elseif k == "DODGE" then st.dodge = st.dodge + n
  elseif k == "PARRY" then st.parry = st.parry + n
  elseif k == "BLOCK" then st.block = st.block + n
  elseif k == "BLOCKVALUE" then st.bv = st.bv + n
  elseif RES_INDEX[k] then st.res = st.res or {}; st.res[k] = (st.res[k] or 0) + n
  end
end
local EHP_STATS = { STA = 10, HEALTH = 100, ARMOR = 100, AGI = 10, DEF = 5, DODGE = 1, PARRY = 1, BLOCK = 1, BLOCKVALUE = 10,
  RES_FIRE = 10, RES_FROST = 10, RES_NATURE = 10, RES_SHADOW = 10, RES_ARCANE = 10, RES_HOLY = 10 }

-- survival: % more EHP per unit of each stat, from you now
local function EHPer()
  local st = S.EHPState()
  local now = S.EHP(st)
  local per = {}
  for k, d in pairs(EHP_STATS) do
    local t = {}
    for x, v in pairs(st) do t[x] = v end
    t.res = {}
    for x, v in pairs(st.res or {}) do t.res[x] = v end
    AddStat(t, k, d)
    per[k] = (S.EHP(t) / now - 1) * 100 / d
  end
  return per
end
S.EHPer = EHPer

local function WornEach(fn)
  for slot = 1, 18 do
    if slot ~= 4 then
      local l = GetInventoryItemLink and GetInventoryItemLink("player", slot)
      local f = l and S.Facts(l)
      if f then fn(f, slot) end
    end
  end
end

-- Your character without gear, in points for a set of values: your base Strength, Agility, Stamina,
-- Intellect and Spirit (level and talents), the attack power your level gives, and the crit and hit
-- your talents give. Items are a % of this plus your gear, so the % is close to the change in your
-- whole output (and on the same scale as effects like "+10% Stormstrike", which are % of output).
-- Returns the points and { stat = points }.
local STAT_INDEX = { STR = 1, AGI = 2, STA = 3, INT = 4, SPI = 5 }
local LEVEL_AP = { WARRIOR = true, PALADIN = true, SHAMAN = true, ROGUE = true, HUNTER = true, DRUID = true }
function S.Base(w)
  local gear = {}
  WornEach(function(f) for k, v in pairs(f.stats) do gear[k] = (gear[k] or 0) + v end end)
  local pts, parts = 0, {}
  local function add(k, amount)
    local x = w[k] or 0
    if amount > 0 and x ~= 0 then pts = pts + amount * x; parts[k] = (parts[k] or 0) + amount * x end
  end
  local eff = {}
  for k, i in pairs(STAT_INDEX) do
    local base, e = Call(UnitStat, "player", i)
    base, e = Num(base), Num(e)
    local g = gear[k] or 0
    eff[k] = e
    -- (Classic-style sheets put gear in the bonus part: the base is you; else gear is in the base)
    add(k, (e - base >= g - 0.5) and base or math.max(0, base - g))
  end
  local level = UnitLevel and UnitLevel("player") or 1
  if LEVEL_AP[ns.Class()] then add("AP", math.max(0, level * 2 - 20)) end -- (Classic: 2 per level, less 20)
  -- crit and hit beyond your gear's and your stats' (talents, your class's base): what the game says,
  -- less your gear's, less what your Agility / Intellect give (about level/3 Agility and level
  -- Intellect per 1% crit, as in Classic)
  local function first(fn, ...) return Num(Call(fn, ...)) end
  local crit = first(GetCritChance) - (gear.CRIT or 0) - (eff.AGI or 0) / math.max(1, level / 3)
  local scrit = 0
  for i = 2, 7 do scrit = math.max(scrit, first(GetSpellCritChance, i)) end
  scrit = scrit - (gear.SPELLCRIT or 0) - (eff.INT or 0) / math.max(1, level)
  add("CRIT", math.max(0, crit)); add("SPELLCRIT", math.max(0, scrit))
  local caps = S.Caps()
  local hit = first(GetHitModifier) - (gear.HIT or 0)
  local shit = first(GetSpellHitModifier) - (gear.SPELLHIT or 0)
  add("HIT", math.max(0, caps.HIT and math.min(hit, caps.HIT[1]) or hit))
  add("SPELLHIT", math.max(0, caps.SPELLHIT and math.min(shit, caps.SPELLHIT[1]) or shit))
  return pts, parts
end

-- What your character brings to its output, in points, from Forever Upgrades' Sim DPS (Guides.lua:
-- `character`, at levels 30 / 40 / 50 / 60): base stats, its spells' own damage, talents, self-buffs.
-- Between those levels it's blended; below 30 it shrinks with your level. nil when there's none.
function S.Character(key, level)
  local g = ns.GUIDE and ns.GUIDE[key]
  local c = g and g.character
  if not c then return nil end
  level = level or (UnitLevel and UnitLevel("player")) or 60
  local lv = {}
  for l in pairs(c) do lv[#lv + 1] = l end
  table.sort(lv)
  if #lv == 0 then return nil end
  if level <= lv[1] then return c[lv[1]] * math.max(level, 1) / lv[1] end
  for i = 2, #lv do
    if level <= lv[i] then
      local a, b = lv[i - 1], lv[i]
      return c[a] + (c[b] - c[a]) * (level - a) / (b - a)
    end
  end
  return c[lv[#lv]]
end

-- your build's sides: { { kind = "points" | "eh", w = values, share, total (you and your gear, in points) } }
function S.Sides()
  if sides then return sides end
  local key = ns.SpecKey()
  local t = ns.SurvivalShare(key)
  local own = ns.Weights(key)
  local list = {}
  if ns.IsTank(key) then
    -- a tank: survival is your EHP (the site's own measure for tanks); damage from the class's damage
    -- spec's values (and its calibration)
    list[1] = { kind = "eh", w = EHPer(), share = t, label = "survival" }
    -- (a tank spec's damage: the class's damage spec; "I tank" on another spec: its own values)
    local dk = ns.IsTankSpec(key) and ns.GUIDE and ns.GUIDE[key] and ns.GUIDE[key].damageSpec
    local dw = dk and ns.SiteWeights(dk) or own
    list[2] = { kind = "points", w = dw, share = 1 - t, label = "damage", calKey = dk or key }
  else
    list[1] = { kind = "points", w = own, share = 1 - t, label = (ns.GUIDE[key] and ns.GUIDE[key].unit == "HPS") and "healing" or "damage", own = true }
    list[2] = { kind = "eh", w = EHPer(), share = t, label = "survival" }
  end
  -- what you score on each points side: your character, your gear's stats, then its effects (with 1%
  -- of you and your gear as +1% output)
  for _, side in ipairs(list) do
    if side.kind == "points" then
      local stats = 0
      WornEach(function(f, slot) stats = stats + Points(f, side.w, slot) end)
      side.gear = stats
      -- your character: calibrated against Forever Upgrades' Sim DPS (your spec's own side), else
      -- worked out from your base stats
      local cal = (side.own and S.Character(key)) or (side.calKey and S.Character(side.calKey))
      if cal then side.base, side.baseParts, side.calibrated = cal, {}, true
      else side.base, side.baseParts = S.Base(side.w) end
      stats = stats + side.base
      -- (a floor when the game won't say: about what a character scores at its level, so a first item
      -- isn't "+5000%")
      local floor = 3 * (UnitLevel and UnitLevel("player") or 1) * math.max(side.w.STR or 0, side.w.AGI or 0, side.w.INT or 0, side.w.SP or 0, side.w.HEAL or 0, side.w.STA or 0, 0.5)
      side.statsTotal = math.max(stats, floor, 1)
      local eff = 0
      if ns.Effects then
        local saved = ns.OUTPUT_PTS
        ns.OUTPUT_PTS = side.statsTotal / 100
        WornEach(function(f) local ok, p = pcall(ns.Effects.Points, f, side.w); if ok then eff = eff + (p or 0) end end)
        ns.OUTPUT_PTS = saved
      end
      side.total = math.max(stats + eff, side.statsTotal)
    end
  end
  sides = list
  return list
end

-- An item's value in a slot, in % of your build's measure: total, facts, { stat = % } (EFFECTS: its
-- effects), and the effect lines. `other`: your capped totals without the items it would replace.
function S.ValueIn(link, slot, other)
  local f = S.Facts(link)
  if not f then return nil end
  local caps = S.Caps()
  local total, parts, why = 0, {}, nil
  for _, side in ipairs(S.Sides()) do
    if side.share > 0 then
      if side.kind == "eh" then
        for k, v in pairs(f.stats) do
          local x = side.w[k]
          if x and x ~= 0 then
            local pct = v * x * side.share
            total = total + pct
            parts[k] = (parts[k] or 0) + pct
          end
        end
      else
        local pts, p = Points(f, side.w, slot, other, caps)
        local e, y = 0, nil
        if ns.Effects and #(f.effects or {}) > 0 then
          local saved = ns.OUTPUT_PTS
          ns.OUTPUT_PTS = side.statsTotal / 100
          local ok, ep, ey = pcall(ns.Effects.Points, f, side.w)
          ns.OUTPUT_PTS = saved
          if ok then e, y = ep or 0, ey end
        end
        local scale = 100 / side.total * side.share
        total = total + (pts + e) * scale
        for k, v in pairs(p) do parts[k] = (parts[k] or 0) + v * scale end
        if e ~= 0 then parts.EFFECTS = (parts.EFFECTS or 0) + e * scale end
        if y and #y > 0 then why = why or y end
      end
    end
  end
  return total, f, parts, why
end
-- (the value with no caps context, in the item's first slot)
function S.Value(link)
  local f = S.Facts(link)
  if not f then return nil end
  local slots = SLOTS[f.equipLoc]
  local v = S.ValueIn(link, slots and slots[1] or 0)
  return v, f
end

-- your capped totals without these items
local function Without(links)
  local o = {}
  for k, v in pairs(S.Totals()) do o[k] = v end
  for _, l in ipairs(links) do
    local f = l and S.Facts(l)
    if f then for k in pairs(o) do o[k] = o[k] - (f.stats[k] or 0) end end
  end
  return o
end

-- An item with no enchant of its own is compared with your enchant on it (the one on the item it'd
-- replace): an enchant can be put on it. Returns the link to score and the enchant's name, or nil.
function S.Carry(link, worn)
  if type(link) ~= "string" or type(worn) ~= "string" then return link, nil end
  local mine = tonumber(link:match("item:%d+:(%d+)") or "")
  local theirs = tonumber(worn:match("item:%d+:(%d+)") or "")
  local E = ns.ENCHANTS or {}
  if not (mine and mine > 0) and theirs and theirs > 0 and E[theirs] then
    return (link:gsub("(item:%d+):%d*", "%1:" .. theirs, 1)), E[theirs][1]
  end
  return link, nil
end

-- the % change from wearing `items` ({ { link, slot } }) in place of `out` (links in their slots):
-- gain, and { stat = % } of the difference
local function Swap(items, out)
  local outLinks = {}
  for _, o in ipairs(out) do outLinks[#outLinks + 1] = o[1] end
  local other = Without(outLinks)
  local gain, parts, why = 0, {}, nil
  for _, it in ipairs(items) do
    local v, _, p, y = S.ValueIn(it[1], it[2], other)
    if not v then return nil end
    gain = gain + v
    for k, x in pairs(p) do parts[k] = (parts[k] or 0) + x end
    why = why or y
  end
  for _, o in ipairs(out) do
    local v, _, p = S.ValueIn(o[1], o[2], other)
    gain = gain - (v or 0)
    for k, x in pairs(p or {}) do parts[k] = (parts[k] or 0) - x end
  end
  return gain, parts, why
end

local function worn(slot) return GetInventoryItemLink and GetInventoryItemLink("player", slot) end
local function locOf(l) return l and C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(l)) end

-- An item's best gain against what you wear, as a setup: a two-hander replaces main hand + off hand;
-- a one-hander replaces the main hand (or the off hand, if you dual wield and it does more there), and
-- replacing a two-hander it's paired with your best off-hand from your bags; an off-hand while you
-- wear a two-hander is paired with your best one-hander from your bags; rings and trinkets replace the
-- weaker of the two. Returns gain, vs (the item replaced), hand ("oh"), partner, empty slot, parts,
-- effect lines, the enchant it was given.
local function GainOf(link, f)
  local loc = f.equipLoc
  local function with(slot, out, extra)
    local cur = out[1] and out[1][1]
    local l, ench = S.Carry(link, cur)
    local items = { { l, slot } }
    if extra then items[2] = extra end
    local g, p, y = Swap(items, out)
    return g, p, y, ench
  end
  local mh, oh = worn(16), worn(17)
  if loc == "INVTYPE_2HWEAPON" then
    local out = {}
    if mh then out[#out + 1] = { mh, 16 } end
    if oh then out[#out + 1] = { oh, 17 } end
    local g, p, y, e = with(16, out)
    return g, mh or oh, nil, nil, #out == 0, p, y, e
  elseif loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then
    if mh and locOf(mh) == "INVTYPE_2HWEAPON" then
      local best, bp, by, be = with(16, { { mh, 16 } })
      local partner
      for _, b in ipairs(BagItems()) do
        local bl = b[1]
        if bl ~= link and (OFF_LOC[b[2]] or (b[2] == "INVTYPE_WEAPON" and DualWields())) then
          local bf = S.Facts(bl)
          if bf and bf.usable then
            local g, p, y, e = with(16, { { mh, 16 } }, { bl, 17 })
            if g and (not best or g > best) then best, bp, by, be, partner = g, p, y, e, bl end
          end
        end
      end
      return best, mh, nil, partner, false, bp, by, be
    end
    local g, p, y, e = with(16, mh and { { mh, 16 } } or {})
    local vs, hand = mh, nil
    if loc == "INVTYPE_WEAPON" and DualWields() then
      local g2, p2, y2, e2 = with(17, oh and { { oh, 17 } } or {})
      if g2 and (not g or g2 > g) then g, p, y, e, vs, hand = g2, p2, y2, e2, oh, "oh" end
    end
    return g, vs, hand, nil, vs == nil, p, y, e
  elseif OFF_LOC[loc] then
    if mh and locOf(mh) == "INVTYPE_2HWEAPON" then
      local best, bp, by, partner
      for _, b in ipairs(BagItems()) do
        if b[2] == "INVTYPE_WEAPON" or b[2] == "INVTYPE_WEAPONMAINHAND" then
          local bf = S.Facts(b[1])
          if bf and bf.usable then
            local g, p, y = Swap({ { link, 17 }, { b[1], 16 } }, { { mh, 16 } })
            if g and (not best or g > best) then best, bp, by, partner = g, p, y, b[1] end
          end
        end
      end
      if not best then return nil, nil, "twohand" end
      return best, mh, nil, partner, false, bp, by
    end
    local g, p, y, e = with(17, oh and { { oh, 17 } } or {})
    return g, oh, nil, nil, oh == nil, p, y, e
  elseif RANGED_LOC[loc] or loc == "INVTYPE_RELIC" then
    local rw = worn(18)
    local g, p, y, e = with(18, rw and { { rw, 18 } } or {})
    return g, rw, nil, nil, rw == nil, p, y, e
  end
  -- other slots; rings and trinkets: the weaker of the two you wear (an empty one first)
  local best, vs, empty, bp, by, be
  for _, slot in ipairs(SLOTS[loc] or {}) do
    local cur = worn(slot)
    local g, p, y, e = with(slot, cur and { { cur, slot } } or {})
    if g and (not best or g > best) then best, vs, empty, bp, by, be = g, cur, cur == nil, p, y, e end
  end
  return best, vs, nil, nil, empty, bp, by, be
end

-- How an item compares with what you own:
-- { kind = "upgrade" | "downgrade" | "same" | "new" | "unusable" | "equipped" | "twohand" | "armortype",
--   pct (of your build's measure), vs = link (worn, or in your bags with inBags), hand = "oh", partner,
--   pair = "weaker" | "stronger" | "equal" (equipped rings / trinkets), parts = { stat = % }, why = effect
--   lines, enchant = the name of yours it was given } or nil (not gear, or not loaded yet)
local compared, bagGains = {}, {}
function S.BagGain(link, fn)
  local g = bagGains[link]
  if g == nil then g = fn() or false; bagGains[link] = g end
  return g or nil
end
function S.ForgetCompared() wipe(compared); wipe(bagGains); sides = nil; totals = nil end
function S.Compare(link)
  local c = compared[link]
  if c == nil then
    c = S.CompareNow(link) or false
    if c then compared[link] = c end
  end
  return c or nil
end

function S.CompareNow(link)
  local f = S.Facts(link)
  if not f then return nil end
  local slots = SLOTS[f.equipLoc]
  if not slots then return nil end
  if not f.usable then return { kind = "unusable" } end
  local best = S.LowerArmor(link, f.equipLoc)
  if best then return { kind = "armortype", best = best } end
  local id = link:match("item:(%d+)")
  -- worn already?
  for _, slot in ipairs(slots) do
    local cur = worn(slot)
    if cur and (cur == link or cur:match("item:(%d+)") == id) then
      local pair
      local o = PAIRED[slot] and worn(PAIRED[slot])
      if o and (f.equipLoc == "INVTYPE_FINGER" or f.equipLoc == "INVTYPE_TRINKET") then
        local a, b = S.ValueIn(cur, slot) or 0, S.ValueIn(o, PAIRED[slot]) or 0
        pair = (math.abs(a - b) < 0.01) and "equal" or (a < b and "weaker" or "stronger")
      end
      return { kind = "equipped", pair = pair, equipLoc = f.equipLoc }
    end
  end
  local gain, vs, hand, partner, empty, parts, why, ench = GainOf(link, f)
  if hand == "twohand" then return { kind = "twohand" } end
  if not gain then return nil end
  -- your best owned item counts, not only what you wear: a better one of its kind in your bags is the
  -- one to beat (an item in your bags itself is measured against what you wear, unless another beats it)
  local bagBest, bagLink = 0, nil
  local carried = false
  for _, b in ipairs(BagItems()) do if b[1]:match("item:(%d+)") == id then carried = true end end
  for _, b in ipairs(BagItems()) do
    if Family(b[2]) == Family(f.equipLoc) and b[1]:match("item:(%d+)") ~= id then
      local bf = S.Facts(b[1])
      if bf and bf.usable then
        local g = S.BagGain(b[1], function() return (GainOf(b[1], bf)) end)
        if g and g > bagBest and (not carried or g > gain) then bagBest, bagLink = g, b[1] end
      end
    end
  end
  local pct = gain - bagBest
  -- effects it doesn't count (procs when you're hit, on kills)
  local unread
  for _, e in ipairs(f.effects or {}) do if e.kind == "note" then unread = e.why end end
  if bagLink then vs, hand, empty, partner, ench = bagLink, nil, false, nil, nil end
  if empty and pct > 0 then return { kind = "new", pct = pct, parts = parts, why = why, enchant = ench, unread = unread } end
  local kind = (math.abs(pct) < 0.1) and "same" or (pct > 0 and "upgrade" or "downgrade")
  return { kind = kind, pct = pct, vs = vs, inBags = bagLink ~= nil, hand = hand, partner = partner,
    parts = (not bagLink) and parts or nil, why = why, enchant = ench, unread = unread }
end
