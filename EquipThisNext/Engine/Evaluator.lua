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
Ev.LATER = { INVTYPE_WEAPON = 3, INVTYPE_2HWEAPON = 3, INVTYPE_WEAPONMAINHAND = 3, INVTYPE_WEAPONOFFHAND = 3,
  INVTYPE_SHIELD = 3, INVTYPE_HOLDABLE = 3, INVTYPE_RANGED = 3, INVTYPE_RANGEDRIGHT = 3, INVTYPE_THROWN = 3,
  INVTYPE_RELIC = 3 }

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
    baselineArmor = state.armor, magicShare = settings and settings.magicShare,
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

-- candidate: an item record (EquipmentScanner.ReadItem): { link, itemID, equipLoc, loaded, stats, effects }
function Ev.Compare(ctx, candidate)
  local res = { link = candidate.link, options = {} }
  if not candidate.loaded then res.status = "loading"; return res end
  local loc = candidate.equipLoc
  if Ev.LATER[loc] then res.status = "later"; res.why = "weapons, shields, off-hands and relics come in milestone " .. Ev.LATER[loc]; return res end
  local slots = Ev.SLOTS[loc]
  if not slots then res.status = "none"; res.why = "not an equippable slot this evaluates"; return res end
  local cand = ns.StatDefs.Normalize(candidate.stats)
  local eq = ctx.profile.equipment.slots
  for _, slot in ipairs(slots) do
    local old = eq[slot]
    local opt = { slot = slot, slotName = old and old.slotName or tostring(slot), old = old }
    if old and not old.empty and not old.loaded then
      opt.status = "loading"
    elseif old and old.link and old.link == candidate.link then
      opt.status = "equipped"
    else
      local oldStats = (old and not old.empty) and ns.StatDefs.Normalize(old.stats) or {}
      local delta = ns.StatDefs.Add(cand, oldStats, -1)
      local s = ns.StatEngine.Apply(ctx.state, delta, ctx.talents)
      local p = Ev.Performance(s, ctx)
      opt.delta, opt.perf = delta, p
      opt.dps, opt.ehp = pct(p.dps, ctx.base.dps), pct(p.ehp, ctx.base.ehp)
      -- each stat on its own: why it's up or down
      opt.parts = {}
      for k, d in pairs(delta) do
        if d ~= 0 then
          local p1 = Ev.Performance(ns.StatEngine.Apply(ctx.state, { [k] = d }, ctx.talents), ctx)
          opt.parts[#opt.parts + 1] = { stat = k, amount = d, dps = pct(p1.dps, ctx.base.dps), ehp = pct(p1.ehp, ctx.base.ehp) }
        end
      end
      table.sort(opt.parts, function(a, b)
        return math.abs(a.dps or a.ehp or 0) > math.abs(b.dps or b.ehp or 0)
      end)
      opt.lost = old and old.effects or nil
      opt.status = "ok"
    end
    res.options[#res.options + 1] = opt
  end
  -- best slot, on the main metric (DPS for melee specs, else EHP)
  local key = ctx.melee and "dps" or "ehp"
  for _, o in ipairs(res.options) do
    if o.status == "ok" and (not res.best or (o[key] or -math.huge) > (res.best[key] or -math.huge)) then res.best = o end
  end
  res.metric = key
  res.status = res.best and "ok" or (res.options[1] and res.options[1].status or "none")
  -- confidence: lowered by effects not counted (on the new item or the one it replaces), assumptions
  -- and talent numbers not confirmed
  local reasons = {}
  if candidate.effects and #candidate.effects > 0 then reasons[#reasons + 1] = "the item has effects not counted yet" end
  if res.best and res.best.lost and #res.best.lost > 0 then reasons[#reasons + 1] = "the replaced item has effects not counted yet" end
  if #ctx.state.assumed > 0 then reasons[#reasons + 1] = "assumed: " .. table.concat(ctx.state.assumed, ", ") end
  if ctx.talents.unchecked > 0 then reasons[#reasons + 1] = "a talent's number isn't confirmed" end
  if ctx.state.missingRating and next(ctx.state.missingRating) then reasons[#reasons + 1] = "a rating conversion is unknown" end
  if ctx.profile.stats.stale then reasons[#reasons + 1] = "stats are from before combat" end
  if ctx.melee then reasons[#reasons + 1] = "abilities, imbues and procs not in DPS yet" end
  res.reasons = reasons
  local serious = (candidate.effects and #candidate.effects > 0) or (res.best and res.best.lost and #res.best.lost > 0)
  res.confidence = serious and "low" or (#reasons > 1 and "medium" or "high")
  return res
end
