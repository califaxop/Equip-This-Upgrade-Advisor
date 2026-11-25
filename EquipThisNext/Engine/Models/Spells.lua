-- Spell model (milestone 4b): damage and healing from spells. Pure Lua, expected values.
--
-- Per cast:
--   damage: (direct + coef x spell damage) x (1 - miss) x (1 + crit x 0.5)  +  (DoT + coef x spell
--           damage) x (1 - miss)                     (DoT ticks don't crit; DoT coef = per tick x ticks)
--   heal:   (direct + coef x healing) x (1 + crit x 0.5)  +  (HoT + coef x healing)
--   spell miss vs 0-3 levels above: 4 / 5 / 6 / 17 %, at least 1%, less your spell hit (Classic's
--   table, assumed for Forever); spell crits do 150% (Classic's; talents that change it aren't in yet).
-- How often each spell is cast: the rotation (Evaluator: learned from your fights by /eqn measure,
-- else a stated assumption). Output: parts per spell, DPS, HPS, healing per mana.
local _, ns = ...
local S = ns and ns.Module and ns.Module("SpellModel") or {}
S.CRIT_MULT = 1.5
S.MISS = { [0] = 4, 5, 6, 17 }
S.MIN_MISS = 1

function S.Miss(state, ctx)
  local off = math.max(0, math.min(3, ctx.offset or 0))
  return math.max(S.MIN_MISS, S.MISS[off] - (state.spellHit or 0))
end

-- average damage or healing of one cast in this state
function S.PerCast(sp, state, ctx)
  local school = sp.school and state.spBySchool and state.spBySchool[sp.school:upper()]
  local power = sp.kind == "heal" and (state.HEAL or 0) or (school or state.SP or 0)
  local crit = math.max(0, math.min(100, state.spellCrit or 0)) / 100
  local land = sp.kind == "heal" and 1 or (1 - S.Miss(state, ctx) / 100)
  local total = 0
  if sp.direct then total = total + (sp.direct.avg + sp.direct.coef * power) * land * (1 + crit * (S.CRIT_MULT - 1)) end
  if sp.dot then total = total + (sp.dot.total + sp.dot.coef * power) * land end
  return total
end

-- rates: { [name] = casts per second }. -> dps, hps, parts = { { name, dps | hps, perCast, perMin } }, manaPerSec
function S.Output(state, ctx, spells, rates)
  local dps, hps, mana, parts = 0, 0, 0, {}
  for name, r in pairs(rates or {}) do
    local sp = spells and spells[name]
    if sp and r > 0 then
      local per = S.PerCast(sp, state, ctx)
      local x = per * r
      if sp.kind == "heal" then hps = hps + x else dps = dps + x end
      mana = mana + (sp.mana or 0) * r
      parts[#parts + 1] = { name = name, kind = sp.kind, dps = sp.kind ~= "heal" and x or nil, hps = sp.kind == "heal" and x or nil,
        perCast = per, perMin = r * 60, rate = r, school = sp.school, cooldown = sp.cooldown, cast = sp.cast }
    end
  end
  table.sort(parts, function(a, b) return (a.dps or a.hps) > (b.dps or b.hps) end)
  return dps, hps, parts, mana
end

-- A default rotation when none has been measured (a stated assumption):
--   damage: DoTs kept up (one cast per duration), spells with a cooldown on cooldown, and the
--           best damage-per-cast-time spell without one filling the rest of the time;
--   heal:   the best healing-per-cast-time heal without a cooldown, cast all the time.
function S.DefaultRotation(state, ctx, spells, kind)
  local rates, busy = {}, 0
  local filler, fillerRate
  -- spells that share a cooldown (a category: Earth / Flame / Frost Shock): only the best of them
  local bestOf = {}
  for name, sp in pairs(spells or {}) do
    if sp.kind == kind and sp.category then
      local b = bestOf[sp.category]
      if not b or S.PerCast(sp, state, ctx) > S.PerCast(spells[b], state, ctx) then bestOf[sp.category] = name end
    end
  end
  for name, sp in pairs(spells or {}) do
    if sp.kind == kind and (not sp.category or bestOf[sp.category] == name) then
      local t = math.max(sp.gcd or 1.5, sp.cast or 0)
      if kind == "damage" and sp.dot and not sp.direct and sp.dot.ticks then
        local dur = sp.dot.duration or 0
        if dur > 0 then rates[name] = 1 / math.max(dur, sp.cooldown or 0); busy = busy + rates[name] * t end
      elseif sp.cooldown and sp.cooldown > 0 and kind == "damage" then
        rates[name] = 1 / sp.cooldown; busy = busy + rates[name] * t
      elseif not (sp.cooldown and sp.cooldown > 0) then
        local v = S.PerCast(sp, state, ctx) / t
        if not fillerRate or v > fillerRate then filler, fillerRate = name, v end
      end
    end
  end
  if filler then
    local sp = spells[filler]
    rates[filler] = math.max(0, 1 - busy) / math.max(sp.gcd or 1.5, sp.cast or 0)
  end
  return rates
end
