-- Melee model (milestone 2): auto-attack damage per second against a target of a given level.
-- Pure Lua. What it counts: your average swing (weapon + attack power + flat weapon damage, from the
-- sheet and moved by gear), the attack table, crits (double damage), glancing blows, haste and Flurry.
-- What it doesn't count yet (milestone 4): abilities (Stormstrike...), weapon imbues and procs
-- (Windfury...), off-hand swings. The upgrade % it gives is the change in auto-attack damage, which
-- most melee stats move in the same proportion as total damage.
--
-- The attack table is Forever's own (Blizzard's Camelot UI code):
--   miss chance vs a target 0/1/2/3 levels above you: 5.0 / 5.2 / 5.4 / 9.0 %, minus your hit
--   the target's dodge: 5.0 / 5.5 / 6.0 / 6.5 %
--   weapon skill vs the target's defense (5 x its level): 0.04 % per point on hit, dodge and crit
--   glancing chance and damage penalty: the game's GetGlancingBlowChance / GetGlancingBlowPenalty
local _, ns = ...
local M = ns and ns.Module and ns.Module("MeleeModel") or {}

M.MISS = { [0] = 5.0, 5.2, 5.4, 9.0 }
M.DODGE = { [0] = 5.0, 5.5, 6.0, 6.5 }
M.CRIT_MULT = 2.0

-- ctx: { offset = 0..3, glancing = { chance (0-1), penalty (0-1) } or nil, talents = TalentInterpreter output }
function M.Table(state, ctx)
  local off = math.max(0, math.min(3, ctx.offset or 0))
  local diff = (state.level + off) * 5 - (state.weaponSkill or state.level * 5)   -- target defense - your skill
  local skill = diff * 0.04
  local miss = math.max(0, M.MISS[off] + skill - (state.hit or 0))
  local dodge = math.max(0, M.DODGE[off] + skill)
  local g = ctx.glancing
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
  local t = M.Table(state, ctx)
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
  return dps, { table = t, perSwing = perSwing, speedMult = speedMult, flurryUptime = flurryUp }
end
