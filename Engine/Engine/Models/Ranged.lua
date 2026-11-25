-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- Ranged model (milestone 5: hunters): Auto Shot and ranged abilities. Pure Lua, expected values.
--   shot = the sheet's average ranged hit (ranged weapon + ranged attack power / 14 x speed + ammo
--   and scopes), moved by gear; every (speed / ranged haste) seconds.
--   table: miss 5 / 5.2 / 5.4 / 9 % vs +0-3 levels less your ranged hit; the target's dodge as for
--   melee (assumed: Classic's); no glancing; crits double (talents that raise it aren't counted).
-- Abilities (Multi-Shot, Aimed Shot...) come from your rotation as physical parts that scale with
-- the ranged weapon and ranged attack power (Evaluator.PhysicalScale).
local _, ns = ...; ns = ns.Engine
local R = ns and ns.Module and ns.Module("RangedModel") or {}
R.CRIT_MULT = 2.0

function R.Table(state, ctx)
  local M = ns.MeleeModel
  local off = math.max(0, math.min(3, ctx.offset or 0))
  local miss = math.max(0, M.MISS[off] - (state.rangedHit or 0))
  local dodge = ctx.pvp and M.PVP_DODGE or M.DODGE[off]
  local crit = math.min(math.max(0, state.rangedCrit or 0), math.max(0, 100 - miss - dodge))
  return { miss = miss, dodge = dodge, crit = crit, hit = math.max(0, 100 - miss - dodge - crit) }
end

function R.DPS(state, ctx)
  if not (state.rangedSwing and state.rangedSpeed and state.rangedSpeed > 0) then return nil, "no ranged weapon damage on the sheet" end
  local t = R.Table(state, ctx)
  local per = (t.hit + t.crit * R.CRIT_MULT) / 100
  local speedMult = 1 + (state.rangedHaste or 0) / 100
  local dps = state.rangedSwing / state.rangedSpeed * per * speedMult
  local parts = { { name = "auto shot", dps = dps, school = "Physical" } }
  for name, ph in pairs(ctx.rotation and ctx.rotation.physical or {}) do
    if ph.ranged then
      local d = ph.k * ns.Evaluator.PhysicalScale(state, ctx, true)
      parts[#parts + 1] = { name = name, dps = d, school = "Physical" }
      dps = dps + d
    end
  end
  return dps, { table = t, perShot = per, speedMult = speedMult, parts = parts, landed = { mh = speedMult / state.rangedSpeed * (t.hit + t.crit) / 100, oh = 0 } }
end
