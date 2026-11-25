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

function Ev.Context(profile, settings)
  local state, why = ns.StatEngine.Baseline(profile)
  if not state then return nil, why end
  local gear = ns.StatEngine.GearTotals(profile)
  -- what the sheet has beyond gear (talents measured from it: Mental Quickness...)
  local extra = { SP = state.SP - (gear.SP or 0), HEAL = state.HEAL - (gear.HEAL or 0) }
  local talents = ns.TalentInterpreter.Interpret(profile, extra)
  local offset = Ev.Offset(profile, settings)
  local calc = profile.calc or {}
  local ctx = {
    profile = profile, state = state, gear = gear, talents = talents, offset = offset,
    melee = Ev.IsMelee(profile),
    glancing = calc.glancing and calc.glancing[offset], armorEffect = calc.armorEffect,
    glancingBySkill = calc.glancingBySkill and next(calc.glancingBySkill) and calc.glancingBySkill or nil,
    baselineArmor = state.armor, magicShare = settings and settings.magicShare,
    canDualWield = settings and settings.canDualWield,
  }
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
    out.dps, out.dpsInfo = d, info
    if not d then out.why.dps = info end
  else
    out.why.dps = "spell damage and healing are modelled in milestone 4"
  end
  local e, info = ns.SurvivalModel.EHP(state, ctx)
  out.ehp, out.ehpInfo = e, info
  if not e then out.why.ehp = info end
  return out
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
    out[k] = { dps = pct(p.dps, ctx.base.dps) and pct(p.dps, ctx.base.dps) / step, ehp = pct(p.ehp, ctx.base.ehp) and pct(p.ehp, ctx.base.ehp) / step }
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
  local s = ns.StatEngine.Apply(ctx.state, delta, ctx.talents, weapons)
  if weapons and weapons.mh == nil and changes[16] == false then s.swing, s.speed = nil, nil end
  local p = Ev.Performance(s, ctx)
  local opt = { status = "ok", label = label, changes = changes, removed = removed, added = added, delta = delta, perf = p,
    dps = pct(p.dps, ctx.base.dps), ehp = pct(p.ehp, ctx.base.ehp), notes = notes or {},
    setGained = gained, setLost = lost, setUnknown = setUnknown }
  -- each stat on its own
  opt.parts = {}
  for k, d in pairs(delta) do
    if d ~= 0 then
      local p1 = Ev.Performance(ns.StatEngine.Apply(ctx.state, { [k] = d }, ctx.talents), ctx)
      opt.parts[#opt.parts + 1] = { stat = k, amount = d, dps = pct(p1.dps, ctx.base.dps), ehp = pct(p1.ehp, ctx.base.ehp) }
    end
  end
  table.sort(opt.parts, function(a, b) return math.abs(a.dps or a.ehp or 0) > math.abs(b.dps or b.ehp or 0) end)
  if weapons then
    local w1 = Ev.Performance(ns.StatEngine.Apply(ctx.state, {}, ctx.talents, weapons), ctx)
    table.insert(opt.parts, 1, { stat = "WEAPON", amount = 0, dps = pct(w1.dps, ctx.base.dps), ehp = pct(w1.ehp, ctx.base.ehp) })
  end
  -- effects of the removed items that aren't counted; enchants that carry over
  opt.lost, opt.carry = {}, {}
  for _, it in ipairs(removed) do
    for _, e in ipairs(it.effects or {}) do opt.lost[#opt.lost + 1] = e end
    if it.enchantText then opt.carry[#opt.carry + 1] = it.enchantText end
  end
  if s.assumedSkill then opt.notes[#opt.notes + 1] = "weapon skill for this weapon type unknown: 5 x level assumed" end
  return opt
end

-- the best of a list of bag items for a slot when paired (by the main metric)
local function bestPartner(ctx, list, makeChanges)
  local best
  for _, it in ipairs(list) do
    local o = Ev.Evaluate(ctx, makeChanges(it), nil)
    local key = ctx.melee and "dps" or "ehp"
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
  local key = ctx.melee and "dps" or "ehp"
  for _, o in ipairs(res.options) do
    if o.status == "ok" and (not res.best or (o[key] or -math.huge) > (res.best[key] or -math.huge)) then res.best = o end
  end
  res.metric = key
  res.status = res.best and "ok" or (res.options[1] and res.options[1].status or "none")
  -- confidence
  local reasons = {}
  if candidate.effects and #candidate.effects > 0 then reasons[#reasons + 1] = "the item has effects not counted yet" end
  local b = res.best
  if b and b.lost and #b.lost > 0 then reasons[#reasons + 1] = "a replaced item has effects not counted yet" end
  if b and b.setUnknown and #b.setUnknown > 0 then reasons[#reasons + 1] = "a set bonus that changes isn't a plain stat" end
  if #ctx.state.assumed > 0 then reasons[#reasons + 1] = "assumed: " .. table.concat(ctx.state.assumed, ", ") end
  if ctx.talents.unchecked > 0 then reasons[#reasons + 1] = "a talent's number isn't confirmed" end
  if ctx.state.missingRating and next(ctx.state.missingRating) then reasons[#reasons + 1] = "a rating conversion is unknown" end
  if ctx.profile.stats.stale then reasons[#reasons + 1] = "stats are from before combat" end
  if ctx.melee then reasons[#reasons + 1] = "abilities, imbues and procs not in DPS yet" end
  if b and b.notes then for _, n in ipairs(b.notes) do if n:find("assumed") or n:find("isn't modelled") then reasons[#reasons + 1] = n end end end
  res.reasons = reasons
  local serious = (candidate.effects and #candidate.effects > 0) or (b and b.lost and #b.lost > 0) or (b and b.setUnknown and #b.setUnknown > 0)
  res.confidence = serious and "low" or (#reasons > 1 and "medium" or "high")
  return res
end
