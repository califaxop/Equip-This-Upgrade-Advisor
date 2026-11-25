-- Milestone 6: mana, memory, benchmark command.
MOCK.Reset()
local ns = LoadAddon()
local Ev, SE = ns.Evaluator, ns.StatEngine

T.Test("M6: mana: a healer's rotation is cast as often as the mana allows; Intellect, Spirit and MP5 count then", function()
  local p = MakeClassProfile(ns, "PRIEST", "Holy")
  local ctx = Ev.Context(p, { targetOffset = 3, maxLevel = 60 })
  local mi = ctx.base.manaInfo
  T.Ok(mi and mi.cost > 0, "the rotation costs mana")
  local v = p.stats.values
  T.Near(mi.available, v["manaMax.value"] / 180 + v["regen.casting"], 1e-9, "pool / 180 s + regen while casting")
  T.Ok(mi.limit < 1, "a healer casting all the time runs short: " .. mi.limit)
  local w = Ev.Weights(ctx)
  T.Ok(w.INT.hps > 0 and w.MP5.hps > 0 and w.SPI.hps > 0, string.format("INT %.3f MP5 %.3f SPI %.3f", w.INT.hps, w.MP5.hps or 0, w.SPI.hps))
  T.Ok(w.HEAL.hps > 0, "healing still counts")
  -- 15 mana per Intellect (Forever's paper doll constant)
  local s = SE.Apply(ctx.state, { INT = 10 }, ctx.talents)
  T.Near(s.manaMax - ctx.state.manaMax, 150, 1e-9)
  -- a longer fight: the pool matters less, regen more
  local long = Ev.Context(p, { targetOffset = 3, maxLevel = 60, fightLength = 600 })
  local wl = Ev.Weights(long)
  T.Ok(wl.MP5.hps / wl.INT.hps > w.MP5.hps / w.INT.hps, "MP5 gains on Intellect in a long fight")
end)

T.Test("M6: mana doesn't touch a warrior; a melee shaman's spells only", function()
  local ctx = Ev.Context(MakeClassProfile(ns, "WARRIOR", "Fury"), { targetOffset = 3, maxLevel = 60 })
  T.Eq(ctx.base.manaInfo, nil)
  local w = Ev.Weights(ctx)
  T.Eq(w.INT.dps or 0, 0, "Intellect: nothing for a warrior")
end)

T.Test("M6: memory: only your class's spells are kept", function()
  MOCK.Reset()
  local n2 = LoadAddon()
  local before = 0
  for _ in pairs(n2.GENERATED.spells) do before = before + 1 end
  local dropped = n2.AbilityInterpreter.PruneToClass("SHAMAN")
  local after = 0
  for _, d in pairs(n2.GENERATED.spells) do after = after + 1; T.Ok(math.floor(d.classMask / 64) % 2 == 1, d.name) end
  T.Eq(before - after, dropped)
  T.Ok(after < before / 4, string.format("%d of %d spells kept", after, before))
  for _, d in pairs(n2.GENERATED.physical) do T.Ok(d.classes.SHAMAN, "physical: shaman only") end
  T.Eq(n2.AbilityInterpreter.PruneToClass("SHAMAN"), 0, "once")
end)

T.Test("M6 in game (mock): pruned at login; /eqn bench and /eqn fight", function()
  MOCK.Reset()
  local n3 = LoadAddon()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  MOCK.Fire("ADDON_LOADED", "EquipThisNext"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  T.Eq(n3.GENERATED.prunedTo, "SHAMAN")
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("bench")
  local out = table.concat(PRINTS, "\n")
  T.Ok(out:find("comparisons") and out:find("memory"), out)
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("fight 300")
  T.Eq(n3.db.fightLength, 300)
  T.Eq(n3.errors.count, 0)
end)

T.Test("M6: a rotation measured in your fights isn't mana-limited (you cast that much there)", function()
  local p = MakeClassProfile(ns, "PRIEST", "Holy")
  local ctx = Ev.Context(p, { targetOffset = 3, maxLevel = 60 })
  local rec = { key = Ev.RotationKey(p), level = 60, duration = 100, parts = {}, other = {}, healing = {} }
  for name, r in pairs(ctx.rotation.rates) do
    rec.healing[name] = r * ns.SpellModel.PerCast(ctx.spells[name], ctx.state, ctx) * 100
  end
  local m = Ev.Context(p, { targetOffset = 3, maxLevel = 60, lastMeasurement = rec })
  T.Eq(m.rotation.source, "measured")
  T.Eq(m.base.manaInfo, nil, "no mana limit")
end)
