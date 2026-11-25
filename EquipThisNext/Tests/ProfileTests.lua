-- CharacterProfile (pure Lua): item links, sets, talent points, validation, fingerprints.
MOCK.Reset()
local ns = LoadAddon()
local P, Item = ns.CharacterProfile, ns.ItemAPI

T.Test("ParseLink: full link, item string, empty fields, junk", function()
  local a = Item.ParseLink("|cff0070dd|Hitem:1002:1897:0:0:0:0:0:0:42|h[Axe]|h|r")
  T.Eq(a.itemID, 1002, "id"); T.Eq(a.enchantID, 1897, "enchant"); T.Eq(#a.gemIDs, 0, "gems"); T.Eq(a.linkLevel, 42, "level")
  local b = Item.ParseLink("item:1003::::::::42")
  T.Eq(b.itemID, 1003, "id"); T.Eq(b.enchantID, nil, "no enchant")
  local c = Item.ParseLink("item:5:0:41:0:42:0:-12:7")
  T.Eq(c.gemIDs[1], 41, "gem 1"); T.Eq(c.gemIDs[2], 42, "gem 3 (2 is empty)"); T.Eq(c.suffixID, -12, "random suffix")
  T.Eq(Item.ParseLink("|Hspell:403|h[Lightning Bolt]|h"), nil, "not an item")
  T.Eq(Item.ParseLink(nil), nil, "nil")
  T.Eq(Item.ParseLink("item:0"), nil, "item 0")
end)

T.Test("CountSets counts worn pieces per set", function()
  local eq = { slots = { [11] = { setID = 77 }, [12] = { setID = 77 }, [1] = { setID = 12 }, [5] = { empty = true } } }
  local sets = P.CountSets(eq)
  T.Eq(sets[77].count, 2, "set 77"); T.Eq(sets[12].count, 1, "set 12")
  T.Eq(sets[77].slots[1], 11, "slots sorted")
end)

T.Test("SumTreePoints adds ranks per tree and finds the main one", function()
  local t = { trees = { { groupID = 1, name = "A" }, { groupID = 2, name = "B" } },
    nodes = { { groupID = 1, rank = 2 }, { groupID = 2, rank = 5 }, { groupID = 2, rank = 1 }, { groupID = 1, rank = 0 } } }
  P.SumTreePoints(t)
  T.Eq(t.trees[1].points, 2, "A"); T.Eq(t.trees[2].points, 6, "B"); T.Eq(t.totalPoints, 8, "total"); T.Eq(t.primaryTree, "B", "main")
end)

local function good()
  local p = P.New()
  p.identity = { class = "SHAMAN", level = 42 }
  p.equipment.slots[1] = { itemID = 1001, loaded = true, stats = { ITEM_MOD_STAMINA_SHORT = 12 }, gemIDs = {} }
  p.equipment.slots[5] = { empty = true }
  p.meta.pendingItems = 0
  return p
end

T.Test("Validate: a good profile has no problems", function()
  T.Eq(#P.Validate(good()), 0, "problems")
end)

T.Test("Validate: an unloaded item must not have stats and must be requested", function()
  local p = good()
  p.equipment.slots[2] = { itemID = 2002, loaded = false, stats = {} }
  p.meta.pendingItems = 1
  local bad = table.concat(P.Validate(p), "; ")
  T.Ok(bad:find("not loaded but has stats"), "stats on an unloaded item: " .. bad)
  T.Ok(bad:find("not requested"), "not requested: " .. bad)
end)

T.Test("Validate: stats can't be both read and hidden; ranks within max", function()
  local p = good()
  p.stats.values["crit.melee"] = 5; p.stats.hidden["crit.melee"] = true
  p.talents.nodes = { { name = "Flurry", rank = 6, maxRank = 5 } }
  local bad = table.concat(P.Validate(p), "; ")
  T.Ok(bad:find("both read and hidden"), "hidden + read")
  T.Ok(bad:find("above its max rank"), "rank")
end)

T.Test("Fingerprint changes with gear, enchants, talents, level; not with stats", function()
  local p = good()
  local f0 = P.Fingerprint(p)
  p.stats.values.x = 1
  T.Eq(P.Fingerprint(p), f0, "stats don't matter")
  p.equipment.slots[1].enchantID = 5
  local f1 = P.Fingerprint(p); T.Ok(f1 ~= f0, "enchant")
  p.talents.nodes = { { nodeID = 9, rank = 1 } }
  local f2 = P.Fingerprint(p); T.Ok(f2 ~= f1, "talent")
  p.identity.level = 43
  T.Ok(P.Fingerprint(p) ~= f2, "level")
end)
