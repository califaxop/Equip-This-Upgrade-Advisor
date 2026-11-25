-- Milestone 4b: spells (damage and healing), the rotation learned from your fights, HPS.
MOCK.Reset()
local ns = LoadAddon()
local P, SE, Ev, IE, AI, S = ns.CharacterProfile, ns.StatEngine, ns.Evaluator, ns.ItemEffects, ns.AbilityInterpreter, ns.SpellModel

local function fixture()
  local p = ns.Database.Copy(FIXTURE_SHAMAN42)
  for _, n in ipairs(p.talents.nodes) do n.groupIDs = n.groupIDs or { n.groupID } end
  P.AssignTrees(p.talents); P.SumTreePoints(p.talents)
  p.calc = p.calc or {}
  local mh = p.equipment.slots[16]
  mh.weapon = { dps = mh.stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT, speed = 3.6 }
  mh.effects = { "Equip: Increases the damage dealt by your Stormstrike ability by 10%." }
  for _, it in pairs(p.equipment.slots) do if it.effects then it.modeled, it.effects = IE.Split(it.effects, it.itemID) end end
  p.stats.skillByLine = { [160] = 209, [44] = 180 }
  -- what the game showed in 0.4.0 for Stormstrike and Windfury; the shaman's spells (highest ranks known)
  p.abilities = { spells = { [17364] = { known = true, desc = "Instantly strike for 110% weapon damage", cooldownText = "8 sec cooldown" } },
    imbues = { [16] = { enchantID = 284, castSpell = 8235,
      desc = "Each hit has a 20% chance of granting you 2 extra attacks with 202 extra melee attack power." } },
    casts = {
      ["Earth Shock"] = { spellID = 10412, castText = "Instant", cooldownText = "6 sec cooldown" },
      ["Flame Shock"] = { spellID = 10447, castText = "Instant", cooldownText = "6 sec cooldown" },
      ["Lightning Bolt"] = { spellID = 10391, castText = "2.5 sec cast", manaText = "130 Mana" },
      ["Lightning Shield"] = { spellID = 8134, castText = "Instant" },
      ["Healing Wave"] = { spellID = 8005, castText = "3 sec cast", manaText = "200 Mana" },
    } }
  return p
end

-- the 0.4.2 measurement in game: 30 fights, 305 s in combat, 66,610 damage
local function realMeasurement(key)
  local T0 = 66610
  return { key = key, level = 42, duration = 305, fights = 30, total = T0,
    parts = { { name = "auto attack", measured = 0.31 * T0 }, { name = "Stormstrike", measured = 0.32 * 0.54 * T0 },
      { name = "Windfury 2", measured = 0.32 * 0.46 * T0 } },
    other = { { name = "Flame Shock", amount = 0.14 * T0 }, { name = "Earth Shock", amount = 0.13 * T0 },
      { name = "Lightning Shield", amount = 0.06 * T0 }, { name = "Lightning Bolt", amount = 0.04 * T0 } },
    healing = {} }
end

T.Test("M4b: spell amounts from the game's descriptions", function()
  local a = AI.SpellAmounts("Instantly sears the target with fire, causing 152 Fire damage immediately and 96 Fire damage over 12 sec.", "damage")
  T.Eq(a.direct, 152); T.Eq(a.dot, 96)
  local b = AI.SpellAmounts("Instantly shocks the target with concussive force, causing 168 to 180 Nature damage.", "damage")
  T.Eq(b.direct, 174); T.Eq(b.dot, nil)
  local c = AI.SpellAmounts("Burns the enemy for 96 Fire damage over 12 sec.", "damage")
  T.Eq(c.direct, nil, "a DoT only"); T.Eq(c.dot, 96)
  local h = AI.SpellAmounts("Heals a friendly target for 389 to 454.", "heal")
  T.Eq(h.direct, 421.5)
  local r = AI.SpellAmounts("Heals the target for 160 over 15 sec.", "heal")
  T.Eq(r.direct, nil); T.Eq(r.dot, 160)
end)

T.Test("M4b: your spells: Forever's coefficients, ranks' amounts at your level, tooltip cast times", function()
  local sp = AI.Spells(fixture())
  local fs, es, lb, ls = sp["Flame Shock"], sp["Earth Shock"], sp["Lightning Bolt"], sp["Lightning Shield"]
  T.Near(fs.direct.coef, 0.214, 1e-9); T.Near(fs.dot.coef, 0.1 * 4, 1e-9, "per tick x 4 ticks"); T.Eq(fs.dot.duration, 12)
  local d = ns.GENERATED.spells[10447]
  T.Near(fs.direct.avg, d.direct.base + d.direct.perLevel * (math.min(42, d.maxLevel) - d.baseLevel), 1e-9, "no description: base + per level up to the rank's max level")
  T.Eq(es.cooldown, 6); T.Eq(lb.cast, 2.5); T.Eq(lb.mana, 130)
  T.Near(ls.direct.coef, 0.267, 1e-9, "Lightning Shield: its lightning bolt's coefficient (26369)")
  T.Eq(sp["Healing Wave"].kind, "heal")
end)

T.Test("M4b: damage per cast: (amount + coef x spell damage) x hit x crit (x1.5), DoTs don't crit", function()
  local p = fixture()
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local s = ctx.state
  local fs = ctx.spells["Flame Shock"]
  local miss = math.max(1, 4 - (s.spellHit or 0))
  local crit = s.spellCrit / 100
  local want = (fs.direct.avg + 0.214 * s.SP) * (1 - miss / 100) * (1 + crit * 0.5) + (fs.dot.total + 0.4 * s.SP) * (1 - miss / 100)
  T.Near(S.PerCast(fs, s, ctx), want, 1e-9)
  local s2 = SE.Apply(s, { SP = 100 }, ctx.talents)
  T.Near(S.PerCast(fs, s2, ctx) - S.PerCast(fs, s, ctx), 100 * (0.214 * (1 - miss / 100) * (1 + crit * 0.5) + 0.4 * (1 - miss / 100)), 1e-6)
end)

T.Test("M4b: an Enhancement shaman's spells aren't guessed: counted once /eqn measure has learned them", function()
  local ctx = Ev.Context(fixture(), { targetOffset = 0 })
  T.Eq(ctx.rotation.source, "none")
  T.Eq(Ev.Weights(ctx).SP.dps or 0, 0, "spell damage: no value yet")
  local res = Ev.Compare(ctx, { link = "item:1", itemID = 1, name = "Ring", loaded = true, equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0,
    canUse = true, effects = {}, modeled = {}, stats = { ITEM_MOD_SPELL_POWER_SHORT = 10 } })
  local said
  for _, r in ipairs(res.reasons) do if r:find("/eqn measure") then said = true end end
  T.Ok(said, "the reason says how to count them")
end)

T.Test("M4b: the rotation learned from the real 30-fight measurement", function()
  local p = fixture()
  local key = Ev.RotationKey(p)
  local ctx = Ev.Context(p, { targetOffset = 0, lastMeasurement = realMeasurement(key) })
  local rot = ctx.rotation
  T.Eq(rot.source, "measured")
  T.Ok(rot.uptime > 0.3 and rot.uptime <= 1, "attacking part of the combat time: " .. rot.uptime)
  T.Ok(rot.strikes.Stormstrike > 1 / 8 * 0.7 and rot.strikes.Stormstrike < 1 / 8 * 1.3,
    string.format("Stormstrike %.1f/min: about once per cooldown (30 short fights: used at each pull)", rot.strikes.Stormstrike * 60))
  T.Ok(rot.rates["Earth Shock"] < 1 / 6, string.format("Earth Shock %.1f/min", rot.rates["Earth Shock"] * 60))
  T.Ok(rot.rates["Flame Shock"] and rot.rates["Lightning Bolt"] and rot.rates["Lightning Shield"], "every measured spell")
  -- the model now splits damage as the fights did
  local shares, total = {}, 0
  for _, part in ipairs(ctx.base.dpsInfo.parts) do shares[part.name] = part.dps; total = total + part.dps end
  local covered = 0.31 + 0.32 + 0.14 + 0.13 + 0.06 + 0.04
  T.Near(shares["Earth Shock"] / total, 0.13 / covered, 0.01, "Earth Shock's share")
  T.Near(shares["Stormstrike"] / total, 0.32 * 0.54 / covered, 0.01, "Stormstrike's share")
  T.Near(shares["auto attack"] / total, 0.31 / covered, 0.04, "auto attack's share (Windfury still from the model)")
  -- spell damage on gear now has a value for this shaman
  local w = Ev.Weights(ctx)
  T.Ok(w.SP.dps > 0, "spell damage counts: " .. w.SP.dps)
  -- (with 37% of the damage from spells, a point of spell damage is worth about a point of attack power)
  T.Ok(w.SP.dps > 0.5 * w.AP.dps and w.SP.dps < 2 * w.AP.dps, string.format("SP %.3f vs AP %.3f per point", w.SP.dps, w.AP.dps))
end)

T.Test("M4b: casters get a stated default rotation; healers get HPS", function()
  local p = fixture()
  p.talents.primaryTree = "Elemental"
  local ctx = Ev.Context(p, { targetOffset = 0 })
  T.Eq(ctx.melee, false); T.Eq(ctx.rotation.source, "assumed")
  local r = ctx.rotation.rates
  T.Ok((r["Lightning Bolt"] or 0) > 0, "Lightning Bolt fills")
  -- Earth and Flame Shock share one cooldown (category 19 in Forever's tables): only the better one
  T.Ok(((r["Earth Shock"] or 0) > 0) ~= ((r["Flame Shock"] or 0) > 0), "one shock on the shared cooldown")
  T.Eq(ctx.spells["Earth Shock"].category, ctx.spells["Flame Shock"].category, "same category")
  local busy = 0
  for name, r in pairs(ctx.rotation.rates) do local sp = ctx.spells[name]; busy = busy + r * math.max(sp.gcd, sp.cast) end
  T.Ok(busy <= 1 + 1e-9, "never more than all of the time: " .. busy)
  T.Ok(ctx.base.dps > 0 and not ctx.base.dpsInfo.table, "DPS from spells only")
  T.Ok(Ev.Weights(ctx).SP.dps > 0)
  p.talents.primaryTree = "Restoration"
  local h = Ev.Context(p, { targetOffset = 0 })
  T.Eq(h.healer, true); T.Ok(h.base.hps > 0, "HPS")
  T.Eq(Ev.MainMetric(h), "hps")
  T.Ok(Ev.Weights(h).HEAL.hps > 0, "healing power raises HPS")
  T.Ok(h.base.hpsInfo.manaPerSec > 0, "mana used: healing per mana")
end)

T.Test("M4b in game (mock): spells scanned; /eqn measure learns the rotation; /eqn model shows it", function()
  MOCK.Reset()
  MOCK.windfury = true
  local ns5 = LoadAddon()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  MOCK.Fire("ADDON_LOADED", "EquipThisNext"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  T.Ok(ns5.profile.abilities.casts["Lightning Bolt"], "Lightning Bolt read from the spellbook")
  local ctx = ns5.Context()
  local by = {}
  for _, part in ipairs(ctx.base.dpsInfo.parts) do by[part.name] = part.dps end
  MOCK.meter = { duration = 120, spells = { [6603] = by["auto attack"] * 80, [17364] = by["Stormstrike"] * 60, [439440] = by["Windfury 1"] * 80, [403] = 3000 } }
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("measure")
  local out = table.concat(PRINTS, "\n")
  T.Ok(out:find("learned how you fight"), out)
  T.Ok(ns5.db.rotation[Ev.RotationKey(ns5.profile)], "kept per class and spec")
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("model")
  out = table.concat(PRINTS, "\n")
  T.Ok(out:find("learned from your fights"), out)
  T.Ok(out:find("Lightning Bolt"), "Lightning Bolt is a DPS part now")
  T.Eq(ns5.errors.count, 0, "no errors")
end)

T.Test("0.5.1: one school's spell damage and spell penetration are stats (regression: Windweaver Staff 'confidence low')", function()
  local IT = ns.ItemText
  local lines = { "Equip: Your spells pierce 3 Magical Resistance.", "Equip: Increases damage done by Arcane spells and effects by up to 51." }
  T.Eq(#IE.Uncounted(lines), 0, "neither is an uncounted effect")
  local extra = IT.ExtraStats(lines, ns.StatDefs.Normalize({ ITEM_MOD_STAMINA_SHORT = 17, ITEM_MOD_SPELL_PENETRATION_SHORT = 3 }))
  T.Eq(extra.SP_ARCANE, 51); T.Eq(extra.SPELL_PEN, nil, "already in the stat table")
  -- if the stat table gives it as plain spell damage, it's moved to its school
  local e2 = IT.ExtraStats(lines, ns.StatDefs.Normalize({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 51 }))
  T.Eq(e2.SP_ARCANE, 51); T.Eq(e2.SP, -51)
  -- arcane spell damage does nothing for a shaman's nature and fire spells; nature does
  local p = fixture()
  local ctx = Ev.Context(p, { targetOffset = 0, lastMeasurement = realMeasurement(Ev.RotationKey(p)) })
  local function dps(d) return Ev.Performance(SE.Apply(ctx.state, d, ctx.talents), ctx).dps end
  T.Near(dps({ SP_ARCANE = 51 }), ctx.base.dps, 1e-9, "arcane: nothing")
  T.Ok(dps({ SP_NATURE = 51 }) > ctx.base.dps, "nature: more")
  T.Ok(dps({ SP = 51 }) > dps({ SP_NATURE = 51 }), "all schools: more than nature alone (Flame Shock is fire)")
  T.Near(dps({ SPELL_PEN = 3 }), ctx.base.dps, 1e-9, "spell penetration: targets have no resistance to pierce (assumed)")
end)
