-- Milestone 2 engine, on a real Forever character (level 42 Enhancement Shaman, FixtureShaman42).
-- First the model must rebuild what the game's character sheet says from the gear; then marginal
-- values and comparisons.
MOCK.Reset()
local ns = LoadAddon()
local P, SE, Ev, SD = ns.CharacterProfile, ns.StatEngine, ns.Evaluator, ns.StatDefs

local function fixture()
  local p = ns.Database.Copy(FIXTURE_SHAMAN42)
  for _, n in ipairs(p.talents.nodes) do n.groupIDs = n.groupIDs or { n.groupID } end   -- (0.1.0 dumps kept one group)
  P.AssignTrees(p.talents); P.SumTreePoints(p.talents)
  p.calc = p.calc or {}
  return p
end

T.Test("the model rebuilds the sheet's swing from gear: weapon DPS + attack power / 14 + flat weapon damage", function()
  local p = fixture()
  local s = SE.Baseline(p)
  local gear = SE.GearTotals(p)
  T.Near(s.swing, 259.0857, 1e-3, "sheet average swing")
  local rebuilt = gear.WEAPON_DPS * s.speed + s.AP / 14 * s.speed + gear.WEAPON_DMG
  T.Near(rebuilt, s.swing, 0.01, "rebuilt from 35.56 DPS x 3.6 + 502 AP / 14 x 3.6 + 2")
  T.Eq(gear.AP, p.stats.values["ap.pos"], "gear attack power = the sheet's AP bonus (73)")
end)

T.Test("the game's own conversions, per point, on this character", function()
  local s = SE.Baseline(fixture())
  T.Near(s.slope.apPerSTR, 2, 1e-9, "2 AP per Strength")
  T.Eq(s.slope.apPerAGI, 0, "no AP from Agility for a Shaman")
  T.Near(s.slope.critPerAGI, 0.03229200094938278 * 100 / 46, 1e-9, "crit % per Agility")
  T.Eq(s.slope.hpPerSTA, 10, "10 health per Stamina")
  T.Near(s.rating.CR_CRIT_MELEE, 0.5 / 7, 1e-9, "crit % per rating point from the sheet (7 rating = 0.5%)")
  T.Eq(s.rating.CR_HIT_MELEE, false, "no hit rating worn and no calculator: unknown, not guessed")
end)

T.Test("talents: Mental Dexterity 3/3 = all Intellect as AP (sheet-confirmed); Mental Quickness measured; Flurry 2/5", function()
  local ctx = Ev.Context(fixture(), { targetOffset = 0 })
  local byTalent = {}
  for _, c in ipairs(ctx.talents.conversions) do byTalent[c.talent .. ">" .. c.to] = c end
  T.Near(byTalent["Mental Dexterity>AP"].pct, 1, 1e-9, "MD")
  T.Near(byTalent["Mental Quickness>SP"].pct, 30 / 87, 1e-9, "MQ spell damage: (37 sheet - 7 gear) / 87 Int")
  T.Near(byTalent["Mental Quickness>HEAL"].pct, 30 / 87, 1e-9, "MQ healing: (50 - 20) / 87")
  T.Near(ctx.talents.flurry.haste, 0.15, 1e-9, "Flurry 2/5 (Classic table: no description in this fixture)")
  -- the sheet check behind Mental Dexterity: base AP = 2 x Str + (2 x level - 20) + 1 x Int
  local v = ctx.profile.stats.values
  T.Eq(v["ap.base"], 2 * 139 + (2 * 42 - 20) + 87, "base AP 429")
end)

T.Test("10 attack power adds exactly 10 / 14 x speed to the swing and the same share of DPS", function()
  local ctx = Ev.Context(fixture(), { targetOffset = 0 })
  local s2 = SE.Apply(ctx.state, { AP = 10 }, ctx.talents)
  T.Near(s2.swing - ctx.state.swing, 10 / 14 * 3.6, 1e-6, "swing (the game's speed is 3.6000001)")
  local p2 = Ev.Performance(s2, ctx)
  T.Near(p2.dps / ctx.base.dps, s2.swing / ctx.state.swing, 1e-9, "DPS scales with the swing (no crit change)")
  -- Intellect: through Mental Dexterity, 10 Int = 10 AP for damage
  local s3 = SE.Apply(ctx.state, { INT = 10 }, ctx.talents)
  T.Near(s3.AP - ctx.state.AP, 10, 1e-9, "10 Int -> 10 AP")
end)

T.Test("hit: worthless at the same level (5% hit already covers the 5% miss), valuable vs a boss", function()
  local p = fixture()
  p.calc.ratingPct = { CR_HIT_MELEE = 0.1, CR_HIT_SPELL = 0.1, CR_HIT_RANGED = 0.1 }
  local same = Ev.Context(p, { targetOffset = 0 })
  local boss = Ev.Context(p, { targetOffset = 3 })
  local function hitValue(ctx)
    return Ev.Weights(ctx).HIT_RATING.dps
  end
  T.Ok(math.abs(hitValue(same)) < 0.01, "same level: hit rating ~0 (only the 0.04% miss from weapon skill 209 vs 210 is left)")
  T.Ok(hitValue(boss) > 0.05, "boss: 1 hit rating > 0.05% DPS")
end)

T.Test("crit is worth more with Flurry than without", function()
  local p = fixture()
  local with = Ev.Weights(Ev.Context(p, { targetOffset = 0 })).CRIT_RATING.dps
  for _, n in ipairs(p.talents.nodes) do if n.name == "Flurry" then n.rank = 0 end end
  local without = Ev.Weights(Ev.Context(p, { targetOffset = 0 })).CRIT_RATING.dps
  T.Ok(with > without * 1.05, string.format("Flurry raises crit's value (%.4f vs %.4f)", with, without))
end)

T.Test("survivability: Stamina raises EHP in proportion to health; armor and resistances count", function()
  local ctx = Ev.Context(fixture(), { targetOffset = 0 })
  local w = Ev.Weights(ctx)
  T.Near(w.STA.ehp * 10, 100 / ctx.state.health * 100, 1e-6, "10 Sta = 100 health = 100/2285 more EHP")
  T.Ok(w.ARMOR.ehp > 0, "armor"); T.Ok(w.RES_NATURE.ehp > 0, "nature resistance")
  T.Eq(w.AP.ehp, 0, "attack power doesn't change EHP")
end)

T.Test("comparing a ring: it replaces the weaker ring, with the % per metric and each stat's part", function()
  local ctx = Ev.Context(fixture(), { targetOffset = 0 })
  local cand = { link = "item:9001", itemID = 9001, equipLoc = "INVTYPE_FINGER", loaded = true,
    stats = { ITEM_MOD_STAMINA_SHORT = 8, ITEM_MOD_ATTACK_POWER_SHORT = 20 }, effects = {} }
  local res = Ev.Compare(ctx, cand)
  T.Eq(res.status, "ok", "evaluated")
  T.Eq(#res.options, 2, "both ring slots tried")
  -- Knucklebone (7 Sta + 2 weapon damage = 7.2 AP worth) vs Determined Band (8 Sta + 9 AP): the new ring
  -- gains more over Knucklebone in DPS terms? 20 AP vs 2 dmg/swing (~7.8 AP): replaces Knucklebone
  T.Eq(res.best.slot, 11, "replaces Ring 1 (Knucklebone), the weaker for DPS")
  T.Ok(res.best.dps > 0, "DPS up"); T.Ok(res.best.ehp > 0, "EHP up (8 Sta vs 7)")
  T.Eq(res.metric, "dps", "melee spec: DPS decides the slot")
  local ap
  for _, part in ipairs(res.best.parts) do if part.stat == "AP" then ap = part end end
  T.Ok(ap and ap.dps > 0, "the AP part is shown")
end)

T.Test("the same item, equipped: no comparison; weapons wait for milestone 3", function()
  local p = fixture()
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local worn = p.equipment.slots[10]
  local res = Ev.Compare(ctx, worn)
  T.Eq(res.options[1].status, "equipped", "equipped")
  local axe = Ev.Compare(ctx, { link = "x", loaded = true, equipLoc = "INVTYPE_2HWEAPON", stats = {} })
  T.Eq(axe.status, "later", "two-hander later")
end)

T.Test("an item with a proc: listed as not counted, confidence low", function()
  local ctx = Ev.Context(fixture(), { targetOffset = 0 })
  local effects = ns.ItemEffects.Uncounted({ "Ring of Procs", "Chance on hit: Wounds the target for 50 damage.",
    "Equip: Improves your chance to get a critical strike by 1%.", "Equip: +12 Attack Power", "Use: Heals you for 300." })
  T.Eq(#effects, 2, "the proc and the use effect, not the two stat lines")
  local res = Ev.Compare(ctx, { link = "item:9002", loaded = true, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STAMINA_SHORT = 5 }, effects = effects })
  T.Eq(res.confidence, "low", "low")
end)

T.Test("a stat key the engine doesn't know is reported, not dropped silently", function()
  local s, unknown = SD.Normalize({ ITEM_MOD_STAMINA_SHORT = 3, ITEM_MOD_SOMETHING_NEW = 4 })
  T.Eq(s.STA, 3, "known"); T.Eq(unknown[1], "ITEM_MOD_SOMETHING_NEW", "unknown listed")
end)

T.Test("in game (mock): the tooltip line, /eqn model, sheet, weights, compare, target", function()
  MOCK.Reset()
  local ns2 = LoadAddon()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  MOCK.ITEMS[1008] = { "Ring of Procs", "INVTYPE_FINGER", 4, 0, 3, 45, nil, { ITEM_MOD_AGILITY_SHORT = 9 } }
  MOCK.cached[1008] = true
  MOCK.Fire("ADDON_LOADED", "EquipThisNext"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  T.Ok(ns2.profile.calc.ratingPct.CR_CRIT_MELEE, "calculators scanned")
  T.Near(ns2.profile.calc.ratingPct.CR_CRIT_MELEE, 1 / 14, 1e-9, "crit % per point from the game")
  T.Ok(ns2.profile.calc.glancing[0].chance, "glancing from the game")
  T.Ok(ns2.profile.calc.talentText[16253], "Flurry's description read")
  local ctx = ns2.Context()
  T.Near(ctx.talents.flurry.haste, ({ 10, 15, 20, 25, 30 })[MOCK.TALENTS[3].rank] / 100, 1e-9, "Flurry at the mock's rank: Classic table, the description is not used")
  local tt = MOCK.MakeTooltip("|cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r")
  MOCK.tooltipHook(tt)
  T.Ok(tt.lines[1] and tt.lines[1]:find("DPS") and tt.lines[1]:find("EHP"), "tooltip line: " .. tostring(tt.lines[1]))
  T.Ok(tt.lines[2] and tt.lines[2]:find("confidence low"), "proc ring: low confidence: " .. tostring(tt.lines[2]))
  MOCK.inCombat = true
  local tt2 = MOCK.MakeTooltip("|cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r")
  MOCK.tooltipHook(tt2)
  T.Eq(#tt2.lines, 0, "nothing computed in combat")
  MOCK.inCombat = false
  for _, c in ipairs({ "model", "sheet", "weights", "compare |cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r", "compare 1001",
    "target 3", "model", "target auto", "tooltip", "tooltip", "compare" }) do
    PRINTS = {}
    SlashCmdList.EQUIPTHISNEXT(c)
    T.Ok(#PRINTS > 0, "/eqn " .. c)
    for _, line in ipairs(PRINTS) do T.Ok(not line:find("error"), "/eqn " .. c .. ": " .. line) end
  end
  T.Eq(ns2.errors.count, 0, "no errors caught")
end)

T.Test("Flurry: never from its description (Forever's says 1%); the buff's value when seen, else Classic per rank", function()
  local p = fixture()
  p.calc.talentText = { [16256] = "Increases your attack speed by 1% for your next 3 swings after dealing a melee critical strike." }
  local ctx = Ev.Context(p, { targetOffset = 0 })
  T.Near(ctx.talents.flurry.haste, 0.15, 1e-9, "2/5 from the Classic table, not 1% (regression: 0.2.0 in game)")
  T.Ok(ctx.talents.unchecked > 0, "marked unconfirmed")
  p.buffs.helpful = { { name = "Flurry", points = { 20 } } }
  local ctx2 = Ev.Context(p, { targetOffset = 0 })
  T.Near(ctx2.talents.flurry.haste, 0.20, 1e-9, "the live buff's value wins")
end)

T.Test("stat lines with decimals are stats, not effects (regression: the cloak's 0.5% crit line in 0.2.0)", function()
  T.Eq(#ns.ItemEffects.Uncounted({ "Equip: Improves your chance to get a critical strike by 0.5%." }), 0, "0.5%")
  T.Eq(#ns.ItemEffects.Uncounted({ "Equip: Reduces the mana cost of Flame Shock and Lightning Bolt by 5 Mana." }), 1, "a real effect stays")
end)
