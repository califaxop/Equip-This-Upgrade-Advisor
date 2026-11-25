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
  T.Near(ctx.talents.flurry.haste, 0.12, 1e-9, "Flurry 2/5: 12% on Forever (seen in game)")
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

T.Test("the same item, equipped: no comparison; a weapon without your weapon's speed: says so", function()
  local p = fixture()
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local worn = p.equipment.slots[10]
  local res = Ev.Compare(ctx, worn)
  T.Eq(res.options[1].status, "equipped", "equipped")
  local axe = Ev.Compare(ctx, { link = "x", loaded = true, equipLoc = "INVTYPE_2HWEAPON", stats = {} })
  T.Eq(axe.status, "unknown", "the fixture (a 0.1.0 dump) has no weapon speed: not guessed")
end)

-- milestone 3: the fixture with what 0.3.0 reads from tooltips (Rage of the Storm: 3.60 speed)
local function fixture3()
  local p = fixture()
  local mh = p.equipment.slots[16]
  mh.weapon = { dps = mh.stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT, speed = 3.6 }
  p.stats.skillByLine = { [160] = 209, [44] = 205, [54] = 210 }   -- 2H maces (sheet), axes, maces
  return p
end
-- I'lalai Flayer as the game shows it: one-hand axe, 52 - 97 damage, speed 2.60, 28.7 DPS, +4 Str +3 Agi +8 Sta
local FLAYER = { link = "item:279887", itemID = 279887, name = "I'lalai Flayer", loaded = true, equipLoc = "INVTYPE_WEAPON",
  classID = 2, subclassID = 0, canUse = true, effects = {},
  stats = { ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 8, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 28.65 },
  weapon = { dps = 28.65, speed = 2.6 } }

T.Test("the swing's flat part: 2 weapon damage from the ring (the sheet minus weapon and AP)", function()
  local s = SE.Baseline(fixture3())
  T.Near(s.flat, 2, 0.01, "flat")
  T.Eq(s.speed, 3.6, "the weapon's own speed")
end)

T.Test("a one-hander for a two-hander: the new swing from its damage and speed, its skill, no off-hand in bags", function()
  local p = fixture3()
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local res = Ev.Compare(ctx, FLAYER)
  T.Eq(res.status, "ok", "evaluated")
  local o = res.best
  T.Ok(o.notes[1]:find("empty off%-hand"), "says the off-hand is empty: " .. tostring(o.notes[1]))
  local s = SE.Apply(ctx.state, o.delta, ctx.talents, { mh = { dps = 28.65, speed = 2.6, subclass = 0 }, oh = false, shield = false })
  -- AP: 502 - 2 x 16 (Rage's Str) + 2 x 4 (Flayer's Str) = 478; swing = (28.65 + 478/14) x 2.6 + 2
  T.Near(s.AP, 478, 1e-9, "AP")
  T.Near(s.swing, (28.65 + 478 / 14) * 2.6 + 2, 1e-4, "swing (the flat part is 2.0000035: the game gives the speed as 3.6000001)")
  T.Eq(s.weaponSkill, 205, "axe skill")
  T.Ok(o.dps < 0, "a 2.6 one-hander loses auto-attack DPS to the 3.6 two-hander here")
  T.Eq(o.removed[1].name, "Rage of the Storm", "replaces the two-hander")
end)

T.Test("with a shield in your bags: the one-hander is paired with it; block counts with a shield only", function()
  local p = fixture3()
  local shield = { link = "item:6001", itemID = 6001, name = "Savage Boar's Guard", loaded = true, equipLoc = "INVTYPE_SHIELD",
    classID = 4, subclassID = 6, canUse = true, effects = {}, shieldBlock = 12,
    stats = { RESISTANCE0_NAME = 1100, ITEM_MOD_STAMINA_SHORT = 6 } }
  p.bags = { shield }
  local ctx = Ev.Context(p, { targetOffset = 0 })
  T.Eq(ctx.state.hasShield, false, "no shield now: the sheet's 4.8% block isn't counted")
  local res = Ev.Compare(ctx, FLAYER)
  T.Ok(res.best.notes[1]:find("Savage Boar's Guard"), "paired with the shield: " .. tostring(res.best.notes[1]))
  T.Ok(res.best.ehp > 5, "a shield's armor and block raise EHP a lot: " .. tostring(res.best.ehp))
  -- the shield itself, while wielding a two-hander: needs a one-hander from the bags
  local r2 = Ev.Compare(ctx, shield)
  T.Eq(r2.status, "none", "no one-hander in the bags")
  p.bags = { FLAYER }
  local r3 = Ev.Compare(Ev.Context(p, { targetOffset = 0 }), shield)
  T.Eq(r3.status, "ok", "with the Flayer from the bags")
  T.Ok(r3.best.notes[1]:find("I'lalai Flayer"), "says so")
end)

T.Test("set bonuses: breaking a 2-piece loses its bonus; completing one gains it", function()
  local p = fixture3()
  local bonus = { { pieces = 2, text = "+10 Attack Power." }, { pieces = 3, text = "Chance on hit: zaps the target." } }
  p.equipment.slots[6].setBonuses = bonus; p.equipment.slots[7].setBonuses = bonus
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local belt = { link = "item:7001", name = "Plain Belt", loaded = true, equipLoc = "INVTYPE_WAIST", canUse = true, effects = {},
    stats = { ITEM_MOD_STRENGTH_SHORT = 12, ITEM_MOD_STAMINA_SHORT = 10, RESISTANCE0_NAME = 136 } }
  local r = Ev.Compare(ctx, belt)
  T.Eq(r.best.setLost[1], "(2) +10 Attack Power.", "the 2-piece bonus is lost")
  T.Near(r.best.delta.AP, -10, 1e-9, "its 10 AP leaves")
  T.Ok(r.best.dps < 0, "same stats, minus the bonus: a downgrade")
  local helm = { link = "item:7002", name = "Scarlet Helm", loaded = true, equipLoc = "INVTYPE_HEAD", canUse = true, effects = {},
    setID = 163, setBonuses = bonus, stats = { ITEM_MOD_STAMINA_SHORT = 9 } }
  local r2 = Ev.Compare(ctx, helm)
  T.Eq(r2.best.setGained[1], "(3) Chance on hit: zaps the target.", "3-piece gained")
  T.Eq(r2.confidence, "low", "a bonus that isn't a stat: low confidence")
end)

T.Test("restrictions: can't use, level, unique", function()
  local ctx = Ev.Context(fixture3(), { targetOffset = 0 })
  local r = Ev.Compare(ctx, { link = "item:1", loaded = true, equipLoc = "INVTYPE_HEAD", canUse = false, stats = {} })
  T.Eq(r.status, "cantuse", "class / armor")
  local r2 = Ev.Compare(ctx, { link = "item:2", loaded = true, equipLoc = "INVTYPE_HEAD", canUse = true, minLevel = 45, stats = { ITEM_MOD_STAMINA_SHORT = 20 }, effects = {} })
  T.Eq(r2.notes[1], "usable at level 45", "still compared, with a note")
  local eq = ctx.profile.equipment.slots
  local r3 = Ev.Compare(ctx, { link = "item:x274614", itemID = 274614, unique = true, loaded = true, equipLoc = "INVTYPE_FINGER", canUse = true, stats = { ITEM_MOD_STAMINA_SHORT = 9 }, effects = {} })
  local statuses = {}
  for _, o in ipairs(r3.options) do statuses[o.slot] = o.status end
  T.Eq(statuses[12], "unique", "can't add a second Knucklebone Ring next to the one in Ring 1")
  T.Eq(statuses[11], "ok", "can replace it")
end)

T.Test("enchants: the replaced item's enchant is carried (not lost), and its text is shown", function()
  local p = fixture3()
  p.equipment.slots[5].enchantText = "Enchanted: +3 Stamina"
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local chest = { link = "item:7003", name = "New Chest", loaded = true, equipLoc = "INVTYPE_CHEST", canUse = true, effects = {},
    stats = { RESISTANCE0_NAME = 106, ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 11 } }
  local r = Ev.Compare(ctx, chest)
  T.Eq(r.best.carry[1], "Enchanted: +3 Stamina", "named")
  T.Ok(math.abs(r.best.ehp) < 1e-9, "identical stats, the enchant carried: no change")
end)

T.Test("item text: speed, damage, block, set lines, enchant and set bonus stat parsing", function()
  local IT = ns.ItemText
  local tip = { left = { "I'lalai Flayer", "One-Hand", "52 - 97 Damage", "(28.7 damage per second)", "1100 Armor", "21 Block",
    "(2) Set: +10 Attack Power.", "(3) Set: Increases damage and healing done by magical spells and effects by up to 12." },
    right = { [2] = "Axe", [3] = "Speed 2.60" } }
  T.Eq(IT.Speed(tip), 2.6, "speed"); local a, b = IT.Damage(tip); T.Eq(a, 52, "min"); T.Eq(b, 97, "max")
  T.Eq(IT.ShieldBlock(tip), 21, "block")
  local sb = IT.SetBonuses(tip); T.Eq(#sb, 2, "two set lines"); T.Eq(sb[1].pieces, 2, "pieces")
  T.Eq(IT.ParseStatText(sb[1].text).AP, 10, "+10 AP")
  local sp = IT.ParseStatText(sb[2].text); T.Eq(sp.SP, 12, "spell dmg"); T.Eq(sp.HEAL, 12, "healing")
  local e = IT.ParseStatText("Enchanted: +3 Agility and +3 Strength"); T.Eq(e.AGI, 3, "agi"); T.Eq(e.STR, 3, "str")
  T.Eq(IT.ParseStatText("+5 All Resistances").RES_FIRE, 5, "all res")
  T.Eq(IT.ParseStatText("Chance on hit: zaps the target."), nil, "not a stat")
  T.Eq(IT.ParseStatText("Improves your chance to get a critical strike by 1%.").CRIT_PCT, 1, "crit %")
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
  T.Near(ctx.talents.flurry.haste, ({ 10, 12, 20, 25, 30 })[MOCK.TALENTS[3].rank] / 100, 1e-9, "Flurry at the mock's rank: Classic table, the description is not used")
  local tt = MOCK.MakeTooltip("|cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r")
  MOCK.tooltipHook(tt)
  T.Ok(tt.lines[1] and tt.lines[1]:find("DPS") and tt.lines[1]:find("EHP"), "tooltip line: " .. tostring(tt.lines[1]))
  -- (milestone 4: its "Wounds the target for 50 damage" is counted, at an assumed rate: medium)
  T.Ok(tt.lines[2] and tt.lines[2]:find("confidence medium"), "proc ring: medium confidence: " .. tostring(tt.lines[2]))
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
  T.Near(ctx.talents.flurry.haste, 0.12, 1e-9, "2/5 = 12% on Forever (seen in game on the buff), not 1% (regression: 0.2.0)")
  p.buffs.helpful = { { name = "Flurry", points = { 20 } } }
  local ctx2 = Ev.Context(p, { targetOffset = 0 })
  T.Near(ctx2.talents.flurry.haste, 0.20, 1e-9, "the live buff's value wins")
end)

T.Test("stat lines with decimals are stats, not effects (regression: the cloak's 0.5% crit line in 0.2.0)", function()
  T.Eq(#ns.ItemEffects.Uncounted({ "Equip: Improves your chance to get a critical strike by 0.5%." }), 0, "0.5%")
  T.Eq(#ns.ItemEffects.Uncounted({ "Equip: Reduces the mana cost of Flame Shock and Lightning Bolt by 5 Mana." }), 1, "a real effect stays")
end)

T.Test("in game (mock), milestone 3: weapon speed and enchant read from tooltips, bag pairing, sets, flat part", function()
  MOCK.Reset()
  local ns3 = LoadAddon()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  MOCK.BAGS = { [1] = "|cff0070dd|Hitem:1011::::::::42|h[Shield of Bags]|h|r" }
  MOCK.Fire("ADDON_LOADED", "EquipThisNext"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  local p = ns3.profile
  local axe = p.equipment.slots[16]
  T.Eq(axe.weapon.speed, 3.6, "speed from the tooltip's right side")
  T.Eq(axe.enchantText, "Enchanted: +5 Weapon Damage", "the enchant's own line (tooltip with vs without it)")
  T.Eq(#axe.effects, 0, "the enchant line isn't counted as the axe's own effect")
  T.Eq(p.sets[77].count, 2, "set pieces"); T.Eq(#p.equipment.slots[11].setBonuses, 2, "set bonuses read")
  T.Eq(#p.bags, 1, "the bag shield found")
  T.Eq(p.stats.skillByLine[43], 190, "sword skill scanned")
  local ctx = ns3.Context()
  T.Near(ctx.state.flat, 5, 1e-6, "flat part = the enchant's 5 weapon damage")
  local blade = "|cff0070dd|Hitem:1010::::::::42|h[Blade of Bags]|h|r"
  local tt = MOCK.MakeTooltip(blade)
  MOCK.tooltipHook(tt)
  local all = table.concat(tt.lines, " | ")
  T.Ok(all:find("DPS") and all:find("Shield of Bags"), "one-hander paired with the bag shield: " .. all)
  T.Ok(all:find("Axe of Testing"), "says it replaces the two-hander")
  T.Ok(all:find("with your enchant on it"), "the axe's enchant carries over")
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("compare " .. blade)
  local out = table.concat(PRINTS, "\n")
  T.Ok(out:find("the weapon itself"), "the weapon's own part is listed")
  T.Eq(ns3.errors.count, 0, "no errors")
end)

-- 0.3.1: what 0.3.0 got wrong in game (dump of the level 42 Shaman, and the tooltips seen)
T.Test("0.3.1: a weapon type you haven't trained: % at your current skill, today's % as a note (regression: Flayer -63%)", function()
  local p = fixture3()
  p.stats.skillByLine[44] = 180     -- axes 180 of 210 (the dump)
  local ctx = Ev.Context(p, { targetOffset = 0 })
  local res = Ev.Compare(ctx, FLAYER)
  local o = res.best
  local note, skillNote
  for _, n in ipairs(o.notes) do
    if n:find("trained up") then note = n end
    if n:find("weapon type is") then skillNote = n end
    T.Ok(#n <= 60, "short enough not to widen the tooltip: " .. n)
  end
  T.Ok(skillNote and skillNote:find("is 180") and skillNote:find("vs 210"), "says the skill: " .. tostring(skillNote))
  local today = tonumber(note:match("DPS ([%+%-]%d+%.%d)%%"))
  T.Ok(today and o.dps > today, "the main % is at the trained skill (" .. o.dps .. ") above today's (" .. tostring(today) .. ")")
  p.stats.skillByLine[44] = 210
  local trained = Ev.Compare(Ev.Context(p, { targetOffset = 0 }), FLAYER).best
  T.Near(o.dps, trained.dps, 1e-6, "same as an axe already at your best weapon skill (maces 210 here)")
  T.Ok(res.confidence ~= "low", "a skill to train isn't a reason for low confidence: " .. res.confidence)
end)

T.Test("0.3.1: '+2% block' on non-shield gear counts (regression: Quillord Mail Leggings)", function()
  local IT = ns.ItemText
  local lines = { "Equip: Increases your chance to block attacks with a shield by 2%." }
  local extra, used = IT.ExtraStats(lines, SD.Normalize({ RESISTANCE0_NAME = 300, ITEM_MOD_STAMINA_SHORT = 10 }))
  T.Eq(extra.BLOCK_PCT, 2, "2% block"); T.Eq(#used, 1, "the line is used")
  T.Eq(#ns.ItemEffects.Uncounted(lines), 0, "and not an uncounted effect")
  -- as Forever writes it, with the % also given as block rating (regression: 0.3.1 "confidence low")
  local fl = { "Equip: Increases your chance to Block attacks with a shield by 2.0%." }
  T.Eq(#ns.ItemEffects.Uncounted(fl), 0, "'Block', '2.0%': a stat line, not an effect")
  local e3 = IT.ExtraStats(fl, SD.Normalize({ ITEM_MOD_BLOCK_RATING_SHORT = 10 }))
  T.Eq(next(e3), nil, "given as block rating too: counted once")
  local e2 = IT.ExtraStats({ "Equip: Improves your chance to get a critical strike by 1%." }, SD.Normalize({ ITEM_MOD_CRIT_RATING_SHORT = 14 }))
  T.Eq(next(e2), nil, "a % already given by the item's rating isn't counted twice")
  local s = SE.Apply(SE.Baseline(fixture3()), { BLOCK_PCT = 2 }, nil)
  T.Near(s.block, SE.Baseline(fixture3()).block + 2, 1e-9, "block + 2")
end)

T.Test("0.3.1: an active set bonus ('Set:' without its count) is read (regression: Scarlet 2-piece)", function()
  local tip = { left = { "Scarlet Leggings", "Scarlet Crusade (2/6)", "Set: +10 Shadow Resistance.",
    "(3) Set: +30 Attack Power against Undead.", "(4) Set: Taking damage has a 15% chance to grant Enraging Light.",
    "(5) Set: Improves your chance to hit by 1.0%.", "(6) Set: Taking damage while at or below 20% health grants you a shield." } }
  local b = ns.ItemText.SetBonuses(tip)
  T.Eq(#b, 5, "five bonuses"); T.Eq(b[1].pieces, 2, "the active one is the 2-piece"); T.Eq(b[1].text, "+10 Shadow Resistance.", "its text")
  T.Eq(b[5].pieces, 6, "sorted")
end)

T.Test("0.3.1: enchants written 'Stamina +3 and Armor +24' parse (as Forever writes them)", function()
  local s = ns.ItemText.ParseStatText("Stamina +3 and Armor +24")
  T.Ok(s, "parsed")
  local n = 0; for _ in pairs(s or {}) do n = n + 1 end
  T.Eq(n, 2, "two stats")
end)

T.Test("0.3.1: effects that touch neither DPS nor EHP don't lower confidence (regression: Whitemane's Chapeau)", function()
  local p = fixture3()
  local hat = { link = "item:7720", itemID = 7720, name = "Whitemane's Chapeau", loaded = true, equipLoc = "INVTYPE_HEAD",
    classID = 4, subclassID = 1, canUse = true, stats = { ITEM_MOD_STAMINA_SHORT = 9, RESISTANCE0_NAME = 60 },
    effects = { "Equip: Reduces the cast time of spells and effects that revive targets by 20%." } }
  local res = Ev.Compare(Ev.Context(p, { targetOffset = 0 }), hat)
  T.Ok(res.confidence ~= "low", "not low: " .. tostring(res.confidence))
  hat.effects = { "Chance on hit: Blasts the enemy for 80 Fire damage." }
  T.Eq(Ev.Compare(Ev.Context(p, { targetOffset = 0 }), hat).confidence, "low", "a damage proc still does")
end)
