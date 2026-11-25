-- StatScanner: the character sheet into profile.stats. Keys are "<read>.<return>", e.g.
-- "crit.melee", "armor.effective", "stat.AGI.effective", "spellDamage.FIRE", "resist.FROST",
-- "rating.CR_HIT_MELEE", "ratingBonus.CR_HIT_MELEE", "critFromStat.AGI".
-- A value the game hides is listed in stats.hidden; an API that's missing or errored in stats.missing.
-- While the game hides stats altogether (stats restricted), nothing is read and the last readable
-- set is reused (marked stale).
local _, ns = ...
local StatScanner = ns.Module("StatScanner")
local Compat, Char = ns.Compat, ns.CharacterAPI

local function put(stats, key, v, why)
  if v == Compat.SECRET then stats.hidden[key] = true
  elseif type(v) == "number" then stats.values[key] = v
  elseif type(v) == "string" then stats.text[key] = v   -- (e.g. the power token "MANA")
  elseif type(v) == "boolean" then stats.values[key] = v and 1 or 0
  elseif why and why ~= "nil" then stats.missing[key] = why end   -- (nil: an optional return, e.g. no off-hand)
end

local function read(stats, key, api, args, names)
  local r = ns.pack(Compat.Call(api, unpack(args)))
  if not r[1] then
    for _, n in ipairs(names) do if n then stats.missing[key .. "." .. n] = r[2] end end
    return
  end
  for i, n in ipairs(names) do
    if n then put(stats, key .. "." .. n, r[i + 1], "nil") end
  end
end

-- Blizzard's paper doll: weapon subclass -> weapon skill line (Camelot/PaperDollFrameStats.lua)
local function weaponSkillMap()
  local W = Enum and Enum.ItemWeaponSubclass
  if not W then return {} end
  return {
    [W.Sword1H] = 43, [W.Axe1H] = 44, [W.Bows] = 45, [W.Guns] = 46, [W.Mace1H] = 54, [W.Sword2H] = 55,
    [W.Staff] = 136, [W.Mace2H] = 160, [W.Axe2H] = 172, [W.Dagger] = 173, [W.Thrown] = 176,
    [W.Crossbow] = 226, [W.Wand] = 228, [W.Polearm] = 229, [W.Unarmed] = 162,
  }
end

local last -- the last readable set (reused while stats are restricted)

function StatScanner.Scan(profile)
  if Char.StatsRestricted() then
    if last then
      profile.stats = ns.Database.Copy(last)
      profile.stats.stale = true
    end
    profile.stats.restricted = true
    ns.CharacterProfile.AddIssue(profile, "warn", "stats-hidden",
      "the game hides stats right now (combat?): " .. (last and "showing the last readable ones" or "none read yet"))
    return profile.stats
  end
  local stats = { values = {}, text = {}, hidden = {}, missing = {}, weaponSkills = {}, takenAt = time and time() or 0 }
  for _, r in ipairs(Char.READS) do read(stats, r[1], r[2], r[3], r[4]) end
  for i, s in ipairs(Char.STATS) do
    read(stats, "stat." .. s, "UnitStat", { "player", i }, { "base", "effective", "pos", "neg" })
    local eff = stats.values["stat." .. s .. ".effective"]
    if eff then
      for _, c in ipairs(Char.STAT_CONVERSIONS) do
        local ok, v = Compat.Call(c[2], i, eff)
        if ok then put(stats, c[1] .. "." .. s, v, "nil") else stats.missing[c[1] .. "." .. s] = v end
      end
    end
  end
  for i, school in ipairs(Char.SCHOOLS) do
    local ok, v = Compat.Call("GetSpellBonusDamage", i + 1)
    if ok then put(stats, "spellDamage." .. school, v, "nil") else stats.missing["spellDamage." .. school] = v end
    read(stats, "resist." .. school, "UnitResistance", { "player", i }, { "base", "effective", false, "bonus" })
  end
  for _, name in ipairs(Char.RATINGS) do
    local idx = Char.RatingIndex(name)
    if idx then
      local ok, v = Compat.Call("GetCombatRating", idx)
      if ok then put(stats, "rating." .. name, v, "nil") end
      ok, v = Compat.Call("GetCombatRatingBonus", idx)
      if ok then put(stats, "ratingBonus." .. name, v, "nil") end
    else
      stats.missing["rating." .. name] = "no " .. name .. " constant"
    end
  end
  -- weapon skill of each weapon worn
  local map = weaponSkillMap()
  for _, slot in ipairs({ 16, 17, 18 }) do
    local id = ns.EquipmentAPI.ItemID(slot)
    local inst = id and ns.ItemAPI.Instant(id)
    if inst and inst.classID == 2 then
      local skillID = map[inst.subclassID]
      local line = skillID and Char.SkillLine(skillID)
      stats.weaponSkills[slot] = { skillLineID = skillID, name = line and line.name, rank = line and line.rank,
        modifier = line and line.modifier, maxRank = line and line.maxRank }
    end
  end
  profile.stats = stats
  last = ns.Database.Copy(stats)
  return stats
end

function StatScanner.Forget() last = nil end
