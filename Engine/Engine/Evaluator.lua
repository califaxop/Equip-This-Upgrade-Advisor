-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- Evaluator: performance of the character, marginal stat values, and item comparisons. Pure Lua.
--
--   ctx = Evaluator.Context(profile, settings)    the baseline: state, talents, target, game calculators
--   Evaluator.Performance(state, ctx)             { dps = , ehp = , why = { dps = , ehp = } }
--   Evaluator.Weights(ctx)                         value of one point of each stat, per metric
--   Evaluator.Compare(ctx, candidate)              the item in each slot it fits; best slot; % per metric
--
-- Metrics are kept separate (DPS, EHP); they are never added into one number.
local _, ns = ...; ns = ns.Engine
local Ev = ns and ns.Module and ns.Module("Evaluator") or {}

-- Specs whose damage is melee auto-attacks plus abilities (tree names as Forever shows them)
Ev.MELEE_TREES = { Enhancement = true, Arms = true, Fury = true, Protection = true, Retribution = true,
  Assassination = true, Combat = true, Subtlety = true, ["Feral Combat"] = true }
Ev.MELEE_CLASSES = { WARRIOR = true, ROGUE = true }
-- healing specs: their main metric is healing per second
Ev.HEAL_TREES = { Restoration = true, Holy = true, Discipline = true }
Ev.TANK_TREES = { Protection = true }

-- a tank: a Protection spec, or a threat-raising stance, form or aura on you (Defensive Stance,
-- Bear Form, Righteous Fury), or the setting
function Ev.IsTank(profile, sources, settings)
  if settings and settings.role == "tank" then return true end
  if settings and settings.role == "notank" then return false end
  local tree = profile.talents and profile.talents.primaryTree
  if tree and Ev.TANK_TREES[tree] then return true end
  for _, src in ipairs(sources or {}) do if src.source == "aura" and src.pct > 0 then return true end end
  return false
end

-- PvP (milestone 4c): its own assumptions, never PvE's.
--   target: a player of your level, armored like you (your armor's reduction vs your level, from
--   the game's calculator); no glancing blows; its dodge 5%, parry not counted; spells: 4% miss
--   (same level), no resistances (assumed).
--   sustained: DPS with your learned rotation vs that target
--   burst: damage in the first Ev.BURST seconds: abilities with a cooldown used at once (and again
--          when ready), use effects at full strength, the rest at their sustained rate
--   survival: EHP vs players: half physical, half magic (assumed), attacker your level, no crushing
Ev.BURST = 6
-- how long a fight lasts for mana (a boss fight, assumed; /eqn fight changes it)
Ev.FIGHT_LENGTH = 180
Ev.PVP_MAGIC_SHARE = 0.5
function Ev.PvPContext(ctx)
  if ctx.pvpCtx then return ctx.pvpCtx end
  local p = {}
  for k, v in pairs(ctx) do p[k] = v end
  p.pvp, p.offset, p.magicShare, p.glancing, p.glancingBySkill = true, 0, Ev.PVP_MAGIC_SHARE, nil, nil
  p.swingRaw = ctx.state.swing
  p.pvpCtx = nil
  ctx.pvpCtx = p
  return p
end

function Ev.PvP(state, ctx)
  local pc = Ev.PvPContext(ctx)
  local level = state.level or 1
  local red = ctx.armorEffect and ctx.armorEffect[level]
  if not red then
    local K = ns.SurvivalModel.ArmorK(pc, level, state.armor)
    red = (state.armor or 0) / ((state.armor or 0) + K)
  end
  local function after(part) return (part.school == "Physical" or not part.school) and (1 - red) or 1 end
  local p = Ev.Performance(state, pc)
  local out = { ehp = p.ehp, armorReduction = red }
  if p.dps and p.dpsInfo and p.dpsInfo.parts then
    local sus = 0
    for _, part in ipairs(p.dpsInfo.parts) do sus = sus + part.dps * after(part) end
    out.sustained = sus
    -- burst: with use effects at full strength
    pc.burst = true
    local pb = Ev.Performance(state, pc)
    pc.burst = nil
    local b = 0
    for _, part in ipairs(pb.dpsInfo.parts) do
      local dmg
      if part.cooldown and part.cooldown > 0 and part.perCast then
        dmg = (1 + math.floor(Ev.BURST / part.cooldown)) * part.perCast
      else
        dmg = part.dps * Ev.BURST
      end
      b = b + dmg * after(part)
    end
    out.burst = b
  end
  return out
end

-- which rotation is yours: per class and main talent tree
function Ev.RotationKey(profile)
  return tostring(profile.identity and profile.identity.class) .. ":" .. tostring(profile.talents and profile.talents.primaryTree)
end

-- How often you use each ability and spell.
--   measured (settings.rotation[key], from /eqn measure): casts per second of fighting
--   else learned now from the last measurement, if there is one
--   else assumed: casters and healers get SpellModel.DefaultRotation; a melee spec's spells aren't
--   counted (no guess at how a hybrid mixes them) and weapon strikes are used on cooldown
function Ev.Rotation(ctx, settings)
  local key = Ev.RotationKey(ctx.profile)
  local r = settings and settings.rotation and settings.rotation[key]
  if r then return r end
  local last = settings and settings.lastMeasurement
  -- (records from 0.4.x have no key: taken when the level matches)
  if last and (last.key == key or (last.key == nil and last.level == ctx.state.level)) then return Ev.LearnRotation(ctx, last) end
  local logs, borrowed = Ev.LogsFor(ctx)
  if logs then
    local r2 = Ev.RotationFromLogs(ctx, logs)
    r2.borrowed = borrowed
    return r2
  end
  local out = { rates = {}, strikes = {}, source = "assumed" }
  local S = ns.SpellModel
  if ctx.healer then out.rates = S.DefaultRotation(ctx.state, ctx, ctx.spells, "heal")
  elseif not ctx.melee then out.rates = S.DefaultRotation(ctx.state, ctx, ctx.spells, "damage")
  else
    out.source = next(ctx.spells or {}) and "none" or "assumed"
  end
  return out
end

-- How a physical ability's damage moves with your gear: its weapon's damage plus attack power at
-- a normalized speed (TBC's normalization, which Forever's abilities use: 2H 3.3, dagger 1.7, else
-- 2.4; ranged 2.8), times the special attack table (hit + 2 x crit). Abilities that scale with attack
-- power alone (Bloodthirst...) or have a flat part are approximated by this.
Ev.NORMALIZED = { twoHand = 3.3, dagger = 1.7, oneHand = 2.4, ranged = 2.8 }
function Ev.PhysicalScale(state, ctx, ranged)
  if ranged then
    local w = state.ranged
    local base = w and (w.dps + (state.RAP or 0) / 14) * Ev.NORMALIZED.ranged
      or (state.rangedSwing and state.rangedSpeed and state.rangedSwing / state.rangedSpeed * Ev.NORMALIZED.ranged) or 0
    local t = ns.RangedModel.Table(state, ctx)
    return base * (t.hit + t.crit * 2) / 100
  end
  local w = state.mh
  local norm = w and (w.twoHand and Ev.NORMALIZED.twoHand or (w.subclass == 15 and Ev.NORMALIZED.dagger) or Ev.NORMALIZED.oneHand) or Ev.NORMALIZED.oneHand
  local base = w and (w.dps + (state.AP or 0) / 14) * norm or (state.swing and state.speed and state.swing / state.speed * norm) or 0
  local y = ns.MeleeModel.Special(state, ctx)
  return base * (y.hit + y.crit * 2) / 100
end

-- what kind of damage or healing a spec does: "ranged", "melee", "healer", "caster"
function Ev.SpecKind(class, tree)
  if class == "HUNTER" then return "ranged" end
  if Ev.MELEE_CLASSES[class] or (tree and Ev.MELEE_TREES[tree]) then return "melee" end
  if tree and Ev.HEAL_TREES[tree] then return "healer" end
  return "caster"
end

-- the logged rotation for your class and spec; else your class's spec of the same kind with the
-- most players (borrowed = its key), else none
function Ev.LogsFor(ctx)
  local R = ns.ROTATIONS or {}
  local key = Ev.RotationKey(ctx.profile)
  if R[key] then return R[key] end
  local class = ctx.profile.identity and ctx.profile.identity.class
  local kind = Ev.SpecKind(class, ctx.profile.talents and ctx.profile.talents.primaryTree)
  local best, bestKey
  for k, r in pairs(R) do
    local c, t = k:match("^(.-):(.+)$")
    if c == class and Ev.SpecKind(c, t) == kind and (not best or r.players > best.players) then best, bestKey = r, k end
  end
  return best, bestKey
end

-- A default rotation from Warcraft Logs (Data/Rotations.lua: each ability's share of a spec's
-- damage and healing in Classic Era raids), turned into a measurement-like record and learned the
-- same way. Anchored on your own auto attack / Auto Shot when there is one; casters' and healers'
-- rates are scaled so they're casting all of the time.
function Ev.RotationFromLogs(ctx, logs)
  local anchor = ctx.ranged and "auto shot" or (ctx.melee and "auto attack" or nil)
  local parts = {}
  for _, p in ipairs(ctx.base.dpsInfo and ctx.base.dpsInfo.parts or {}) do parts[p.name] = p end
  local shareA = 0
  for _, a in ipairs(logs.damage or {}) do if anchor and a.name == anchor then shareA = a.share end end
  local dur, unit = 100, 1000
  if anchor and shareA > 0 and parts[anchor] then unit = parts[anchor].dps * dur / shareA end
  local rec = { duration = dur, parts = {}, other = {}, healing = {}, schools = {}, fromLogs = true }
  for _, a in ipairs(logs.damage or {}) do
    if a.name == anchor then rec.parts[#rec.parts + 1] = { name = anchor, measured = a.share * unit }
    else rec.other[#rec.other + 1] = { name = a.name, amount = a.share * unit } end
    rec.schools[a.name] = a.school
  end
  for _, a in ipairs(logs.healing or {}) do rec.healing[a.name] = a.share * 1000 end
  local out = Ev.LearnRotation(ctx, rec)
  if not (anchor and shareA > 0) then
    -- no anchor: cast all of the time (spells), physical parts scaled the same
    local busy = 0
    for name, r in pairs(out.rates) do
      local sp = ctx.spells[name]
      busy = busy + r * math.max(sp.gcd or 1.5, sp.cast or 0)
    end
    if busy > 0 then
      for name, r in pairs(out.rates) do out.rates[name] = r / busy end
      for _, ph in pairs(out.physical or {}) do ph.k = ph.k / busy end
    end
  end
  out.source, out.players, out.fights = "logs", logs.players, logs.fights
  return out
end

-- which of your spells (by the game's name) a model part is: the damage meter calls auto attacks
-- "Attack" (spell 6603, seen in game 0.4.1); a part named "Windfury 2" is any "Windfury..." spell
Ev.PART_NAMES = { ["auto attack"] = { "^attack$", "auto attack", "^melee$" }, ["off-hand"] = { "off%-hand", "offhand" },
  ["auto shot"] = { "^auto shot$" } }
function Ev.PartMatches(partName, spellName)
  local s, key = tostring(spellName):lower(), partName:lower()
  for _, w in ipairs(Ev.PART_NAMES[key] or { (key:gsub(" %d+$", "")) }) do if s:find(w) then return true end end
  return false
end

-- A measurement record from damage and healing by spell name (the game's damage meter), for
-- LearnRotation: amounts matched to the model's parts, the rest kept by name
function Ev.RecordFrom(ctx, byName, healByName, duration, fights)
  local rec = { duration = duration, fights = fights, level = ctx.state.level, key = Ev.RotationKey(ctx.profile),
    parts = {}, other = {}, healing = healByName or {} }
  local used = {}
  for _, part in ipairs(ctx.base.dpsInfo and ctx.base.dpsInfo.parts or {}) do
    local amt = 0
    for n, a in pairs(byName or {}) do
      if not used[n] and Ev.PartMatches(part.name, n) then amt = amt + a; used[n] = true end
    end
    rec.parts[#rec.parts + 1] = { name = part.name, measured = amt }
  end
  for n, a in pairs(byName or {}) do if not used[n] then rec.other[#rec.other + 1] = { name = n, amount = a } end end
  return rec
end

-- A rotation from a measurement (rec: /eqn measure's record): each ability's and spell's casts
-- per second of fighting = its damage (or healing) / the model's damage per cast / the time you
-- were fighting. "Fighting" time = combat time x your auto-attack uptime (measured auto-attack
-- damage / the model's), so it's on the same footing as the melee model (always attacking).
function Ev.LearnRotation(ctx, rec)
  local out = { rates = {}, strikes = {}, source = "measured", at = rec.time, fights = rec.fights }
  local dur = rec.duration or 0
  if dur <= 0 then return { rates = {}, strikes = {}, source = "assumed" } end
  local parts = {}
  for _, part in ipairs(ctx.base.dpsInfo and ctx.base.dpsInfo.parts or {}) do parts[part.name] = part end
  local measured = {}
  for _, p in ipairs(rec.parts or {}) do measured[p.name] = (measured[p.name] or 0) + (p.measured or 0) end
  for _, o in ipairs(rec.other or {}) do measured[o.name] = (measured[o.name] or 0) + (o.amount or 0) end
  local up = 1
  local anchor = ctx.ranged and "auto shot" or "auto attack"
  local auto = parts[anchor]
  if (ctx.melee or ctx.ranged) and auto and auto.dps > 0 and (measured[anchor] or 0) > 0 then
    up = math.max(0.05, math.min(1, measured[anchor] / (auto.dps * dur)))
  end
  out.uptime = up
  local active = dur * up
  for _, st in ipairs(ctx.abilities and ctx.abilities.strikes or {}) do
    local p = parts[st.name]
    if p and p.rate and p.rate > 0 and p.dps > 0 and measured[st.name] then
      -- (not capped at once per cooldown: in short fights it's used at each pull while auto
      -- attacks are still starting, so per second of auto-attacking it can come out above that)
      out.strikes[st.name] = measured[st.name] / (p.dps / p.rate) / active
    end
  end
  local S = ns.SpellModel
  for name, sp in pairs(ctx.spells or {}) do
    local amt = sp.kind == "heal" and rec.healing and rec.healing[name] or (sp.kind ~= "heal" and measured[name])
    if amt and amt > 0 then
      local per = S.PerCast(sp, ctx.state, ctx)
      if per > 0 then out.rates[name] = amt / per / active end
    end
  end
  -- physical abilities the model has no per-cast numbers for (Mortal Strike, Sinister Strike,
  -- Multi-Shot...): their damage share, scaling with the weapon and attack power (PhysicalScale)
  out.physical = {}
  local G = ns.GENERATED and ns.GENERATED.physical or {}
  local class = ctx.profile.identity and ctx.profile.identity.class
  local known = {}
  for _, p in pairs(parts) do known[p.name] = true end
  -- (from the logs, only abilities in your spellbook: a borrowed spec's may not be yours)
  local book
  if rec.fromLogs then
    book = {}
    for _, n in pairs(ctx.profile.spells and ctx.profile.spells.known or {}) do book[(tostring(n):gsub(" %(.*%)$", ""))] = true end
  end
  for name, amt in pairs(measured) do
    local g = G[name]
    local phys = (g and (not class or g.classes[class])) or (rec.schools and rec.schools[name] == 1)
    if book and not book[name] then phys = false end
    if phys and amt > 0 and not known[name] and not (ctx.spells and ctx.spells[name]) and name ~= anchor then
      local ranged = g and g.ranged or false
      local scale = Ev.PhysicalScale(ctx.state, ctx, ranged)
      if scale > 0 then out.physical[name] = { k = amt / active / scale, ranged = ranged } end
    end
  end
  return out
end

Ev.SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
}

function Ev.IsMelee(profile)
  local class = profile.identity and profile.identity.class
  if Ev.MELEE_CLASSES[class] then return true end
  local tree = profile.talents and profile.talents.primaryTree
  return tree and Ev.MELEE_TREES[tree] or false
end

-- target level offset: the setting, else +3 (a boss) at the level cap and +0 below it
function Ev.Offset(profile, settings)
  local o = settings and settings.targetOffset
  if type(o) == "number" then return math.max(0, math.min(3, o)) end
  return (profile.identity.level or 1) >= (settings and settings.maxLevel or 60) and 3 or 0
end

-- A weapon type whose skill is below your best weapon skill trains up with use: weapons are valued
-- at that skill (state.trainedSkill; today's % is given as a note). Also your worn weapon's, so a
-- comparison is the same seen from either item (regression: 0.4.1, wearing a 180-skill axe made a
-- 209-skill mace +133%).
Ev.UNTRAINED_GAP = 5   -- (a level's worth of skill or less: as it is)
local function trained(s, state)
  local base = state.trainedSkill or state.baseSkill
  if not (base and s.mh) then return nil end
  local function lineOf(w) return w and w.subclass and ns.StatDefs.WEAPON_SKILL[w.subclass] end
  local low = {}
  local mhLine = lineOf(s.mh)
  if s.weaponSkill and s.weaponSkill < base - Ev.UNTRAINED_GAP then low[#low + 1] = { line = mhLine, skill = s.weaponSkill } end
  local ohLine = lineOf(s.oh)
  local ohSkill = ohLine and s.skills and s.skills[ohLine]
  if ohSkill and ohSkill < base - Ev.UNTRAINED_GAP and ohLine ~= mhLine then low[#low + 1] = { line = ohLine, skill = ohSkill } end
  if #low == 0 then return nil end
  local t = {}
  for k, x in pairs(s) do t[k] = x end
  t.skills = {}
  for k, x in pairs(s.skills or {}) do t.skills[k] = x end
  for _, l in ipairs(low) do if l.line then t.skills[l.line] = base end end
  if s.weaponSkill < base - Ev.UNTRAINED_GAP then t.weaponSkill = base end
  return t, low[1].skill, base
end

-- the modelled effects of worn items ({ kind, ..., slot, item }), from ItemEffects.Model
function Ev.EffectsOf(items)
  local out = {}
  for slot, it in pairs(items) do
    if it and not it.empty then
      for _, m in ipairs(it.modeled or {}) do
        local e = {}
        for k, v in pairs(m) do e[k] = v end
        e.slot, e.item = slot, it.name
        out[#out + 1] = e
      end
    end
  end
  return out
end

-- Stat procs and use effects as average stats: amount x the share of time they're up.
--   proc: up 1 - e^(-procs a second x duration) of the time (a proc while it's up restarts it)
--   use:  duration / cooldown (used on cooldown)
function Ev.AverageStats(state, landed, burst)
  local avg = {}
  for _, e in ipairs(state.effects or {}) do
    local up
    if e.kind == "procStat" and e.duration and landed then
      local speed = e.slot == 17 and state.oh and state.oh.speed or state.speed
      local lambda = ns.MeleeModel.ProcRate(e.rate, ns.MeleeModel.HitsFor(e.slot, landed), speed)
      up = 1 - math.exp(-lambda * e.duration)
    elseif e.kind == "useStat" and e.duration and e.cooldown then
      up = burst and 1 or math.min(1, e.duration / e.cooldown)   -- (a burst opens with it)
    end
    if up and up > 0 then
      e.uptime = up
      for k, v in pairs(e.stats or {}) do avg[k] = (avg[k] or 0) + v * up end
    end
  end
  return avg
end

function Ev.Context(profile, settings)
  -- a spec chosen in the settings instead of the one the talents say
  if settings and settings.tree and profile.talents and settings.tree ~= profile.talents.primaryTree then
    local p, t = {}, {}
    for k, v in pairs(profile) do p[k] = v end
    for k, v in pairs(profile.talents) do t[k] = v end
    t.primaryTree = settings.tree
    p.talents = t
    profile = p
  end
  local state, why = ns.StatEngine.Baseline(profile)
  if not state then return nil, why end
  state.effects = Ev.EffectsOf(profile.equipment.slots)
  local gear = ns.StatEngine.GearTotals(profile)
  -- what the sheet has beyond gear (talents measured from it: Mental Quickness...)
  local extra = { SP = state.SP - (gear.SP or 0), HEAL = state.HEAL - (gear.HEAL or 0) }
  local talents = ns.TalentInterpreter.Interpret(profile, extra)
  local abilities = ns.AbilityInterpreter and ns.AbilityInterpreter.Interpret(profile, talents, settings and settings.confirmed) or { strikes = {}, notes = {}, unchecked = 0 }
  local offset = Ev.Offset(profile, settings)
  local calc = profile.calc or {}
  local tree = profile.talents and profile.talents.primaryTree
  local ctx = {
    profile = profile, state = state, gear = gear, talents = talents, abilities = abilities, offset = offset,
    melee = Ev.IsMelee(profile), healer = tree and Ev.HEAL_TREES[tree] and not Ev.IsMelee(profile) or false,
    ranged = (profile.identity and profile.identity.class == "HUNTER") or false,
    spells = ns.AbilityInterpreter and ns.AbilityInterpreter.Spells and ns.AbilityInterpreter.Spells(profile) or {},
    rotation = { rates = {}, strikes = {}, source = "assumed" },
    threat = ns.ThreatModel and ns.ThreatModel.Sources(profile) or {},
    fightLength = settings and tonumber(settings.fightLength),
    wantPvp = settings and settings.pvp,
    glancing = calc.glancing and calc.glancing[offset], armorEffect = calc.armorEffect,
    glancingBySkill = calc.glancingBySkill and next(calc.glancingBySkill) and calc.glancingBySkill or nil,
    baselineArmor = state.armor, magicShare = settings and settings.magicShare,
    canDualWield = settings and settings.canDualWield,
  }
  -- your best weapon skill (not above 5 x level): what weapons are valued at
  local best = state.weaponSkill or 0
  for _, line in pairs(ns.StatDefs.WEAPON_SKILL) do
    local v = state.skills and state.skills[line]
    if v and v > best then best = v end
  end
  state.trainedSkill = math.min(best, (state.level or 1) * 5)
  if ctx.melee then
    local t, now, base = trained(state, state)
    if t then
      -- your worn weapon isn't trained up: the baseline is at the trained skill, today's kept
      ctx.rawState, ctx.todayBase = state, Ev.Performance(state, ctx)
      ctx.state, state = t, t
      ctx.skillNote = string.format("your current weapon's skill is %d (vs %d)", now, base)
    end
  end
  ctx.base = Ev.Performance(state, ctx)
  -- the rotation needs the model's per-cast numbers: worked out after a first baseline
  ctx.rotation = Ev.Rotation(ctx, settings)
  if ctx.todayBase then ctx.todayBase = Ev.Performance(ctx.rawState, ctx) end
  ctx.tank = Ev.IsTank(profile, ctx.threat, settings)
  ctx.base = Ev.Performance(state, ctx)
  if ctx.wantPvp then ctx.pvpBase = Ev.PvP(state, ctx) end
  -- buffs and talents in the sheet beyond gear, per primary stat (stat.X.pos - gear)
  ctx.beyondGear = {}
  for _, k in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do
    local pos = profile.stats.values["stat." .. k .. ".pos"]
    if pos then ctx.beyondGear[k] = pos - (gear[k] or 0) end
  end
  return ctx
end

function Ev.Performance(state, ctx)
  local out = { why = {} }
  if ctx.melee then
    local d, info = ns.MeleeModel.DPS(state, ctx)
    if d then
      -- stat procs and use effects, averaged in (their uptime from this state's hit rate)
      local avg = Ev.AverageStats(state, info.landed, ctx.burst)
      if next(avg) then
        local d2, info2 = ns.MeleeModel.DPS(ns.StatEngine.Apply(state, avg, ctx.talents), ctx)
        if d2 then d, info = d2, info2; info.procStats = avg end
      end
    end
    out.dps, out.dpsInfo = d, info
    if not d then out.why.dps = info end
  end
  -- ranged (milestone 5: hunters): Auto Shot and ranged abilities
  if ctx.ranged then
    local d, info = ns.RangedModel.DPS(state, ctx)
    if d then
      local avg = Ev.AverageStats(state, info.landed, ctx.burst)
      if next(avg) then
        local d2, info2 = ns.RangedModel.DPS(ns.StatEngine.Apply(state, avg, ctx.talents), ctx)
        if d2 then d, info = d2, info2; info.procStats = avg end
      end
      out.dps, out.dpsInfo = d, info
    else
      out.why.dps = info
    end
  end
  -- spells (milestone 4b): damage added to DPS, healing as HPS
  local rates = ctx.rotation and ctx.rotation.rates
  if rates and next(rates) then
    local sd, sh, sparts, mana = ns.SpellModel.Output(state, ctx, ctx.spells, rates)
    -- mana (milestone 6): over a fight of ctx.fightLength seconds you can spend your pool plus
    -- what you regain while casting; a rotation that costs more is cast that much less. Not for a
    -- rotation measured in your own fights: you cast that much there (regen and drinking between
    -- fights included)
    local measured = ctx.rotation and ctx.rotation.source == "measured"
    if mana > 0 and state.manaMax and state.manaMax > 0 and not measured then
      local T = ctx.fightLength or Ev.FIGHT_LENGTH
      local avail = state.manaMax / T + (state.regenCast or 0)
      local limit = math.min(1, avail / mana)
      if limit < 1 then
        sd, sh = sd * limit, sh * limit
        for _, p in ipairs(sparts) do
          if p.dps then p.dps = p.dps * limit end
          if p.hps then p.hps = p.hps * limit end
        end
      end
      out.manaInfo = { cost = mana, available = avail, limit = limit, fight = T }
    end
    if sd > 0 then
      out.dpsInfo = out.dpsInfo or { parts = {} }
      out.dpsInfo.parts = out.dpsInfo.parts or {}
      for _, p in ipairs(sparts) do if p.dps then out.dpsInfo.parts[#out.dpsInfo.parts + 1] = p end end
      out.dps = (type(out.dps) == "number" and out.dps or 0) + sd
      out.why.dps = nil
    end
    if sh > 0 then
      out.hps = sh
      out.hpsInfo = { parts = {}, manaPerSec = mana }
      for _, p in ipairs(sparts) do if p.hps then out.hpsInfo.parts[#out.hpsInfo.parts + 1] = p end end
    end
  end
  if out.dps and out.dpsInfo and out.dpsInfo.parts and ns.ThreatModel then out.tps = ns.ThreatModel.TPS(out.dpsInfo.parts, ctx.threat) end
  if not out.dps and not out.why.dps then out.why.dps = ctx.melee and "no main-hand weapon damage on the sheet" or "no damage spells counted yet" end
  local e, info = ns.SurvivalModel.EHP(state, ctx)
  out.ehp, out.ehpInfo = e, info
  if not e then out.why.ehp = info end
  return out
end

-- the metric a comparison picks its best slot by: healing for healers, else damage, else EHP
function Ev.MainMetric(ctx)
  if ctx.healer and ctx.base.hps then return "hps" end
  if ctx.base.dps then return "dps" end
  return "ehp"
end

local function pct(new, old)
  if not (new and old) or old <= 0 then return nil end
  return (new / old - 1) * 100
end

-- One point (or `step`) of each stat: % change of each metric per point.
Ev.WEIGHT_STATS = { "STR", "AGI", "STA", "INT", "SPI", "AP", "CRIT_RATING", "HIT_RATING", "HASTE_RATING", "WEAPON_DMG",
  "ARMOR", "DEFENSE_RATING", "DODGE_RATING", "SP", "HEAL", "MP5", "RES_NATURE" }
function Ev.Weights(ctx, step)
  step = step or 10
  local out = {}
  for _, k in ipairs(Ev.WEIGHT_STATS) do
    local s = ns.StatEngine.Apply(ctx.state, { [k] = step }, ctx.talents)
    local p = Ev.Performance(s, ctx)
    local function per(m) local x = pct(p[m], ctx.base[m]); return x and x / step end
    out[k] = { dps = per("dps"), ehp = per("ehp"), hps = per("hps"), tps = per("tps") }
  end
  return out
end

-- Set bonuses: which are active with a given set of worn items, and what changes when items change.
-- bonuses come from the tooltips of the set's items ("(2) Set: +10 Attack Power").
local function setBonusDelta(ctx, removed, added)
  local profile = ctx.profile
  local count, bonuses = {}, {}
  local function learn(it)
    if it and it.setID and it.setBonuses and #it.setBonuses > 0 then bonuses[it.setID] = it.setBonuses end
  end
  for _, it in pairs(profile.equipment.slots) do
    if it.loaded and it.setID then count[it.setID] = (count[it.setID] or 0) + 1 end
    learn(it)
  end
  local after = {}
  for k, v in pairs(count) do after[k] = v end
  for _, it in ipairs(removed) do if it.setID then after[it.setID] = (after[it.setID] or 0) - 1 end end
  for _, it in ipairs(added) do
    learn(it)
    if it.setID then after[it.setID] = (after[it.setID] or 0) + 1 end
  end
  local delta, gained, lost, unknown = {}, {}, {}, {}
  for setID, list in pairs(bonuses) do
    local b, a = count[setID] or 0, after[setID] or 0
    for _, bonus in ipairs(list) do
      local was, now = b >= bonus.pieces, a >= bonus.pieces
      if was ~= now then
        local stats = ns.ItemText.ParseStatText(bonus.text)
        local txt = string.format("(%d) %s", bonus.pieces, bonus.text)
        if now then gained[#gained + 1] = txt else lost[#lost + 1] = txt end
        if stats then
          delta = ns.StatDefs.Add(delta, stats, now and 1 or -1)
        else
          unknown[#unknown + 1] = txt
        end
      end
    end
  end
  return delta, gained, lost, unknown
end

local function statsOf(it)
  if not it or it.empty or not it.stats then return {} end
  local s = ns.StatDefs.Normalize(it.stats)
  s.WEAPON_DPS = nil                     -- (a weapon's damage is handled as the weapon itself)
  if it.shieldBlock then s.BLOCK_VALUE = (s.BLOCK_VALUE or 0) + it.shieldBlock end
  for k, v in pairs(it.extraStats or {}) do s[k] = (s[k] or 0) + v end   -- "Equip: +2% block"...
  return s
end

local function weaponOf(it)
  if it and it.weapon and it.weapon.dps and it.weapon.speed then
    return { dps = it.weapon.dps, speed = it.weapon.speed, subclass = it.subclassID, twoHand = it.equipLoc == "INVTYPE_2HWEAPON" }
  end
end
local function isShield(it) return it and it.classID == ns.StatDefs.SHIELD.class and it.subclassID == ns.StatDefs.SHIELD.subclass end
local function isTwoHand(it) return it and it.equipLoc == "INVTYPE_2HWEAPON" end
local ONE_HAND = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OFF_HAND = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true }

-- One resulting setup: { [slot] = item or false (emptied) } -> option with performance and %.
function Ev.Evaluate(ctx, changes, label, notes)
  local eq = ctx.profile.equipment.slots
  local removed, added = {}, {}
  local delta = {}
  local weaponsChange = nil
  for slot, new in pairs(changes) do
    local old = eq[slot]
    if old and not old.empty then
      if not old.loaded then return { status = "loading", label = label } end
      removed[#removed + 1] = old
      delta = ns.StatDefs.Add(delta, statsOf(old), -1)
    end
    if new then
      added[#added + 1] = new
      delta = ns.StatDefs.Add(delta, statsOf(new))
    end
    if slot == 16 or slot == 17 then weaponsChange = true end
  end
  local weapons
  if weaponsChange then
    if not ctx.state.flat and ctx.melee then return { status = "unknown", label = label, why = "your main-hand weapon's speed couldn't be read" } end
    local mhItem = changes[16] == nil and eq[16] or changes[16] or nil
    local ohItem = changes[17] == nil and eq[17] or changes[17] or nil
    weapons = { mh = weaponOf(mhItem) or false, oh = weaponOf(ohItem) or false, shield = isShield(ohItem) and true or false }
    if not weapons.mh then weapons.mh = nil end
  end
  if changes[18] ~= nil and ctx.ranged then
    weapons = weapons or {}
    weapons.rangedW = weaponOf(changes[18] or nil) or false
  end
  local setDelta, gained, lost, setUnknown = setBonusDelta(ctx, removed, added)
  delta = ns.StatDefs.Add(delta, setDelta)
  -- the modelled item effects of the new setup: the worn ones not replaced, plus the new items'
  local effects, effectsChange = {}, false
  for _, e in ipairs(ctx.state.effects or {}) do
    if changes[e.slot] == nil then effects[#effects + 1] = e else effectsChange = true end
  end
  local newItems = {}
  for slot, new in pairs(changes) do if new then newItems[slot] = new end end
  for _, e in ipairs(Ev.EffectsOf(newItems)) do effects[#effects + 1] = e; effectsChange = true end
  local s = ns.StatEngine.Apply(ctx.state, delta, ctx.talents, weapons)
  s.effects = effects
  if weapons and weapons.mh == nil and changes[16] == false then s.swing, s.speed = nil, nil end
  s.effects = effects
  local p = Ev.Performance(s, ctx)
  local untrainedNote
  if weapons and ctx.melee then
    -- today's numbers: this setup with your skills as they are, vs your gear as it is today
    local pNow, baseNow = p, ctx.base
    if ctx.rawState then
      local sNow = ns.StatEngine.Apply(ctx.rawState, delta, ctx.talents, weapons)
      sNow.effects = effects
      pNow, baseNow = Ev.Performance(sNow, ctx), ctx.todayBase
    end
    local t, now, base = trained(s, ctx.state)
    if t then s, p = t, Ev.Performance(t, ctx) end
    local today, main = pct(pNow.dps, baseNow.dps), pct(p.dps, ctx.base.dps)
    if (t or ctx.rawState) and today and main and math.abs(today - main) >= 0.5 then
      -- (two short lines: one long one widens the tooltip)
      untrainedNote = { t and string.format("your skill with this weapon type is %d (vs %d)", now, base) or ctx.skillNote,
        string.format("until it's trained up: DPS %+.1f%%", today) }
    end
  end
  local opt = { status = "ok", label = label, changes = changes, removed = removed, added = added, delta = delta, perf = p,
    dps = pct(p.dps, ctx.base.dps), ehp = pct(p.ehp, ctx.base.ehp), hps = pct(p.hps, ctx.base.hps), notes = notes or {},
    tps = ctx.tank and pct(p.tps, ctx.base.tps) or nil,
    setGained = gained, setLost = lost, setUnknown = setUnknown }
  -- each stat on its own
  opt.parts = {}
  for k, d in pairs(delta) do
    if d ~= 0 then
      local p1 = Ev.Performance(ns.StatEngine.Apply(ctx.state, { [k] = d }, ctx.talents), ctx)
      opt.parts[#opt.parts + 1] = { stat = k, amount = d, dps = pct(p1.dps, ctx.base.dps), ehp = pct(p1.ehp, ctx.base.ehp), hps = pct(p1.hps, ctx.base.hps) }
    end
  end
  table.sort(opt.parts, function(a, b) return math.abs(a.dps or a.ehp or 0) > math.abs(b.dps or b.ehp or 0) end)
  if effectsChange then
    local se = {}
    for k, x in pairs(ctx.state) do se[k] = x end
    se.effects = effects
    local e1 = Ev.Performance(se, ctx)
    table.insert(opt.parts, 1, { stat = "EFFECTS", amount = 0, dps = pct(e1.dps, ctx.base.dps), ehp = pct(e1.ehp, ctx.base.ehp), hps = pct(e1.hps, ctx.base.hps) })
  end
  opt.assumedRates = {}
  for _, e in ipairs(effects) do
    if e.rate and e.rate.source == "assumed" and newItems[e.slot] then opt.assumedRates[#opt.assumedRates + 1] = e.item or "an item" end
  end
  if weapons then
    local ws = ns.StatEngine.Apply(ctx.state, {}, ctx.talents, weapons)
    ws = untrainedNote and trained(ws, ctx.state) or ws
    local w1 = Ev.Performance(ws, ctx)
    table.insert(opt.parts, 1, { stat = "WEAPON", amount = 0, dps = pct(w1.dps, ctx.base.dps), ehp = pct(w1.ehp, ctx.base.ehp), hps = pct(w1.hps, ctx.base.hps) })
  end
  -- effects of the removed items that aren't counted; enchants that carry over
  opt.lost, opt.carry = {}, {}
  for _, it in ipairs(removed) do
    for _, e in ipairs(it.effects or {}) do opt.lost[#opt.lost + 1] = e end
    if it.enchantText then opt.carry[#opt.carry + 1] = it.enchantText end
  end
  if untrainedNote then for _, n in ipairs(untrainedNote) do opt.notes[#opt.notes + 1] = n end end
  if ctx.wantPvp and ctx.pvpBase then
    local pv, b = Ev.PvP(s, ctx), ctx.pvpBase
    opt.pvp = { sustained = pct(pv.sustained, b.sustained), burst = pct(pv.burst, b.burst), ehp = pct(pv.ehp, b.ehp) }
  end
  if s.assumedSkill then opt.notes[#opt.notes + 1] = "weapon skill for this weapon type unknown: 5 x level assumed" end
  return opt
end

-- the best of a list of bag items for a slot when paired (by the main metric)
local function bestPartner(ctx, list, makeChanges)
  local best
  for _, it in ipairs(list) do
    local o = Ev.Evaluate(ctx, makeChanges(it), nil)
    local key = Ev.MainMetric(ctx)
    if o.status == "ok" and (not best or (o[key] or -math.huge) > (best.opt[key] or -math.huge)) then best = { item = it, opt = o } end
  end
  return best and best.item
end

-- candidate: an item record (EquipmentScanner.ReadItem): { link, itemID, equipLoc, loaded, stats, effects, ... }
function Ev.Compare(ctx, candidate)
  local res = { link = candidate.link, options = {}, notes = {} }
  if not candidate.loaded then res.status = "loading"; return res end
  if candidate.canUse == false then res.status = "cantuse"; res.why = "you can't use this (class, armor or weapon skill)"; return res end
  local level = ctx.profile.identity.level or 1
  if candidate.minLevel and candidate.minLevel > level then res.notes[#res.notes + 1] = "usable at level " .. candidate.minLevel end
  local loc = candidate.equipLoc
  local eq = ctx.profile.equipment.slots
  local bags = ctx.profile.bags or {}
  local canDW = ctx.profile.stats.values["dualWield"] == 1 or ctx.canDualWield
  local configs = {}   -- { changes, label, notes }
  local function add(changes, label, notes) configs[#configs + 1] = { changes, label, notes } end
  local mh = eq[16]
  if Ev.SLOTS[loc] then
    for _, slot in ipairs(Ev.SLOTS[loc]) do add({ [slot] = candidate }, eq[slot] and eq[slot].slotName or tostring(slot)) end
  elseif loc == "INVTYPE_2HWEAPON" then
    add({ [16] = candidate, [17] = false }, "Main hand")
  elseif ONE_HAND[loc] then
    if isTwoHand(mh) then
      local offs = {}
      for _, it in ipairs(bags) do if OFF_HAND[it.equipLoc] and (it.equipLoc ~= "INVTYPE_WEAPONOFFHAND" or canDW) then offs[#offs + 1] = it end end
      if canDW then for _, it in ipairs(bags) do if it.equipLoc == "INVTYPE_WEAPON" and it.link ~= candidate.link then offs[#offs + 1] = it end end end
      local partner = bestPartner(ctx, offs, function(it) return { [16] = candidate, [17] = it } end)
      add({ [16] = candidate, [17] = partner or false }, "Main hand",
        { partner and ("with " .. tostring(partner.name) .. " from your bags in the off-hand") or "with an empty off-hand (no off-hand in your bags)" })
    else
      add({ [16] = candidate }, "Main hand")
    end
    if loc == "INVTYPE_WEAPON" and canDW and mh and not isTwoHand(mh) and not mh.empty then add({ [17] = candidate }, "Off hand") end
  elseif OFF_HAND[loc] then
    if loc == "INVTYPE_WEAPONOFFHAND" and not canDW then res.status = "cantuse"; res.why = "you can't dual wield"; return res end
    if isTwoHand(mh) then
      local ones = {}
      for _, it in ipairs(bags) do if ONE_HAND[it.equipLoc] then ones[#ones + 1] = it end end
      local partner = bestPartner(ctx, ones, function(it) return { [16] = it, [17] = candidate } end)
      if partner then
        add({ [16] = partner, [17] = candidate }, "Off hand", { "with " .. tostring(partner.name) .. " from your bags instead of your two-hander" })
      else
        res.status = "none"; res.code = "needsOneHander"; res.why = "needs a one-hander (you wield a two-hander and have none in your bags)"; return res
      end
    else
      add({ [17] = candidate }, "Off hand")
    end
  elseif RANGED[loc] then
    add({ [18] = candidate }, "Ranged / relic", { "its own damage (ranged attacks) isn't modelled yet" })
  else
    res.status = "none"; res.why = "not an item slot this evaluates"; return res
  end
  for _, c in ipairs(configs) do
    local changes = c[1]
    local same = false
    for slot, it in pairs(changes) do if it and eq[slot] and eq[slot].link and it.link == eq[slot].link then same = true end end
    local opt
    if same then
      opt = { status = "equipped", label = c[2] }
    else
      -- unique: the same item already worn in another slot that isn't being replaced
      local dup = false
      if candidate.unique then
        for slot, it in pairs(eq) do
          if changes[slot] == nil and it.itemID and it.itemID == candidate.itemID then dup = true end
        end
      end
      if dup then opt = { status = "unique", label = c[2] }
      else opt = Ev.Evaluate(ctx, changes, c[2], c[3]) end
    end
    local first = next(changes)
    opt.slot, opt.slotName = first, c[2]
    opt.old = eq[first]
    res.options[#res.options + 1] = opt
  end
  local key = Ev.MainMetric(ctx)
  for _, o in ipairs(res.options) do
    if o.status == "ok" and (not res.best or (o[key] or -math.huge) > (res.best[key] or -math.huge)) then res.best = o end
  end
  res.metric = key
  res.status = res.best and "ok" or (res.options[1] and res.options[1].status or "none")
  -- confidence (effects that touch neither DPS nor EHP, like a faster revive, don't lower it)
  local function relevant(list)
    local n = 0
    for _, e in ipairs(list or {}) do if not ns.ItemEffects.IsIrrelevant(e) then n = n + 1 end end
    return n
  end
  local reasons = {}
  if relevant(candidate.effects) > 0 then reasons[#reasons + 1] = "the item has effects not counted yet" end
  local b = res.best
  if b and relevant(b.lost) > 0 then reasons[#reasons + 1] = "a replaced item has effects not counted yet" end
  if b and b.setUnknown and #b.setUnknown > 0 then reasons[#reasons + 1] = "a set bonus that changes isn't a plain stat" end
  if #ctx.state.assumed > 0 then reasons[#reasons + 1] = "assumed: " .. table.concat(ctx.state.assumed, ", ") end
  if ctx.talents.unchecked > 0 then reasons[#reasons + 1] = "a talent's number isn't confirmed" end
  if ctx.state.missingRating and next(ctx.state.missingRating) then reasons[#reasons + 1] = "a rating conversion is unknown" end
  if ctx.profile.stats.stale then reasons[#reasons + 1] = "stats are from before combat" end
  local rot = ctx.rotation or {}
  if rot.source == "none" then reasons[#reasons + 1] = "your spells aren't counted until /eqn measure learns how you use them"
  elseif rot.source == "assumed" and next(rot.rates or {}) then reasons[#reasons + 1] = "rotation assumed (/eqn measure learns yours)"
  elseif rot.source == "logs" then reasons[#reasons + 1] = "rotation from Warcraft Logs (Classic Era raids at 60): /eqn measure learns yours" end
  if ctx.melee or next(rot.rates or {}) then reasons[#reasons + 1] = "rage, energy and talents that change spells aren't counted" end
  if ctx.base.manaInfo and ctx.base.manaInfo.limit < 1 then
    reasons[#reasons + 1] = string.format("mana runs short over a %ds fight (assumed length; /eqn fight)", ctx.base.manaInfo.fight)
  end
  if ctx.abilities and ctx.abilities.unchecked > 0 then reasons[#reasons + 1] = "an ability or imbue number isn't confirmed" end
  if b and b.assumedRates and #b.assumedRates > 0 then reasons[#reasons + 1] = "proc rate assumed (once a minute): " .. table.concat(b.assumedRates, ", ") end
  if b and b.notes then for _, n in ipairs(b.notes) do if n:find("assumed") or n:find("isn't modelled") then reasons[#reasons + 1] = n end end end
  res.reasons = reasons
  local serious = relevant(candidate.effects) > 0 or (b and relevant(b.lost) > 0) or (b and b.setUnknown and #b.setUnknown > 0)
  res.confidence = serious and "low" or (#reasons > 1 and "medium" or "high")
  return res
end
