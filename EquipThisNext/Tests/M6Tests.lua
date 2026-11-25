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

T.Test("0.8.1: caches have a limit (every hovered item was kept all session); /eqn dump clear", function()
  local C = ns.Cache
  C.Invalidate("item")
  for i = 1, C.MAX.item + 5 do C.Set("item", "item:" .. i, { i = i }) end
  T.Ok(C.Count("item") <= C.MAX.item, "at most " .. C.MAX.item .. ": " .. C.Count("item"))
  C.Set("item", "x", 1); C.Set("item", "x", 2)
  T.Eq(C.Get("item", "x"), 2, "a key set twice counts once")
  MOCK.Reset()
  local n4 = LoadAddon()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  MOCK.Fire("ADDON_LOADED", "EquipThisNext"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  SlashCmdList.EQUIPTHISNEXT("dump")
  local n = 0; for _ in pairs(n4.db.snapshots) do n = n + 1 end
  T.Eq(n, 1, "a snapshot")
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("dump clear")
  T.Eq(next(n4.db.snapshots), nil, "cleared")
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("bench")
  T.Ok(table.concat(PRINTS, " "):find("after a garbage collection"), table.concat(PRINTS, " "))
end)

T.Test("5.0: after each fight the rotation is learned from the damage meter; opt-in records are anonymous", function()
  MOCK.Reset()
  MOCK.windfury = true
  local n5 = LoadAddon()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  MOCK.Fire("ADDON_LOADED", "EquipThisNext"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  T.Eq(n5.db.learn, true, "learning on by default"); T.Eq(n5.db.share, false, "sharing off by default")
  local ctx = n5.Context()
  local by = {}
  for _, part in ipairs(ctx.base.dpsInfo.parts) do by[part.name] = part.dps end
  local key = n5.Evaluator.RotationKey(n5.profile)
  local function fight(id)
    MOCK.meter = { id = id, duration = 20, spells = { [6603] = by["auto attack"] * 18, [17364] = by["Stormstrike"] * 12, [403] = 400 } }
    MOCK.Fire("PLAYER_REGEN_ENABLED"); MOCK.RunTimers()
  end
  for i = 1, 7 do fight(100 + i) end
  T.Eq(n5.db.rotation[key], nil, "not yet: fewer than 8 fights")
  fight(108)
  local rot = n5.db.rotation[key]
  T.Ok(rot and rot.auto and rot.source == "measured", "learned after 8 fights")
  T.Ok(rot.rates["Lightning Bolt"], "Lightning Bolt learned")
  fight(108)
  T.Eq(n5.db.fightLog[key].fights, 8, "the same fight isn't counted twice")
  T.Eq(#n5.db.shared, 0, "nothing kept to share unless opted in")
  SlashCmdList.EQUIPTHISNEXT("share")
  fight(109)
  T.Eq(#n5.db.shared, 1)
  local text, n = n5.FightRecorder.ReportText()
  T.Eq(n, 1)
  T.Ok(text:find("EQT5|") and text:find("SHAMAN") and text:find("Lightning Bolt="), text)
  T.Ok(not text:find(tostring(UnitName and UnitName("player") or "Mocky")) and not text:find("Player%-"), "no name or GUID")
  T.Eq(n5.errors.count, 0)
end)
