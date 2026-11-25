-- Melee model: damage per second against a target of a given level. Pure Lua. Expected values
-- (no random simulation: every part here is a rate times an average).
--   milestone 2: auto attacks: your average swing (weapon + attack power + flat weapon damage, from
--     the sheet and moved by gear), the attack table, crits (double damage), glancing blows, haste,
--     Flurry, the off-hand.
--   milestone 4: weapon strikes used on cooldown (Stormstrike: no glancing, no dual-wield miss),
--     item bonuses to them ("Stormstrike +10%"), Windfury Weapon's extra attacks, item procs
--     (damage, extra attacks) per landed hit with the game's chance / procs a minute and internal
--     cooldown. Stat procs and use effects are averaged into stats by the Evaluator.
--   not yet: spells (shocks, Lightning Bolt), mana and rage limits, Flametongue / Frostbrand.
--
-- The attack table is Forever's own (Blizzard's Camelot UI code):
--   miss chance vs a target 0/1/2/3 levels above you: 5.0 / 5.2 / 5.4 / 9.0 %, minus your hit
--   the target's dodge: 5.0 / 5.5 / 6.0 / 6.5 %
--   weapon skill vs the target's defense (5 x its level): 0.04 % per point on hit, dodge and crit
--   glancing chance and damage penalty: the game's GetGlancingBlowChance / GetGlancingBlowPenalty
local _, ns = ...
local M = ns and ns.Module and ns.Module("MeleeModel") or {}
local function SE_AP_PER_DPS() return ns.StatEngine and ns.StatEngine.AP_PER_DPS or 14 end

M.MISS = { [0] = 5.0, 5.2, 5.4, 9.0 }
M.DUAL_WIELD_MISS = 19     -- (Classic: +19 % miss for both hands while dual wielding: assumed for Forever)
M.OFFHAND_DAMAGE = 0.5     -- (Classic: an off-hand hit does half damage)
M.DODGE = { [0] = 5.0, 5.5, 6.0, 6.5 }
M.CRIT_MULT = 2.0
M.SPELL_MISS = { [0] = 4, 5, 6, 17 }   -- (a proc's spell vs 0-3 levels above: Classic's table, assumed for Forever)

-- Special attacks (abilities): the same table without glancing blows or the dual-wield miss.
function M.Special(state, ctx, weaponSkill)
  local off = math.max(0, math.min(3, ctx.offset or 0))
  weaponSkill = weaponSkill or state.weaponSkill or state.level * 5
  local skill = ((state.level + off) * 5 - weaponSkill) * 0.04
  local miss = math.max(0, M.MISS[off] + skill - (state.hit or 0))
  local dodge = math.max(0, M.DODGE[off] + skill)
  local crit = math.min(math.max(0, (state.crit or 0) - skill), math.max(0, 100 - miss - dodge))
  return { miss = miss, dodge = dodge, crit = crit, hit = math.max(0, 100 - miss - dodge - crit) }
end

-- Procs a second from landed hits a second. rate: { chance = % per hit } or { ppm = procs a minute
-- (a per-hit chance of ppm x weapon speed / 60) }, icd = internal cooldown in seconds. With an
-- internal cooldown: lambda / (1 + lambda x icd) (the proc can't come back for icd seconds).
function M.ProcRate(rate, hitsPerSec, speed)
  if not rate then return 0 end
  local per
  if rate.ppm and rate.ppm > 0 then per = rate.ppm * (speed or 2) / 60 else per = (rate.chance or 0) / 100 end
  local lambda = (hitsPerSec or 0) * math.min(1, per)
  if rate.icd and rate.icd > 0 and lambda > 0 then lambda = lambda / (1 + lambda * rate.icd) end
  return lambda
end

-- landed hits a second for an effect on an item in `slot` (a weapon's own procs: its hand only)
function M.HitsFor(slot, landed)
  if slot == 16 then return landed.mh elseif slot == 17 then return landed.oh end
  return landed.mh + landed.oh
end

-- ctx: { offset = 0..3, glancing = { chance (0-1), penalty (0-1) } or nil, talents = TalentInterpreter output }
function M.Table(state, ctx, weaponSkill, dualWield)
  local off = math.max(0, math.min(3, ctx.offset or 0))
  weaponSkill = weaponSkill or state.weaponSkill or state.level * 5
  local diff = (state.level + off) * 5 - weaponSkill   -- target defense - your skill
  local skill = diff * 0.04
  local miss = math.max(0, M.MISS[off] + (dualWield and M.DUAL_WIELD_MISS or 0) + skill - (state.hit or 0))
  local dodge = math.max(0, M.DODGE[off] + skill)
  -- glancing: the game's numbers for this skill (or the main-hand's when that's all there is)
  local bySkill = ctx.glancingBySkill and ctx.glancingBySkill[weaponSkill]
  local g = (bySkill and bySkill[off]) or (weaponSkill == state.baseSkill and ctx.glancing) or (not ctx.glancingBySkill and ctx.glancing) or nil
  local glance, penalty, assumed
  if g and g.chance then
    glance, penalty = g.chance * 100, g.penalty or 0
  else
    -- (Classic: 10% + 2% per point of defense above your skill; ~5% less damage) - assumed
    glance, penalty, assumed = math.max(0, 10 + math.max(0, diff) * 2), 0.05, true
  end
  local crit = math.max(0, (state.crit or 0) - skill)
  crit = math.min(crit, math.max(0, 100 - miss - dodge - glance))
  local hit = math.max(0, 100 - miss - dodge - glance - crit)
  return { miss = miss, dodge = dodge, glance = glance, glancePenalty = penalty, crit = crit, hit = hit, assumedGlancing = assumed }
end

-- Auto-attack DPS, or nil and why.
function M.DPS(state, ctx)
  if not (state.swing and state.speed and state.speed > 0) then return nil, "no main-hand weapon damage on the sheet" end
  local dw = state.oh ~= nil
  local t = M.Table(state, ctx, nil, dw)
  local perSwing = (t.hit + t.glance * (1 - t.glancePenalty) + t.crit * M.CRIT_MULT) / 100
  local speedMult = 1 + (state.haste or 0) / 100
  local f = ctx.talents and ctx.talents.flurry
  local flurryUp = 0
  if f and f.haste > 0 then
    -- a swing is hasted if any of the last `swings` swings critted
    flurryUp = 1 - (1 - t.crit / 100) ^ (f.swings or 3)
    speedMult = speedMult * (1 + f.haste * flurryUp)
  end
  local dps = state.swing / state.speed * perSwing * speedMult
  local parts = { { name = "auto attack", dps = dps } }
  local landed = { mh = speedMult / state.speed * (t.hit + t.glance + t.crit) / 100, oh = 0 }
  local ohDps
  if dw and state.oh.speed and state.oh.speed > 0 then
    local line = state.oh.subclass and ns.StatDefs.WEAPON_SKILL[state.oh.subclass]
    local ohSkill = line and state.skills and state.skills[line] or state.weaponSkill
    local to = M.Table(state, ctx, ohSkill, true)
    local ohSwing = (state.oh.dps + (state.AP or 0) / 14) * state.oh.speed * M.OFFHAND_DAMAGE
    ohDps = ohSwing / state.oh.speed * (to.hit + to.glance * (1 - to.glancePenalty) + to.crit * M.CRIT_MULT) / 100 * speedMult
    dps = dps + ohDps
    parts[#parts + 1] = { name = "off-hand", dps = ohDps }
    landed.oh = speedMult / state.oh.speed * (to.hit + to.glance + to.crit) / 100
  end
  local assumed = {}
  -- abilities used on cooldown, with item bonuses to them
  local ab = ctx.abilities
  local abilityPct = {}
  for _, e in ipairs(state.effects or {}) do
    if e.kind == "abilityPct" then abilityPct[e.ability] = (abilityPct[e.ability] or 0) + e.pct end
  end
  if ab and #ab.strikes > 0 then
    local y = M.Special(state, ctx)
    for _, st in ipairs(ab.strikes) do
      local casts = 1 / st.cooldown
      local d = casts * state.swing * st.weaponPct / 100 * (1 + (abilityPct[st.name] or 0) / 100) * (y.hit + y.crit * M.CRIT_MULT) / 100
      parts[#parts + 1] = { name = st.name, dps = d }
      dps = dps + d
      landed.mh = landed.mh + casts * (y.hit + y.crit) / 100
    end
  end
  -- Windfury Weapon: extra main-hand attacks (white attacks) with its attack power
  local imb = ab and ab.imbue
  if imb and imb.kind == "windfury" and imb.slot == 16 then
    local lambda = M.ProcRate({ chance = imb.chance, icd = imb.icd }, landed.mh, state.speed)
    local per = (state.swing + (imb.ap or 0) / SE_AP_PER_DPS() * state.speed) * perSwing
    local d = lambda * (imb.attacks or 1) * per
    parts[#parts + 1] = { name = imb.name or "Windfury", dps = d, procsPerMin = lambda * 60 }
    dps = dps + d
  end
  -- item procs: damage and extra attacks
  local off = math.max(0, math.min(3, ctx.offset or 0))
  for _, e in ipairs(state.effects or {}) do
    if e.kind == "procDamage" or e.kind == "procExtra" then
      local hits = M.HitsFor(e.slot, landed)
      local speed = e.slot == 17 and state.oh and state.oh.speed or state.speed
      local lambda = M.ProcRate(e.rate, hits, speed)
      local d
      if e.kind == "procDamage" then
        d = lambda * e.avg * (1 - M.SPELL_MISS[off] / 100)
      else
        d = lambda * (e.attacks or 1) * state.swing * perSwing
      end
      parts[#parts + 1] = { name = e.item or "item proc", dps = d, procsPerMin = lambda * 60, rateSource = e.rate and e.rate.source }
      if e.rate and e.rate.source == "assumed" then assumed[#assumed + 1] = (e.item or "an item") .. "'s proc rate" end
      dps = dps + d
    end
  end
  return dps, { table = t, perSwing = perSwing, speedMult = speedMult, flurryUptime = flurryUp, offHand = ohDps,
    parts = parts, landed = landed, assumed = assumed }
end
