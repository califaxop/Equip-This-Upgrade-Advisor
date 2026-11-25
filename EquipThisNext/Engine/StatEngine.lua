-- StatEngine: the character as numbers the models use (a "state"), and how a change of gear moves
-- them. Pure Lua.
--
-- The state starts from the character sheet (the game's own numbers, buffs included). A gear change
-- is applied as a difference: the stats it adds or removes, through the game's own conversions
-- measured on this character (attack power per Strength, crit per Agility, % per rating point...)
-- and the talent conversions (Mental Dexterity: Intellect -> attack power). Nothing is assumed where
-- the game gives the number; where it doesn't (missing data), a Classic constant is used and the
-- state's `assumed` list says so.
local _, ns = ...
local SE = ns and ns.Module and ns.Module("StatEngine") or {}

-- Blizzard's Forever paper doll constants (Camelot/PaperDollFrameStats.lua)
SE.ARMOR_PER_AGILITY = 2
SE.BLOCK_VALUE_PER_STRENGTH = 20
SE.AP_PER_DPS = 14            -- ATTACK_POWER_MAGIC_NUMBER

local function v(p, key) return p.stats and p.stats.values and p.stats.values[key] end

-- Sum of the worn gear's stats (engine names)
function SE.GearTotals(profile)
  local total, unknown = {}, {}
  for _, it in pairs(profile.equipment and profile.equipment.slots or {}) do
    if it.loaded and it.stats then
      local s, u = ns.StatDefs.Normalize(it.stats)
      total = ns.StatDefs.Add(total, s)
      for _, k in ipairs(u) do unknown[k] = true end
    end
  end
  return total, unknown
end

-- % per rating point for a rating (CR_ name): the game's calculator, else the sheet's ratio, else nil
local function ratingPct(profile, cr)
  local c = profile.calc and profile.calc.ratingPct and profile.calc.ratingPct[cr]
  if c then return c, "game" end
  local r, b = v(profile, "rating." .. cr), v(profile, "ratingBonus." .. cr)
  if r and b and r > 0 then return b / r, "sheet" end
  return nil
end

-- The state from the sheet. Returns state, or nil and why.
function SE.Baseline(profile)
  local val = profile.stats and profile.stats.values
  if not val or not next(val) then return nil, "no character sheet read yet" end
  local s = { level = profile.identity.level, class = profile.identity.class, assumed = {}, slope = {}, rating = {} }
  for _, k in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do s[k] = v(profile, "stat." .. k .. ".effective") or 0 end
  s.AP = (v(profile, "ap.base") or 0) + (v(profile, "ap.pos") or 0) - (v(profile, "ap.neg") or 0)
  s.crit = v(profile, "crit.melee") or 0
  s.spellCrit = v(profile, "critSpell.spell") or 0
  s.hit = (v(profile, "hit.melee") or 0) + (v(profile, "ratingBonus.CR_HIT_MELEE") or 0)
  s.spellHit = (v(profile, "hitSpell.spell") or 0) + (v(profile, "ratingBonus.CR_HIT_SPELL") or 0)
  s.haste = v(profile, "hasteMelee.melee") or 0
  s.expertise = v(profile, "expertise.mainHand") or 0
  s.SP = v(profile, "spellDamage.NATURE") or 0
  for _, sch in ipairs({ "FIRE", "FROST", "SHADOW", "ARCANE", "HOLY" }) do s.SP = math.max(s.SP, v(profile, "spellDamage." .. sch) or 0) end
  s.HEAL = v(profile, "healing.bonus") or 0
  s.health = v(profile, "health.max") or 0
  s.armor = v(profile, "armor.effective") or 0
  s.defense = (v(profile, "defense.base") or 0) + (v(profile, "defense.modifier") or 0)
  s.dodge, s.parry, s.block = v(profile, "dodge.chance") or 0, v(profile, "parry.chance") or 0, v(profile, "block.chance") or 0
  s.blockValue = v(profile, "blockValue.value") or 0
  s.res = {}
  for _, sch in ipairs({ "HOLY", "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE" }) do s.res["RES_" .. sch] = v(profile, "resist." .. sch .. ".effective") or 0 end
  s.mp5 = v(profile, "regen.casting") -- (mana per second while casting, as the sheet gives it)
  -- main hand: the sheet's average swing (weapon + attack power + flat bonuses) and speed
  local mn, mx, sp = v(profile, "melee.min"), v(profile, "melee.max"), v(profile, "speed.mainHand")
  if mn and mx and sp and sp > 0 then s.swing, s.speed = (mn + mx) / 2, sp end
  local ws = profile.stats.weaponSkills and profile.stats.weaponSkills[16]
  s.weaponSkill = ws and ws.rank and (ws.rank + (ws.modifier or 0)) or (s.level * 5)
  if not (ws and ws.rank) then s.assumed[#s.assumed + 1] = "weapon skill = 5 x level" end
  -- the game's conversions, per point, measured on this character
  local function per(key, stat)
    local x, n = v(profile, key), s[stat]
    if x and n and n > 0 then return x / n end
  end
  s.slope.apPerSTR = per("apFromStat.STR", "STR") or 0
  s.slope.apPerAGI = per("apFromStat.AGI", "AGI") or 0
  s.slope.critPerAGI = (per("critFromStat.AGI", "AGI") or 0) * 100       -- (the game gives a fraction)
  s.slope.spellCritPerINT = (per("spellCritFromStat.INT", "INT") or 0) * 100
  s.slope.dodgePerAGI = (per("dodgeFromAgi.chance", "AGI") or 0) * 100
  s.slope.hpPerSTA = v(profile, "hpPerStamina.value") or 10
  if not v(profile, "hpPerStamina.value") then s.assumed[#s.assumed + 1] = "10 health per Stamina" end
  -- % per rating point
  for _, list in pairs(ns.StatDefs.RATINGS) do
    for _, cr in ipairs(list) do
      if s.rating[cr] == nil then
        local r = ratingPct(profile, cr)
        s.rating[cr] = r or false
      end
    end
  end
  return s
end

local function rate(state, cr, points)
  if not points or points == 0 then return 0 end
  local r = state.rating[cr]
  if not r then
    state.missingRating = state.missingRating or {}
    state.missingRating[cr] = true
    return 0
  end
  return points * r
end

-- A copy of state with a gear difference applied (delta: engine stats, + gained / - lost).
-- talents: TalentInterpreter output (conversions). Returns the new state.
function SE.Apply(state, delta, talents)
  local d = {}
  for k, x in pairs(delta or {}) do d[k] = x end
  -- talent conversions (from the stat as the item gives it)
  for _, c in ipairs(talents and talents.conversions or {}) do
    if d[c.from] and d[c.from] ~= 0 then d[c.to] = (d[c.to] or 0) + d[c.from] * c.pct end
  end
  local s = {}
  for k, x in pairs(state) do s[k] = x end
  s.res = {}
  for k, x in pairs(state.res or {}) do s.res[k] = x + (d[k] or 0) end
  local g = function(k) return d[k] or 0 end
  for _, k in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do s[k] = state[k] + g(k) end
  local dAP = g("AP") + g("STR") * state.slope.apPerSTR + g("AGI") * state.slope.apPerAGI
  s.AP = state.AP + dAP
  s.crit = state.crit + g("AGI") * state.slope.critPerAGI + rate(s, "CR_CRIT_MELEE", g("CRIT_RATING") + g("CRIT_MELEE_RATING"))
  s.spellCrit = state.spellCrit + g("INT") * state.slope.spellCritPerINT + rate(s, "CR_CRIT_SPELL", g("CRIT_RATING") + g("CRIT_SPELL_RATING"))
  s.hit = state.hit + rate(s, "CR_HIT_MELEE", g("HIT_RATING") + g("HIT_MELEE_RATING"))
  s.spellHit = state.spellHit + rate(s, "CR_HIT_SPELL", g("HIT_RATING") + g("HIT_SPELL_RATING"))
  s.haste = state.haste + rate(s, "CR_HASTE_MELEE", g("HASTE_RATING") + g("HASTE_MELEE_RATING"))
  s.expertise = state.expertise + rate(s, "CR_EXPERTISE", g("EXPERTISE_RATING"))
  s.SP = state.SP + g("SP")
  s.HEAL = state.HEAL + g("HEAL")
  s.health = state.health + g("STA") * state.slope.hpPerSTA + g("HEALTH")
  s.armor = state.armor + g("ARMOR") + g("AGI") * SE.ARMOR_PER_AGILITY
  s.defense = state.defense + rate(s, "CR_DEFENSE_SKILL", g("DEFENSE_RATING"))
  local dDef = s.defense - state.defense
  s.dodge = state.dodge + g("AGI") * state.slope.dodgePerAGI + rate(s, "CR_DODGE", g("DODGE_RATING")) + dDef * 0.04
  s.parry = state.parry + rate(s, "CR_PARRY", g("PARRY_RATING")) + (state.parry > 0 and dDef * 0.04 or 0)
  s.block = state.block + rate(s, "CR_BLOCK", g("BLOCK_RATING")) + (state.block > 0 and dDef * 0.04 or 0)
  s.blockValue = state.blockValue + g("BLOCK_VALUE") + g("STR") / SE.BLOCK_VALUE_PER_STRENGTH
  if state.swing and state.speed then
    s.swing = state.swing + dAP / SE.AP_PER_DPS * state.speed + g("WEAPON_DMG") + g("WEAPON_DPS") * state.speed
  end
  return s
end
