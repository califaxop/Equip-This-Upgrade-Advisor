-- Survival model (milestone 2): effective health (EHP) = health / the share of an enemy's raw damage
-- you actually take. Pure Lua.
--
-- Melee, Forever's own rules (Blizzard's Camelot paper doll): an attacker's weapon skill is 5 x its
-- level; per point above your defense skill it has 0.04 % less chance to miss you (5 % base) and
-- 0.04 % more to crit (5 % base, double damage); with 15+ points it can crush (2 % per point - 15,
-- +50 % damage). Your dodge, parry and block (from the sheet) shrink by 0.04 % per point too. Armor:
-- reduction = armor / (armor + K), K measured from the game's own C_PaperDollInfo.GetArmorEffectiveness
-- for that attacker level. A block takes your block value off the hit.
-- Spells: a share of the damage that comes at you is magic, cut only by resistance (on average
-- 75 % x resistance / (5 x attacker level), at most 75 %, Classic). While leveling 20 %, split evenly;
-- a choice of raids at the level cap comes later (the released Equip This! has the measured mixes).
local _, ns = ...
local S = ns and ns.Module and ns.Module("SurvivalModel") or {}

S.MAGIC_SHARE = 0.20
S.SCHOOLS = { "RES_FIRE", "RES_FROST", "RES_NATURE", "RES_SHADOW", "RES_ARCANE" }

-- K for an attacker level: from the game's armor effectiveness measured at the current armor, or the
-- Classic formula (assumed).
function S.ArmorK(ctx, attackerLevel, armor)
  local e = ctx.armorEffect and ctx.armorEffect[attackerLevel]
  if e and e > 0 and e < 1 and armor and armor > 0 then return armor * (1 - e) / e, false end
  if attackerLevel > 59 then return 467.5 * attackerLevel - 22167.5, true end
  return 400 + 85 * attackerLevel, true
end

-- ctx: { offset, armorEffect = { [attackerLevel] = 0-1 at the baseline armor }, baselineArmor, swingRaw }
function S.EHP(state, ctx)
  if not (state.health and state.health > 0) then return nil, "no health on the sheet" end
  local off = math.max(0, math.min(3, ctx.offset or 0))
  local a = state.level + off
  local skillGap = a * 5 - (state.defense or state.level * 5)
  local adj = skillGap * 0.04
  local miss = math.max(0, 5 - adj)
  local dodge = math.max(0, (state.dodge or 0) - adj)
  local parry = math.max(0, (state.parry or 0) - adj)
  local block = math.max(0, (state.block or 0) - adj)
  local crit = math.max(0, 5 + adj)
  local crushGap = a * 5 - math.min(state.defense or 0, state.level * 5)
  local crush = crushGap >= 15 and math.max(0, crushGap * 2 - 15) or 0
  -- fill the table in order; later rows get what's left
  local left = 100
  local function take(x) local t = math.min(x, left); left = left - t; return t end
  miss, dodge, parry, block, crit, crush = take(miss), take(dodge), take(parry), take(block), take(crit), take(crush)
  local hit = left
  local K, assumedK = S.ArmorK(ctx, a, ctx.baselineArmor)
  local dr = (state.armor or 0) / ((state.armor or 0) + K)
  dr = math.min(dr, 0.75)
  local raw = ctx.swingRaw or (2 * a)          -- (an enemy's raw swing: about 2 x its level while leveling, assumed)
  local after = raw * (1 - dr)
  local blocked = math.max(0, after - (state.blockValue or 0)) / after
  local melee = ((hit + crit * 2 + crush * 1.5 + block * blocked) / 100) * (1 - dr)
  local spell = 0
  for _, k in ipairs(S.SCHOOLS) do
    local r = state.res and state.res[k] or 0
    spell = spell + (1 - math.min(0.75, 0.75 * math.max(0, r) / (5 * a))) / #S.SCHOOLS
  end
  local m = ctx.magicShare or S.MAGIC_SHARE
  local taken = (1 - m) * melee + m * spell
  return state.health / taken, { taken = taken, melee = melee, spell = spell, armorReduction = dr, assumedK = assumedK,
    table = { miss = miss, dodge = dodge, parry = parry, block = block, crit = crit, crush = crush, hit = hit } }
end
