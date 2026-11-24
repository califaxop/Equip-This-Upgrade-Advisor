-- Reading an item's stats and scoring it against what you wear.
local _, ns = ...
local S = {}
ns.Score = S
local Readable = ns.Readable

-- the game's stat keys -> ours
local KEYS = {
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

-- Enchants (Spells.lua: ns.ENCHANTS, from Forever's tables). An item is read without its enchant, then
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
-- (with its permanent enchant; temporary ones: S.FactsWithTemp)
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

-- A weapon's temporary enchant (a shaman imbue, a poison, a stone, an oil): the enchant ID, or nil.
-- On you: the game says (GetWeaponEnchantInfo); in your bags: its tooltip's line ("Rockbiter 5 (59 min)").
local tempByName
local function TempByName(name)
  if not tempByName then
    tempByName = {}
    for id, e in pairs(ns.ENCHANTS or {}) do if e[2] then tempByName[e[1]] = id end end
  end
  return tempByName[name]
end
local tempCache = {}
function S.ForgetTemp() wipe(tempCache) end
function S.TempEnchant(link)
  if type(link) ~= "string" then return nil end
  local c = tempCache[link]
  if c ~= nil then return c or nil end
  local id
  local worn = { [16] = 1, [17] = 2 }
  for slot, n in pairs(worn) do
    local l = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if l == link and GetWeaponEnchantInfo then
      local r = { pcall(GetWeaponEnchantInfo) }
      local has, ench = r[n == 1 and 2 or 6], r[n == 1 and 5 or 9]
      if r[1] and Readable(has) and has and Readable(ench) then id = ench end
    end
  end
  if not id and C_TooltipInfo and C_TooltipInfo.GetBagItem then
    for _, b in ipairs(S.BagList()) do
      if b[1] == link then
        local ok, data = pcall(C_TooltipInfo.GetBagItem, b[3], b[4])
        for _, l in ipairs(ok and type(data) == "table" and data.lines or {}) do
          local t = Readable(l.leftText) and l.leftText or ""
          local name = t:match("^(.-) %(%d+ %a+%)$")
          if name then
            id = TempByName(name)
            if id then break end
          end
        end
        break
      end
    end
  end
  tempCache[link] = id or false
  return id
end
function S.ClearCache() wipe(cache); S.ForgetCompared(); if S.ForgetBags then S.ForgetBags() end; if ns.Sim then ns.Sim.Forget() end; if ns.Effects then ns.Effects.ClearCache() end; end

local WEAPON_LOCS = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- an item's score for a spec (weights): its stats times their weights; DPS only on weapons
function S.Value(link, weights)
  local f = S.Facts(link)
  if not f then return nil end
  local total = 0
  for k, v in pairs(f.stats) do
    -- weights are importance 0-5; ns.PointsPer turns them into points per unit of the stat
    if k ~= "DPS" or WEAPON_LOCS[f.equipLoc] then total = total + v * ns.PointsPer(k, weights[k]) end
  end
  -- procs, Use effects, "+X% to a spell": what they add for this spec (0 if it can't use them)
  if ns.Effects then total = total + (ns.Effects.Points(f, weights) or 0) end
  return total, f
end

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
function S.ForgetBags() bagItems = nil; S.ForgetCompared(); if S.ForgetTemp then S.ForgetTemp() end end
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
-- is this item yours (worn or in your bags)?
function S.Owned(link)
  if type(link) ~= "string" then return false end
  for slot = 1, 19 do
    if GetInventoryItemLink and GetInventoryItemLink("player", slot) == link then return true end
  end
  for _, b in ipairs(BagItems()) do if b[1] == link then return true end end
  return false
end
-- your bag items of a kind (not this item), as { { value, link } }: usable ones only
local function BagScores(loc, exceptId, weights)
  local out = {}
  for _, b in ipairs(BagItems()) do
    if Family(b[2]) == Family(loc) and b[1]:match("item:(%d+)") ~= exceptId then
      local v, bf = S.Value(b[1], weights)
      if v and bf and bf.usable then out[#out + 1] = { v, b[1] } end
    end
  end
  return out
end

-- With the DPS / HPS model: the % change from wearing an item, against your best owned one.
-- Weapons as setups: a two-hander replaces main hand + off hand; a one-hander replaces the main hand
-- (or, if you dual wield, whichever hand it does more in); rings and trinkets the one they beat most.
-- { kind, pct, delta, value (its gain), vs, inBags, hand = "oh", partner = off-hand link, model = true }
local RANGED_LOC = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local OFF_LOC = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
function S.ModelCompare(link, f, weights)
  local Sim = ns.Sim
  local s = Sim.Cached()
  local function worn(slot) return GetInventoryItemLink and GetInventoryItemLink("player", slot) end
  local function loc2(l) return C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(l)) end
  local function gainOf(l, lf)
    local loc = lf.equipLoc
    if loc == "INVTYPE_2HWEAPON" then
      local out, mh, oh = {}, worn(16), worn(17)
      if mh then out[#out + 1] = mh end
      if oh then out[#out + 1] = oh end
      return Sim.Gain(l, out, weights, "mh", s), mh or oh
    elseif loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then
      local mh = worn(16)
      if mh and loc2(mh) == "INVTYPE_2HWEAPON" then
        -- replacing your two-hander: with your best off-hand from your bags (a shield, a held item,
        -- or a second weapon if you dual wield), else on its own
        local best, partner = Sim.Gain(l, { mh }, weights, "mh", s), nil
        for _, b in ipairs(BagItems()) do
          local bl = b[1]
          if bl ~= l and (OFF_LOC[b[2]] or (b[2] == "INVTYPE_WEAPON" and DualWields())) then
            local bf = S.Facts(bl)
            if bf and bf.usable then
              local g = Sim.Gain(l, { mh }, weights, "mh", s, bl)
              if g and (not best or g > best) then best, partner = g, bl end
            end
          end
        end
        return best, mh, nil, nil, partner
      end
      local g, vs, hand = Sim.Gain(l, mh and { mh } or {}, weights, "mh", s), mh, nil
      if loc == "INVTYPE_WEAPON" and DualWields() and not (mh and loc2(mh) == "INVTYPE_2HWEAPON") then
        local oh = worn(17)
        local g2 = Sim.Gain(l, oh and { oh } or {}, weights, "oh", s)
        if g2 and (not g or g2 > g) then g, vs, hand = g2, oh, "oh" end
      end
      return g, vs, hand
    elseif OFF_LOC[loc] then
      local oh = worn(17)
      return Sim.Gain(l, oh and { oh } or {}, weights, "oh", s), oh
    elseif RANGED_LOC[loc] then
      local rw = worn(18)
      return Sim.Gain(l, rw and { rw } or {}, weights, "rw", s), rw
    end
    local best, vs, empty
    for _, slot in ipairs(SLOTS[loc] or {}) do
      local cur = worn(slot)
      local g = Sim.Gain(l, cur and { cur } or {}, weights, nil, s)
      if g and (not best or g > best) then best, vs, empty = g, cur, cur == nil end
    end
    return best, vs, nil, empty
  end
  local gain, vs, hand, empty, partner = gainOf(link, f)
  if not gain then return nil end
  if vs == nil then empty = true end
  -- your best owned item of the kind: one in your bags that does more is the one to beat
  -- (an item in your bags itself is measured against what you wear, unless another beats it)
  local id = link:match("item:(%d+)")
  local carried = false
  for _, b in ipairs(BagItems()) do if b[1]:match("item:(%d+)") == id then carried = true end end
  local bagBest, bagLink = 0, nil
  for _, b in ipairs(BagItems()) do
    if Family(b[2]) == Family(f.equipLoc) and b[1]:match("item:(%d+)") ~= id then
      local bf = S.Facts(b[1])
      if bf and bf.usable then
        local g = S.BagGain(b[1], function() return (gainOf(b[1], bf)) end)
        if g and g > bagBest and (not carried or g > gain) then bagBest, bagLink = g, b[1] end
      end
    end
  end
  local pct = gain - bagBest
  if bagLink then vs, hand, empty, partner = bagLink, nil, false, nil end
  if empty and pct > 0 then return { kind = "new", pct = pct, delta = pct, value = gain, model = true } end
  local kind = (math.abs(pct) < 0.1) and "same" or (pct > 0 and "upgrade" or "downgrade")
  return { kind = kind, pct = pct, delta = pct, value = gain, vs = vs, inBags = bagLink ~= nil, hand = hand, partner = partner, model = true }
end

-- An off-hand while you wear a two-hander: the pair it makes with your best one-hander from your bags
-- (main hand), against the two-hander. Nil when you carry no one-hander.
function S.PairOffHand(link, f, weights, mh)
  local Sim = ns.Sim
  local s = Sim.Cached()
  local best, partner
  for _, b in ipairs(BagItems()) do
    if (b[2] == "INVTYPE_WEAPON" or b[2] == "INVTYPE_WEAPONMAINHAND") and b[1] ~= link then
      local bf = S.Facts(b[1])
      if bf and bf.usable then
        local g = Sim.Gain(b[1], { mh }, weights, "mh", s, link)
        if g and (not best or g > best) then best, partner = g, b[1] end
      end
    end
  end
  if not best then return nil end
  local kind = (math.abs(best) < 0.1) and "same" or (best > 0 and "upgrade" or "downgrade")
  return { kind = kind, pct = best, delta = best, value = best, vs = mh, partner = partner, model = true }
end

-- Your whole gear's score: every slot you wear (not shirt or tabard). Upgrades are measured against it,
-- so a % means the same in every slot ("+2%": 2% stronger overall), however weak the item you'd replace.
function S.GearTotal(weights)
  local total = 0
  for slot = 1, 18 do
    if slot ~= 4 then
      local l = GetInventoryItemLink and GetInventoryItemLink("player", slot)
      if l then total = total + (S.Value(l, weights) or 0) end
    end
  end
  return total
end

-- How an item compares with what you wear, for a spec:
-- { kind = "upgrade" | "downgrade" | "same" | "new" | "unusable" | "equipped", pct (of your whole gear), delta, value,
--   vs = link (your best owned item it'd replace: worn, or in your bags with inBags = true),
--   pair = "weaker" | "stronger" | "equal" (equipped rings / trinkets, when you wear two) }
-- or nil (not gear, or not loaded yet)
-- (kept until something changes: your gear, bags, level, talents or settings; hovering an item
-- refreshes its tooltip several times a second, and the DPS model is too much work for that)
local compared, bagGains = {}, {}
-- a bag item's own gain (the same whichever item is hovered): kept with the comparisons
function S.BagGain(link, fn)
  local g = bagGains[link]
  if g == nil then g = fn() or false; bagGains[link] = g end
  return g or nil
end
function S.Compare(link, weights)
  if weights then return S.CompareWeights(link, weights) end
  local c = compared[link]
  if c == nil then
    c = S.CompareWeights(link, ns.Weights()) or false
    -- (kept only when it's final: not "not loaded yet", and not the weights standing in for the
    -- DPS model when the model should have answered; those are asked again next time)
    local fallback = c and not c.model and ns.Sim and ns.Sim.Active()
      and (c.kind == "upgrade" or c.kind == "downgrade" or c.kind == "same" or c.kind == "new")
    if c and not fallback then compared[link] = c end
  end
  return c or nil
end
function S.ForgetCompared() wipe(compared); wipe(bagGains) end

function S.CompareWeights(link, weights)
  weights = weights or ns.Weights()
  local value, f = S.Value(link, weights)
  if not value then return nil end
  local slots = SLOTS[f.equipLoc]
  if not slots then return nil end
  if not f.usable then return { kind = "unusable", value = value } end
  -- (optional) from level 40, armor below your best type isn't an upgrade
  local best = S.LowerArmor(link, f.equipLoc)
  if best then return { kind = "armortype", value = value, best = best } end
  -- the item you'd swap out, and its score
  local oldValue, vs, wearing = nil, nil, false
  local function worn(slot) return GetInventoryItemLink and GetInventoryItemLink("player", slot) end
  if f.equipLoc == "INVTYPE_2HWEAPON" then
    -- a two-hander replaces main hand + off hand
    local mh, oh = worn(16), worn(17)
    if mh and (mh == link or mh:match("item:(%d+)") == link:match("item:(%d+)")) then wearing = 16 end
    if mh or oh then
      oldValue = (mh and S.Value(mh, weights) or 0) + (oh and S.Value(oh, weights) or 0); vs = mh or oh
    end
  else
    local list = slots
    -- wearing a two-hander: the off hand isn't free. Off-hand items can't go with it; a
    -- one-hander would have to replace the two-hander
    local mh = worn(16)
    local mhLoc = mh and C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(mh))
    if mhLoc == "INVTYPE_2HWEAPON" then
      if f.equipLoc == "INVTYPE_SHIELD" or f.equipLoc == "INVTYPE_HOLDABLE" or f.equipLoc == "INVTYPE_WEAPONOFFHAND" then
        -- with the DPS model: paired with your best one-hander from your bags, against your two-hander
        if ns.Sim and ns.Sim.Active() then
          local ok, r = pcall(S.PairOffHand, link, f, weights, mh)
          if ok and r then return r end
        end
        return { kind = "twohand", value = value }
      end
      if f.equipLoc == "INVTYPE_WEAPON" then list = { 16 } end
    end
    if f.equipLoc == "INVTYPE_WEAPON" and not DualWields() then list = { 16 } end
    local id = link:match("item:(%d+)")
    for _, slot in ipairs(list) do
      local cur = worn(slot)
      if cur and (cur == link or cur:match("item:(%d+)") == id) then wearing = slot end
    end
    for _, slot in ipairs(list) do
      local cur = worn(slot)
      local v = cur and S.Value(cur, weights) or 0
      if not cur then oldValue, vs = 0, nil; break end -- an empty slot: it's an upgrade
      if oldValue == nil or v < oldValue then oldValue, vs = v, cur end -- the weaker ring / trinket
    end
  end
  -- your DPS / HPS, worked out from your spells (Sim.lua): the change from wearing it
  if not wearing and ns.Sim and ns.Sim.Active() then
    local ok, r = pcall(S.ModelCompare, link, f, weights)
    if ok and r then return r end
    S.modelError = ok and "no result (your numbers aren't readable yet?)" or tostring(r) -- (shown by /eqt item)
  end
  -- Your best owned item counts, not only what you wear: a better one in your bags is the one to beat
  -- (so an item that's worse than one you already carry isn't called an upgrade).
  local inBags = false
  if not wearing and oldValue then
    local id = link:match("item:(%d+)")
    local pair = f.equipLoc == "INVTYPE_FINGER" or f.equipLoc == "INVTYPE_TRINKET"
    local dualSlots = f.equipLoc == "INVTYPE_WEAPON" and #slots == 2 and DualWields()
    if pair then
      -- rings, trinkets: your best two (worn or in bags); a new one replaces the weaker of them
      local owned = {}
      for _, slot in ipairs(slots) do
        local cur = worn(slot)
        if cur then owned[#owned + 1] = { S.Value(cur, weights) or 0, cur, true } end
      end
      for _, b in ipairs(BagScores(f.equipLoc, id, weights)) do owned[#owned + 1] = { b[1], b[2], false } end
      table.sort(owned, function(a, b) return a[1] > b[1] end)
      if #owned >= 2 then oldValue, vs, inBags = owned[2][1], owned[2][2], not owned[2][3]
      else oldValue, vs = 0, nil end
    elseif not dualSlots and oldValue > 0 then
      -- one slot (or a two-hander against main hand + off hand): your best of its kind in your bags.
      -- An item that's in your bags itself is measured against what you wear ("equip it"), unless
      -- something else you carry beats it.
      local carried = false
      for _, b in ipairs(BagItems()) do if b[1]:match("item:(%d+)") == id then carried = true end end
      for _, b in ipairs(BagScores(f.equipLoc, id, weights)) do
        if b[1] > oldValue and (not carried or b[1] > value) then oldValue, vs, inBags = b[1], b[2], true end
      end
    end
  end
  if wearing then
    -- a ring or trinket you wear: is it the weaker of your two (the one a new one replaces)?
    local pair
    local other = PAIRED[wearing]
    if other and (f.equipLoc == "INVTYPE_FINGER" or f.equipLoc == "INVTYPE_TRINKET") then
      local o = worn(other)
      local mine = worn(wearing)
      if o and mine then
        local a, b = S.Value(mine, weights) or 0, S.Value(o, weights) or 0
        pair = (math.abs(a - b) < 0.01) and "equal" or (a < b and "weaker" or "stronger")
      end
    end
    return { kind = "equipped", value = value, pair = pair, equipLoc = f.equipLoc }
  end
  local total = math.max(S.GearTotal(weights), 1)
  if not oldValue or oldValue <= 0 then return { kind = "new", value = value, delta = value, pct = value / total * 100 } end
  local delta = value - oldValue
  local pct = delta / total * 100
  local kind = (math.abs(pct) < 0.1) and "same" or (delta > 0 and "upgrade" or "downgrade")
  return { kind = kind, pct = pct, delta = delta, value = value, vs = vs, inBags = inBags }
end
