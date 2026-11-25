-- Evaluator: performance of the character, marginal stat values, and item comparisons. Pure Lua.
--
--   ctx = Evaluator.Context(profile, settings)    the baseline: state, talents, target, game calculators
--   Evaluator.Performance(state, ctx)             { dps = , ehp = , why = { dps = , ehp = } }
--   Evaluator.Weights(ctx)                         value of one point of each stat, per metric
--   Evaluator.Compare(ctx, candidate)              the item in each slot it fits; best slot; % per metric
--
-- Metrics are kept separate (DPS, EHP); they are never added into one number.
local _, ns = ...
local Ev = ns and ns.Module and ns.Module("Evaluator") or {}

-- Specs whose damage is melee auto-attacks plus abilities (tree names as Forever shows them)
Ev.MELEE_TREES = { Enhancement = true, Arms = true, Fury = true, Protection = true, Retribution = true,
  Assassination = true, Combat = true, Subtlety = true, ["Feral Combat"] = true }
Ev.MELEE_CLASSES = { WARRIOR = true, ROGUE = true }
-- healing specs: their main metric is healing per second
Ev.HEAL_TREES = { Restoration = true, Holy = true, Discipline = true }

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
  local out = { rates = {}, strikes = {}, source = "assumed" }
  local S = ns.SpellModel
  if ctx.healer then out.rates = S.DefaultRotation(ctx.state, ctx, ctx.spells, "heal")
  elseif not ctx.melee then out.rates = S.DefaultRotation(ctx.state, ctx, ctx.spells, "damage")
  else
    out.source = next(ctx.spells or {}) and "none" or "assumed"
  end
  return out
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
  local auto = parts["auto attack"]
  if ctx.melee and auto and auto.dps > 0 and (measured["auto attack"] or 0) > 0 then
    up = math.max(0.05, math.min(1, measured["auto attack"] / (auto.dps * dur)))
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
function Ev.AverageStats(state, landed)
  local avg = {}
  for _, e in ipairs(state.effects or {}) do
    local up
    if e.kind == "procStat" and e.duration and landed then
      local speed = e.slot == 17 and state.oh and state.oh.speed or state.speed
      local lambda = ns.MeleeModel.ProcRate(e.rate, ns.MeleeModel.HitsFor(e.slot, landed), speed)
      up = 1 - math.exp(-lambda * e.duration)
    elseif e.kind == "useStat" and e.duration and e.cooldown then
      up = math.min(1, e.duration / e.cooldown)
    end
    if up and up > 0 then
      e.uptime = up
      for k, v in pairs(e.stats or {}) do avg[k] = (avg[k] or 0) + v * up end
    end
  end
  return avg
end

function Ev.Context(profile, settings)
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
    spells = ns.AbilityInterpreter and ns.AbilityInterpreter.Spells and ns.AbilityInterpreter.Spells(profile) or {},
    rotation = { rates = {}, strikes = {}, source = "assumed" },
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
  ctx.base = Ev.Performance(state, ctx)
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
      local avg = Ev.AverageStats(state, info.landed)
      if next(avg) then
        local d2, info2 = ns.MeleeModel.DPS(ns.StatEngine.Apply(state, avg, ctx.talents), ctx)
        if d2 then d, info = d2, info2; info.procStats = avg end
      end
    end
    out.dps, out.dpsInfo = d, info
    if not d then out.why.dps = info end
  end
  -- spells (milestone 4b): damage added to DPS, healing as HPS
  local rates = ctx.rotation and ctx.rotation.rates
  if rates and next(rates) then
    local sd, sh, sparts, mana = ns.SpellModel.Output(state, ctx, ctx.spells, rates)
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
  "ARMOR", "DEFENSE_RATING", "DODGE_RATING", "SP", "HEAL", "RES_NATURE" }
function Ev.Weights(ctx, step)
  step = step or 10
  local out = {}
  for _, k in ipairs(Ev.WEIGHT_STATS) do
    local s = ns.StatEngine.Apply(ctx.state, { [k] = step }, ctx.talents)
    local p = Ev.Performance(s, ctx)
    local function per(m) local x = pct(p[m], ctx.base[m]); return x and x / step end
    out[k] = { dps = per("dps"), ehp = per("ehp"), hps = per("hps") }
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
  local weaponsChange, newMH, newOH = nil, nil, nil
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
  local mh, oh = eq[16], eq[17]
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
        res.status = "none"; res.why = "needs a one-hander (you wield a two-hander and have none in your bags)"; return res
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
  elseif rot.source == "assumed" and next(rot.rates or {}) then reasons[#reasons + 1] = "rotation assumed (/eqn measure learns yours)" end
  if ctx.melee or next(rot.rates or {}) then reasons[#reasons + 1] = "mana, rage and talents that change spells aren't counted" end
  if ctx.abilities and ctx.abilities.unchecked > 0 then reasons[#reasons + 1] = "an ability or imbue number isn't confirmed" end
  if b and b.assumedRates and #b.assumedRates > 0 then reasons[#reasons + 1] = "proc rate assumed (once a minute): " .. table.concat(b.assumedRates, ", ") end
  if b and b.notes then for _, n in ipairs(b.notes) do if n:find("assumed") or n:find("isn't modelled") then reasons[#reasons + 1] = n end end end
  res.reasons = reasons
  local serious = relevant(candidate.effects) > 0 or (b and relevant(b.lost) > 0) or (b and b.setUnknown and #b.setUnknown > 0)
  res.confidence = serious and "low" or (#reasons > 1 and "medium" or "high")
  return res
end
