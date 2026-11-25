-- Milestone 4c: threat (kept apart from EHP) and PvP (its own assumptions).
MOCK.Reset()
local ns = LoadAddon()
local P, SE, Ev, IE, TM, M = ns.CharacterProfile, ns.StatEngine, ns.Evaluator, ns.ItemEffects, ns.ThreatModel, ns.MeleeModel

local function fixture()
  local p = ns.Database.Copy(FIXTURE_SHAMAN42)
  for _, n in ipairs(p.talents.nodes) do n.groupIDs = n.groupIDs or { n.groupID } end
  P.AssignTrees(p.talents); P.SumTreePoints(p.talents)
  p.calc = p.calc or {}
  local mh = p.equipment.slots[16]
  mh.weapon = { dps = mh.stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT, speed = 3.6 }
  for _, it in pairs(p.equipment.slots) do if it.effects then it.modeled, it.effects = IE.Split(it.effects, it.itemID) end end
  p.stats.skillByLine = { [160] = 209 }
  p.abilities = { spells = { [17364] = { known = true, desc = "Instantly strike for 110% weapon damage", cooldownText = "8 sec cooldown" } },
    imbues = {}, casts = { ["Earth Shock"] = { spellID = 10412, castText = "Instant", cooldownText = "6 sec cooldown" } } }
  p.buffs = { helpful = {} }
  return p
end

T.Test("M4c: threat modifiers from Forever's tables: stances and forms by their passives, auras, class passives", function()
  local p = fixture()
  -- (this shaman's talents have one: listed, then left out to check the auras alone)
  local talentOnes = TM.Sources(p)
  local tal = talentOnes[1]
  T.Ok(tal and tal.source == "talent", "a talent that changes threat: " .. tostring(tal and tal.name))
  for _, n in ipairs(p.talents.nodes) do if tal and n.spellID and ns.GENERATED.threat[n.spellID] then n.rank = 0 end end
  p.buffs.helpful = { { name = "Defensive Stance", spellId = 71 } }
  local src = TM.Sources(p)
  T.Eq(#src, 1); T.Eq(src[1].name, "Defensive Stance Passive"); T.Eq(src[1].pct, 80)
  T.Near(TM.Multiplier(src, "Physical"), 1.8, 1e-9)
  p.buffs.helpful = { { name = "Dire Bear Form", spellId = 9634 } }
  T.Near(TM.Multiplier(TM.Sources(p), "Physical"), 2.15, 1e-9, "Bear Form (Passive2) +115%")
  p.buffs.helpful = { { name = "Righteous Fury", spellId = 25780 } }
  local rf = TM.Sources(p)
  T.Near(TM.Multiplier(rf, "Holy"), 1.9 * 1.33, 1e-9, "+90% Holy and +33% all, multiplied")
  T.Near(TM.Multiplier(rf, "Physical"), 1.33, 1e-9)
  p.buffs.helpful = {}
  p.identity.class = "ROGUE"
  T.Near(TM.Multiplier(TM.Sources(p), "Physical"), 0.71, 1e-9, "Rogue Passive -29%")
end)

T.Test("M4c: a tank gets threat per second (its own number, not part of EHP); the role setting overrides", function()
  local p = fixture()
  T.Eq(Ev.Context(p, { targetOffset = 0 }).tank, false, "Enhancement, no threat aura")
  p.buffs.helpful = { { name = "Righteous Fury", spellId = 25780 } }
  local ctx = Ev.Context(p, { targetOffset = 0 })
  T.Eq(ctx.tank, true, "a threat-raising aura")
  local want = 0
  for _, part in ipairs(ctx.base.dpsInfo.parts) do want = want + part.dps * TM.Multiplier(ctx.threat, part.school) end
  T.Near(ctx.base.tps, want, 1e-9)
  local tal = 1
  for _, x in ipairs(ctx.threat) do if x.source == "talent" then tal = tal * (1 + x.pct / 100) end end
  T.Near(ctx.base.tps, ctx.base.dps * 1.33 * tal, 1e-6, "all physical here: x1.33 and the talent's")
  T.Eq(Ev.Context(p, { targetOffset = 0, role = "notank" }).tank, false, "setting")
  p.buffs.helpful = {}
  T.Eq(Ev.Context(p, { targetOffset = 0, role = "tank" }).tank, true, "setting")
  local res = Ev.Compare(Ev.Context(p, { targetOffset = 0, role = "tank" }), { link = "item:1", itemID = 1, name = "Ring", loaded = true,
    equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0, canUse = true, effects = {}, modeled = {}, stats = { ITEM_MOD_STRENGTH_SHORT = 10 } })
  T.Ok(res.best.tps and res.best.tps > 0, "threat %")
  local L = ns.Tooltip.Lines(res)
  T.Ok(L[1]:find("Threat") and not L[1]:find("DPS"), "the tooltip shows threat for a tank: " .. L[1])
end)

T.Test("M4c: PvP: no glancing blows, 5% dodge, armor like yours, burst opens with cooldowns and use effects", function()
  local p = fixture()
  p.calc.armorEffect = { [42] = 0.24 }
  local ctx = Ev.Context(p, { targetOffset = 0, pvp = true })
  local pc = Ev.PvPContext(ctx)
  local t = M.Table(ctx.state, pc)
  T.Eq(t.glance, 0, "no glancing vs players"); T.Near(t.dodge, 5 + (210 - 209) * 0.04, 1e-9)
  local pv = ctx.pvpBase
  T.Eq(pv.armorReduction, 0.24, "your armor's reduction at your level (the game's calculator)")
  local p2 = Ev.Performance(ctx.state, pc)
  local sus = 0
  for _, part in ipairs(p2.dpsInfo.parts) do sus = sus + part.dps * ((part.school == "Physical") and 0.76 or 1) end
  T.Near(pv.sustained, sus, 1e-9)
  -- burst: Stormstrike used at once (6 s window, 8 s cooldown: once)
  local ss
  for _, part in ipairs(p2.dpsInfo.parts) do if part.name == "Stormstrike" then ss = part end end
  T.Ok(pv.burst > 0 and pv.burst < pv.sustained * 6 + ss.perCast, "burst")
  -- a use effect counts in full in a burst, its average in sustained
  local ring = p.equipment.slots[11]
  ring.modeled = { { kind = "useStat", stats = { AP = 200 }, duration = 20, cooldown = 120 } }
  local c2 = Ev.Context(p, { targetOffset = 0, pvp = true })
  local gainBurst, gainSus = c2.pvpBase.burst / pv.burst - 1, c2.pvpBase.sustained / pv.sustained - 1
  T.Ok(gainBurst > 3 * gainSus, string.format("burst +%.1f%% vs sustained +%.1f%%", gainBurst * 100, gainSus * 100))
  -- survival: no crushing blows from players, half magic
  local e = ns.SurvivalModel.EHP(ctx.state, pc)
  T.Eq(select(2, ns.SurvivalModel.EHP(ctx.state, pc)).table.crush, 0)
  T.Near(pv.ehp, e, 1e-9)
end)

T.Test("M4c: comparisons carry PvP numbers when asked; PvE numbers don't change", function()
  local p = fixture()
  local ring = { link = "item:1", itemID = 1, name = "Ring", loaded = true, equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0,
    canUse = true, effects = {}, modeled = {}, stats = { ITEM_MOD_STAMINA_SHORT = 10, ITEM_MOD_SPELL_PENETRATION_SHORT = 10 } }
  local a = Ev.Compare(Ev.Context(p, { targetOffset = 0 }), ring)
  local b = Ev.Compare(Ev.Context(p, { targetOffset = 0, pvp = true }), ring)
  T.Eq(a.best.pvp, nil); T.Ok(b.best.pvp and b.best.pvp.ehp, "PvP numbers")
  T.Near(a.best.dps or 0, b.best.dps or 0, 1e-9, "PvE unchanged")
  T.Ok(b.best.pvp.ehp > 0, "stamina: survival")
  local L = ns.Tooltip.Lines(b)
  local found
  for _, l in ipairs(L) do if l:find("PvP:") then found = l end end
  T.Ok(found and found:find("survival"), "a PvP line: " .. tostring(found))
end)

T.Test("M4c in game (mock): /eqn pvp, /eqn role, /eqn model, /eqn compare", function()
  MOCK.Reset()
  local ns6 = LoadAddon()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  MOCK.Fire("ADDON_LOADED", "EquipThisNext"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  local link = "|cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r"
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("pvp")
  T.Eq(ns6.db.pvp, true)
  local tt = MOCK.MakeTooltip(link); MOCK.tooltipHook(tt)
  local all = table.concat(tt.lines, " | ")
  T.Ok(all:find("PvP:"), all)
  SlashCmdList.EQUIPTHISNEXT("pvp")
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("role tank")
  T.Ok(table.concat(PRINTS, " "):find("tanking"), table.concat(PRINTS, " "))
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("model")
  local out = table.concat(PRINTS, "\n")
  T.Ok(out:find("threat") and out:find("PvP vs a player"), out)
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("compare " .. link)
  T.Ok(table.concat(PRINTS, "\n"):find("PvP: burst"), table.concat(PRINTS, "\n"))
  SlashCmdList.EQUIPTHISNEXT("role auto")
  T.Eq(ns6.errors.count, 0, "no errors")
end)
