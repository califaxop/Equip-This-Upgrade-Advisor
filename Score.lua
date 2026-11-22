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
  { "spell critical strike chance by " .. N .. "%%", "SPELLCRIT" },
  { "spell crit chance by " .. N .. "%%", "SPELLCRIT" },
  { "hit with spells by " .. N .. "%%", "SPELLHIT" },
  { "spell hit chance by " .. N .. "%%", "SPELLHIT" },
  -- melee / ranged
  { "critical strike by " .. N .. "%%", "CRIT" },
  { "critical strike chance by " .. N .. "%%", "CRIT" },
  { "crit chance by " .. N .. "%%", "CRIT" },
  { "chance to crit by " .. N .. "%%", "CRIT" },
  { "chance to hit by " .. N .. "%%", "HIT" },
  { "hit chance by " .. N .. "%%", "HIT" },
  -- spell damage and healing (a school's spell damage counts as spell damage)
  { "damage and healing done by magical spells and effects by up to (%d+)", "SP" },
  { "spell damage and healing by up to (%d+)", "SP" },
  { "damage done by %a+ spells and effects by up to (%d+)", "SP" },
  { "spell damage by up to (%d+)", "SP" },
  { "%+(%d+) [Ss]pell [Dd]amage", "SP" },
  { "%+(%d+) [Ss]pell [Pp]ower", "SP" },
  { "healing done by spells and effects by up to (%d+)", "HEAL" },
  { "healing by up to (%d+)", "HEAL" },
  { "%+(%d+) [Hh]ealing", "HEAL" },
  -- mana
  { "[Rr]estores (%d+) mana per 5 sec", "MP5" },
  { "(%d+) mana every 5 sec", "MP5" },
  -- attack power (ranged first)
  { "%+(%d+) [Rr]anged [Aa]ttack [Pp]ower", "RAP" },
  { "[Ii]ncreases ranged attack power by (%d+)", "RAP" },
  { "%+(%d+) [Aa]ttack [Pp]ower", "AP" },
  { "[Ii]ncreases [Aa]ttack [Pp]ower by (%d+)", "AP" },
  -- tanking
  { "dodge an attack by " .. N .. "%%", "DODGE" },
  { "parry an attack by " .. N .. "%%", "PARRY" },
  { "block attacks with a shield by " .. N .. "%%", "BLOCK" },
  { "block value of your shield by (%d+)", "BLOCKVALUE" },
  { "[Ii]ncreased [Dd]efense %+(%d+)", "DEF" },
  { "[Dd]efense by (%d+)", "DEF" },
}
-- bonuses only against some enemies don't count as the stat all the time
local SITUATIONAL = { "when fighting", "against undead", "against demons", "against beasts" }

local function IsRed(c)
  return type(c) == "table" and Readable(c.r) and c.r > 0.9 and c.g < 0.3 and c.b < 0.3
end

-- what the item tooltip says: Equip-line stats, and whether something on it is red
-- (can't use it: armor type, weapon skill, class, level)
-- (also: every line's text, for the effects, and the weapon's speed)
local function TooltipFacts(link)
  local extra, red, texts, speed = {}, false, {}, nil
  if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return extra, red, texts end
  local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
  if not (ok and type(data) == "table" and type(data.lines) == "table") then return extra, red, texts end
  for i, l in ipairs(data.lines) do
    if i > 1 and (IsRed(l.leftColor) or IsRed(l.rightColor)) then red = true end
    local t = Readable(l.leftText) and l.leftText or ""
    texts[#texts + 1] = t
    local r = Readable(l.rightText) and l.rightText or ""
    speed = speed or tonumber(r:match("^Speed (%d+%.?%d*)") or t:match("Speed (%d+%.?%d*)") or "")
    local perSpell = t:find(" chance of ") or t:find(" chance with ") -- "crit chance of Lightning Bolt": an effect
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
  return extra, red, texts, speed
end

local cache = {}
-- { stats = { STR = 5, ... }, equipLoc = "INVTYPE_...", usable = bool, sell = copper } or nil (not loaded yet)
function S.Facts(link)
  if type(link) ~= "string" then return nil end
  if cache[link] then return cache[link] end
  local equipLoc = C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(link))
  if not equipLoc or equipLoc == "" then return nil end
  local stats = {}
  local raw = C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link) or (GetItemStats and GetItemStats(link))
  if type(raw) ~= "table" then return nil end -- not loaded yet
  for k, v in pairs(raw) do
    local key = KEYS[k]
    if key and type(v) == "number" then stats[key] = (stats[key] or 0) + v end
  end
  local extra, red, texts, speed = TooltipFacts(link)
  for k, v in pairs(extra) do if not stats[k] then stats[k] = v end end
  local sell = select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(link))
  local f = { stats = stats, equipLoc = equipLoc, usable = not red, sell = type(sell) == "number" and sell or 0,
    speed = speed, effects = ns.Effects and ns.Effects.Parse(texts) or {} }
  cache[link] = f
  return f
end
function S.ClearCache() wipe(cache); if ns.Effects then ns.Effects.ClearCache() end end

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

-- How an item compares with what you wear, for a spec:
-- { kind = "upgrade" | "downgrade" | "same" | "new" | "unusable" | "equipped", pct, delta, value, vs = link,
--   pair = "weaker" | "stronger" | "equal" (equipped rings / trinkets, when you wear two) }
-- or nil (not gear, or not loaded yet)
function S.Compare(link, weights)
  weights = weights or ns.Weights()
  local value, f = S.Value(link, weights)
  if not value then return nil end
  local slots = SLOTS[f.equipLoc]
  if not slots then return nil end
  if not f.usable then return { kind = "unusable", value = value } end
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
  if not oldValue or oldValue <= 0 then return { kind = "new", value = value, delta = value } end
  local delta = value - oldValue
  local pct = delta / oldValue * 100
  local kind = (math.abs(pct) < 1) and "same" or (delta > 0 and "upgrade" or "downgrade")
  return { kind = kind, pct = pct, delta = delta, value = value, vs = vs }
end
