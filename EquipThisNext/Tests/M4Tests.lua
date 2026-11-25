-- Milestone 4 (first part): abilities, Windfury, item procs and use effects in melee DPS, and the
-- check against the game's damage meter. On the level 42 Enhancement Shaman fixture.
MOCK.Reset()
local ns = LoadAddon()
local P, SE, Ev, IE, M = ns.CharacterProfile, ns.StatEngine, ns.Evaluator, ns.ItemEffects, ns.MeleeModel

local function fixture()
  local p = ns.Database.Copy(FIXTURE_SHAMAN42)
  for _, n in ipairs(p.talents.nodes) do n.groupIDs = n.groupIDs or { n.groupID } end
  P.AssignTrees(p.talents); P.SumTreePoints(p.talents)
  p.calc = p.calc or {}
  local mh = p.equipment.slots[16]
  mh.weapon = { dps = mh.stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT, speed = 3.6 }
  p.stats.skillByLine = { [160] = 209, [44] = 205, [54] = 210 }
  -- Rage of the Storm's effect line, as the 0.3.0 dump read it (the 0.1.0 fixture has no effect lines)
  mh.effects = mh.effects or { "Equip: Increases the damage dealt by your Stormstrike ability by 10%." }
  -- (the 0.3.0 dump predates milestone 4: its effect lines split as the scanner now does)
  for _, it in pairs(p.equipment.slots) do
    if it.effects then it.modeled, it.effects = IE.Split(it.effects, it.itemID) end
  end
  return p
end
-- what the game shows for Stormstrike and Windfury Weapon (Forever: 100% weapon damage, 8 sec cooldown)
local SS_DESC = "Instantly strike for 100% weapon damage and increase the damage you deal to the target with your next Lightning Bolt, Chain Lightning, or Earth Shock spell by 20% for 12 sec."
local WF_DESC = "Imbue the Shaman's weapon with wind.  Each hit has a 20% chance of granting you 1 extra attack with 145 extra melee attack power. Lasts for 60 minutes."
local function withAbilities(p, wf)
  p.abilities = { spells = { [17364] = { known = true, desc = SS_DESC, cooldownText = "8 sec cooldown" } }, imbues = {} }
  if wf then p.abilities.imbues[16] = { enchantID = 284, castSpell = 8235, desc = WF_DESC } end
  return p
end
local function rank(p, name, r) for _, n in ipairs(p.talents.nodes) do if n.name == name then n.rank = r end end end

T.Test("M4: item effect lines the models count (and the ones they don't)", function()
  local a = IE.Model("Equip: Increases the damage dealt by your Stormstrike ability by 10%.", 280604)
  T.Eq(a.kind, "abilityPct"); T.Eq(a.ability, "Stormstrike"); T.Eq(a.pct, 10)
  local d = IE.Model("Chance on hit: Blasts the enemy for 70 to 90 Fire damage.", 1)
  T.Eq(d.kind, "procDamage"); T.Eq(d.avg, 80); T.Eq(d.school, "Fire")
  T.Eq(IE.Model("Chance on hit: Wounds the target for 50 damage.", 1).school, "Physical", "no school: physical")
  local x = IE.Model("Chance on hit: Grants 1 extra attack.", 1)
  T.Eq(x.kind, "procExtra"); T.Eq(x.attacks, 1)
  local st = IE.Model("Chance on hit: Increases your attack power by 120 for 10 sec.", 1)
  T.Eq(st.kind, "procStat"); T.Eq(st.stats.AP, 120); T.Eq(st.duration, 10)
  local u = IE.Model("Use: Increases your Strength by 50 for 20 sec. (5 |4Min:Min; Cooldown)", 1)
  T.Eq(u.kind, "useStat", "the dump's unresolved plural token"); T.Eq(u.stats.STR, 50); T.Eq(u.cooldown, 300)
  T.Eq(IE.Model("Use: Absorb up to 260 to 300 damage and Stun yourself for 5 sec. (5 |4Min:Min; Cooldown)", 1), nil, "not a stat: not counted")
  T.Eq(IE.Model("Chance on hit: zaps the target.", 1), nil, "no number: not counted")
end)

T.Test("M4: proc rates: measured, then the game's tables, else assumed once a minute (and said so)", function()
  T.Eq(IE.Rate(23221).source, "measured"); T.Near(IE.Rate(23221).ppm, 3.27, 1e-9)
  local id
  for i, g in pairs(ns.GENERATED.itemProcs) do if g.chance > 0 and g.chance < 100 then id = i end end
  T.Eq(IE.Rate(id).source, "game data", "item " .. id)
  T.Eq(IE.Rate(id).chance, ns.GENERATED.itemProcs[id].chance)
  T.Eq(IE.Rate(1).source, "assumed"); T.Eq(IE.Rate(1).ppm, 1)
  -- rates: 20% of 1 hit/s with a 1.5 s internal cooldown: 0.2 / (1 + 0.2 x 1.5)
  T.Near(M.ProcRate({ chance = 20, icd = 1.5 }, 1), 0.2 / 1.3, 1e-12)
  T.Near(M.ProcRate({ ppm = 2 }, 1, 3), 0.1, 1e-12, "2 a minute with a 3.0 weapon: 10% a hit")
end)

T.Test("M4: Stormstrike and Windfury read from what the game shows; Forever's data fills the rest", function()
  local p = withAbilities(fixture(), true)
  rank(p, "Elemental Weapons", 0)
  local a = ns.AbilityInterpreter.Interpret(p, {})
  T.Eq(#a.strikes, 1); T.Eq(a.strikes[1].weaponPct, 100); T.Eq(a.strikes[1].cooldown, 8, "from the tooltip")
  T.Eq(a.imbue.chance, 20); T.Eq(a.imbue.attacks, 1); T.Eq(a.imbue.ap, 145); T.Eq(a.imbue.icd, 1.5, "internal cooldown from the game's data")
  T.Eq(a.unchecked, 0)
  rank(p, "Elemental Weapons", 3)
  local b = ns.AbilityInterpreter.Interpret(p, {})
  T.Near(b.imbue.ap, 145 * 1.4, 1e-9, "Elemental Weapons 3/3: +40% (Classic's value, unconfirmed)")
  T.Eq(b.unchecked, 1)
  T.Eq(ns.AbilityInterpreter.Interpret(p, {}, { ["Windfury 2"] = true }).unchecked, 0, "confirmed by a measurement")
  -- no description (not in the spellbook...): the game's data, level-scaled
  p.abilities.imbues[16].desc = nil
  rank(p, "Elemental Weapons", 0)
  local c = ns.AbilityInterpreter.Interpret(p, {})
  T.Near(c.imbue.ap, 46 + 7.2 * (38 - 30), 1e-9, "439431's attack power at its max level 38"); T.Eq(c.imbue.apSource, "game data")
end)

T.Test("M4: Stormstrike's DPS: weapon damage every 8 s, special attack table, +10% from Rage of the Storm", function()
  local p = withAbilities(fixture(), false)
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local s = ctx.state
  local info = ctx.base.dpsInfo
  local ss
  for _, part in ipairs(info.parts) do if part.name == "Stormstrike" then ss = part end end
  T.Ok(ss, "a Stormstrike part")
  local y = M.Special(s, ctx)
  T.Eq(y.miss, 5.0 + (210 - 209) * 0.04 - s.hit, "no dual-wield penalty")
  local bonus = 1
  for _, e in ipairs(s.effects) do if e.kind == "abilityPct" then bonus = bonus + e.pct / 100 end end
  T.Near(bonus, 1.10, 1e-9, "Rage of the Storm's +10% read from its tooltip line")
  T.Near(ss.dps, s.swing / 8 * bonus * (y.hit + y.crit * 2) / 100, 1e-9)
  -- swapping the weapon loses the bonus: the item-effects part says so
  local res = Ev.Compare(ctx, { link = "item:279887", itemID = 279887, name = "I'lalai Flayer", loaded = true, equipLoc = "INVTYPE_WEAPON",
    classID = 2, subclassID = 0, canUse = true, effects = {}, modeled = {},
    stats = { ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 8, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 28.65 },
    weapon = { dps = 28.65, speed = 2.6 } })
  local fx
  for _, part in ipairs(res.best.parts) do if part.stat == "EFFECTS" then fx = part end end
  T.Ok(fx and fx.dps < 0, "losing Rage of the Storm's Stormstrike bonus costs DPS: " .. tostring(fx and fx.dps))
  T.Ok(res.confidence ~= "low", "the bonus is counted, so it doesn't make confidence low: " .. res.confidence)
end)

T.Test("M4: Windfury: 20% of landed main-hand hits (swings and Stormstrike), 1.5 s internal cooldown, white extra attacks", function()
  local p = withAbilities(fixture(), true)
  rank(p, "Elemental Weapons", 0)
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local s, info = ctx.state, ctx.base.dpsInfo
  local t, y = info.table, M.Special(s, ctx)
  local landed = info.speedMult / s.speed * (t.hit + t.glance + t.crit) / 100 + 1 / 8 * (y.hit + y.crit) / 100
  local lambda = 0.2 * landed / (1 + 0.2 * landed * 1.5)
  local wf
  for _, part in ipairs(info.parts) do if part.name == "Windfury 2" then wf = part end end
  T.Near(wf.dps, lambda * (s.swing + 145 / 14 * s.speed) * info.perSwing, 1e-9)
  T.Ok(wf.procsPerMin > 2 and wf.procsPerMin < 8, "procs a minute: " .. wf.procsPerMin)
  local total = 0
  for _, part in ipairs(info.parts) do total = total + part.dps end
  T.Near(total, ctx.base.dps, 1e-9, "the parts add up to the DPS")
end)

T.Test("M4: stat procs and use effects count as their average (amount x time up)", function()
  local p = fixture()
  local ring = p.equipment.slots[11]
  ring.modeled = { { kind = "useStat", stats = { AP = 100 }, duration = 20, cooldown = 120 } }
  local ctx = Ev.Context(p, { targetOffset = 0 })
  T.Near(ctx.base.dpsInfo.procStats.AP, 100 * 20 / 120, 1e-9, "use: 20 s of 2 min")
  ring.modeled = { { kind = "procStat", stats = { STR = 50 }, duration = 10, rate = { chance = 5, icd = 0 } } }
  local ctx2 = Ev.Context(p, { targetOffset = 0 })
  local lambda = M.ProcRate({ chance = 5 }, M.HitsFor(11, (function() local _, i = M.DPS(ctx2.state, ctx2) return i.landed end)()))
  T.Near(ctx2.base.dpsInfo.procStats.STR, 50 * (1 - math.exp(-lambda * 10)), 1e-9)
  local plain = Ev.Context(fixture(), { targetOffset = 0 })
  T.Ok(ctx2.base.dps > plain.base.dps, "it adds DPS")
end)

T.Test("M4: a proc whose rate the game hides: counted at once a minute, confidence says so", function()
  local p = fixture()
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local ring = { link = "item:1", itemID = 1, name = "Ring of Zaps", loaded = true, equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0,
    canUse = true, effects = {}, stats = { ITEM_MOD_STAMINA_SHORT = 5 },
    modeled = { IE.Model("Chance on hit: Blasts the enemy for 80 Fire damage.", 1) } }
  local res = Ev.Compare(ctx, ring)
  local found
  for _, r in ipairs(res.reasons) do if r:find("proc rate assumed") then found = r end end
  T.Ok(found, "the reason: " .. table.concat(res.reasons, "; "))
  T.Ok(res.confidence ~= "high", "not high")
  T.Ok(res.best.dps > 0, "a damage proc adds DPS: " .. tostring(res.best.dps))
end)

T.Test("M4 in game (mock): Stormstrike and Windfury scanned; /eqn measure against the damage meter", function()
  MOCK.Reset()
  MOCK.windfury = true
  local ns4 = LoadAddon()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  MOCK.Fire("ADDON_LOADED", "EquipThisNext"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  local A = ns4.profile.abilities
  T.Ok(A.spells[17364] and A.spells[17364].desc:find("100%% weapon damage"), "Stormstrike's description")
  T.Eq(A.spells[17364].cooldownText, "8 sec cooldown")
  T.Eq(A.imbues[16].enchantID, 283); T.Eq(A.imbues[16].castSpell, 8232, "your Windfury Weapon rank")
  local ctx = ns4.Context()
  T.Ok(ctx.abilities.imbue and ctx.abilities.imbue.ap == 104, "Windfury's attack power from the description")
  for _, c in ipairs({ "abilities", "model", "measure" }) do
    PRINTS = {}; SlashCmdList.EQUIPTHISNEXT(c)
    T.Ok(#PRINTS > 0, "/eqn " .. c)
  end
  T.Ok(table.concat(PRINTS, " "):find("no finished fight"), "measure before any fight")
  -- a fight whose split matches the model: Windfury is confirmed
  local parts = ctx.base.dpsInfo.parts
  local by = {}
  for _, part in ipairs(parts) do by[part.name] = part.dps end
  MOCK.meter = { duration = 100, spells = { [6603] = by["auto attack"] * 90, [17364] = by["Stormstrike"] * 90,
    [439440] = by["Windfury 1"] * 90, [8134] = 500 } }
  MOCK.inCombat = true
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("measure")
  T.Ok(table.concat(PRINTS, " "):find("hidden in combat"), "not in combat")
  MOCK.inCombat = false
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("measure")
  local out = table.concat(PRINTS, "\n")
  T.Ok(out:find("Windfury 1: model %d+%%, measured %d+%% %- agrees"), out)
  T.Ok(out:find("Lightning Shield"), "spells not modelled are listed")
  T.Eq(ns4.db.confirmed["Windfury 1"], true, "confirmed")
  T.Eq(#ns4.db.measurements, 1, "kept for the dump")
  T.Eq(ns4.errors.count, 0, "no errors")
end)
