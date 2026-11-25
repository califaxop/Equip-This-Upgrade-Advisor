-- Scanners end to end against the mock client: login, items loading late, stats, talents, spells,
-- buffs, combat, gear and talent changes, and every /eqn command.
MOCK.Reset()
local ns = LoadAddon()
local function login()
  MOCK.Fire("ADDON_LOADED", "EquipThisNext")
  MOCK.Fire("PLAYER_LOGIN")
  MOCK.Fire("PLAYER_ENTERING_WORLD")
  MOCK.RunTimers()
  return ns.profile
end
local function issues(p, code)
  for _, i in ipairs(p.issues) do if i.code == code then return i end end
end

T.Test("login with items not loaded yet: recorded as loading, never as empty stats", function()
  local p = login()
  T.Ok(p, "profile built")
  T.Eq(p.meta.pendingItems, 5, "five worn items waiting")
  local helm = p.equipment.slots[1]
  T.Eq(helm.loaded, false, "helm not loaded"); T.Eq(helm.stats, nil, "no stats yet"); T.Eq(helm.itemID, 1001, "but its ID is known")
  T.Ok(MOCK.requested[1001] >= 1, "data requested")
  T.Ok(p.equipment.slots[2].empty, "neck really empty")
  T.Eq(p.meta.complete, false, "not complete")
  T.Ok(issues(p, "items-loading"), "says items are loading")
  T.Eq(issues(p, "invalid"), nil, "profile valid")
end)

T.Test("item data arrives: rescanned and complete", function()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  for id in pairs(MOCK.ITEMS) do MOCK.Fire("ITEM_DATA_LOAD_RESULT", id, true) end
  MOCK.RunTimers()
  local p = ns.profile
  T.Eq(p.meta.pendingItems, 0, "none waiting")
  T.Eq(p.equipment.slots[1].stats.ITEM_MOD_STAMINA_SHORT, 12, "helm stamina")
  T.Eq(p.equipment.slots[16].enchantID, 1897, "axe enchant from the link")
  T.Eq(p.equipment.slots[16].itemLevel, 42, "axe item level")
  T.Eq(p.sets[77].count, 2, "two set rings"); T.Eq(p.sets[77].name, "The Testing Rings", "set name")
  T.Eq(p.meta.complete, true, "complete")
  T.Eq(issues(p, "invalid"), nil, "valid")
end)

T.Test("character sheet values", function()
  T.Eq(ns.profile.stats.missing["speed.offHand"], nil, "no off-hand isn't 'unavailable' (regression: in game 0.1.0)")
  local v = ns.profile.stats.values
  T.Eq(v["crit.melee"], 6.2, "melee crit"); T.Eq(v["stat.AGI.effective"], 72, "agility")
  T.Eq(v["spellDamage.NATURE"], 25, "nature spell damage (school 4)")
  T.Eq(v["resist.NATURE.effective"], 15, "nature resistance (index 3)")
  T.Eq(v["ratingBonus.CR_HIT_MELEE"], 2, "hit from rating"); T.Eq(v["defense.base"], 210, "defense skill")
  T.Near(v["critFromStat.AGI"], 72 / 20 / 100, 1e-12, "crit from agility, the game's own conversion")
  T.Eq(ns.profile.stats.text["power.token"], "MANA", "power token")
  T.Ok(ns.profile.stats.missing["rating.CR_ARMOR_PENETRATION"], "an undefined rating constant is reported, not guessed")
  local w = ns.profile.stats.weaponSkills[16]
  T.Eq(w.name, "Two-Handed Axes", "weapon skill line"); T.Eq(w.rank, 205, "weapon skill")
end)

T.Test("talents, spells and buffs", function()
  local t = ns.profile.talents
  T.Eq(t.readable, true, "readable")
  T.Eq(t.trees[1].name, "Elemental", "trees in the game's order"); T.Eq(t.trees[2].points, 8, "Enhancement points")
  T.Eq(t.totalPoints, 9, "total"); T.Eq(t.primaryTree, "Enhancement", "main tree")
  local flurry
  for _, n in ipairs(t.nodes) do if n.name == "Flurry" then flurry = n end end
  T.Eq(flurry.rank, 3, "Flurry rank"); T.Eq(flurry.maxRank, 5, "Flurry max"); T.Eq(flurry.spellID, 16253, "Flurry spell")
  T.Eq(flurry.groupID, 11657, "a talent in several groups goes to its tree, not its first group (regression: in game 0.1.0)")
  T.Eq(t.trees[1].points + t.trees[2].points + t.trees[3].points, t.totalPoints, "every point in a tree")
  T.Eq(t.trees[2].spentByGame, 8, "the game's own count agrees")
  T.Eq(issues(ns.profile, "talents-mismatch"), nil, "no mismatch")
  T.Eq(ns.profile.spells.count, 3, "spells"); T.Eq(ns.profile.spells.known[403], "Lightning Bolt (Rank 4)", "rank text kept")
  T.Eq(ns.profile.buffs.helpful[1].name, "Lightning Shield", "buff")
end)

T.Test("combat: no scanning; forced scan keeps the last readable stats, marked stale", function()
  MOCK.inCombat, MOCK.statsSecret, MOCK.aurasSecret = true, true, true
  local before = ns.CharacterScanner.scans
  MOCK.Fire("UNIT_STATS", "player"); MOCK.RunTimers()
  T.Eq(ns.CharacterScanner.scans, before, "no scan in combat")
  T.Eq(ns.CharacterScanner.waitingForCombat, true, "waits for combat to end")
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("status")
  T.Ok(table.concat(PRINTS, "\n"):find("now: in combat true; stats hidden true %(crit reads hidden%)"), "status shows combat live: " .. table.concat(PRINTS, " | "))
  local p = ns.CharacterScanner.Refresh(true)
  T.Eq(p.stats.restricted, true, "restricted"); T.Eq(p.stats.stale, true, "stale copy")
  T.Eq(p.stats.values["crit.melee"], 6.2, "last readable crit kept")
  T.Eq(p.buffs.restricted, true, "auras not read (and no error)")
  T.Eq(ns.errors.count, 0, "no errors caught")
  MOCK.inCombat, MOCK.statsSecret, MOCK.aurasSecret = false, false, false
  MOCK.Fire("PLAYER_REGEN_ENABLED"); MOCK.RunTimers()
  T.Eq(ns.profile.stats.stale, nil, "fresh after combat")
end)

T.Test("gear change: new item loading, fingerprint changes", function()
  local fp = ns.profile.meta.fingerprint
  MOCK.ITEMS[1007] = { "Trinket of Later", "INVTYPE_TRINKET", 4, 0, 3, 45, nil, { ITEM_MOD_SPIRIT_SHORT = 7 } }
  MOCK.WORN[13] = "|cff0070dd|Hitem:1007::::::::42|h[Trinket of Later]|h|r"
  MOCK.Fire("PLAYER_EQUIPMENT_CHANGED", 13, false); MOCK.RunTimers()
  T.Eq(ns.profile.meta.pendingItems, 1, "trinket loading")
  T.Ok(ns.profile.meta.fingerprint ~= fp, "fingerprint changed")
  MOCK.cached[1007] = true
  MOCK.Fire("GET_ITEM_INFO_RECEIVED", 1007, true); MOCK.RunTimers()
  T.Eq(ns.profile.equipment.slots[13].stats.ITEM_MOD_SPIRIT_SHORT, 7, "trinket read")
end)

T.Test("talent change invalidates the talent cache", function()
  MOCK.TALENTS[3].rank = 5
  MOCK.Fire("TRAIT_CONFIG_UPDATED", 77); MOCK.RunTimers()
  T.Eq(ns.profile.talents.trees[2].points, 10, "new Enhancement points")
end)

T.Test("every /eqn command runs without errors", function()
  ns.Database.Load()
  for _, c in ipairs({ "", "status", "char", "stats", "stats crit", "gear", "item 16", "item", "talents", "talents all", "buffs",
    "spells", "spells bolt", "api", "api all", "scan", "dump", "debug", "debug" }) do
    PRINTS = {}
    SlashCmdList.EQUIPTHISNEXT(c)
    T.Ok(#PRINTS > 0, "/eqn " .. c .. " printed something")
    for _, line in ipairs(PRINTS) do T.Ok(not line:find("error:"), "/eqn " .. c .. ": " .. line) end
  end
  T.Ok(EquipThisNextDB.snapshots["Thrall-Forever"].profile.identity.class == "SHAMAN", "dump saved")
  PRINTS = {}; SlashCmdList.EQUIPTHISNEXT("status")
  local all = table.concat(PRINTS, "\n")
  T.Ok(all:find("all 17 match"), "slot numbers verified against the client")
  T.Ok(all:find("all registered"), "events registered")
  T.Eq(ns.errors.count, 0, "no errors caught")
end)

T.Test("no talent configuration: reported, profile incomplete", function()
  MOCK.noTalents = true
  ns.Cache.Invalidate("talents")
  local p = ns.CharacterScanner.Refresh(true)
  T.Ok(issues(p, "talents-unreadable"), "issue raised"); T.Eq(p.meta.complete, false, "incomplete")
  MOCK.noTalents = nil
end)

T.Test("an event the client doesn't know is recorded, the addon still works", function()
  MOCK.Reset()
  MOCK.unknownEvents = { COMBAT_RATING_UPDATE = true }
  local ns2 = LoadAddon()
  MOCK.unknownEvents = nil
  T.Ok(ns2.Events.failed.COMBAT_RATING_UPDATE, "recorded")
  MOCK.Fire("ADDON_LOADED", "EquipThisNext"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  T.Ok(ns2.profile and ns2.profile.identity.class == "SHAMAN", "scanned anyway")
end)
