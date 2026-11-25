-- Milestone 6 benchmark (offline, not part of the test run: tools/run_next_tests.py bench).
-- Times the work a tooltip and a comparison do, per spec, and the memory the addon's data takes.
MOCK.Reset()
collectgarbage("collect")
local before = collectgarbage("count")
local ns = LoadAddon()
collectgarbage("collect")
local loaded = collectgarbage("count") - before
local Ev = ns.Evaluator
local out = {}
local function P(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
P("addon loaded: %.0f KB of Lua memory (Generated.lua's tables included)", loaded)
local function time(n, fn)
  local t0 = os.clock()
  for _ = 1, n do fn() end
  return (os.clock() - t0) / n * 1000
end
-- counting model calls
local calls = 0
local perf = Ev.Performance
Ev.Performance = function(...) calls = calls + 1; return perf(...) end
local RING = { link = "item:1", itemID = 1, name = "Test Ring", loaded = true, equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0,
  canUse = true, effects = {}, modeled = {}, stats = { ITEM_MOD_STAMINA_SHORT = 10, ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_AGILITY_SHORT = 10,
    ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 10 } }
local MACE = { link = "item:2", itemID = 2, name = "Test Mace", loaded = true, equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 5,
  canUse = true, effects = {}, modeled = {}, stats = { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 50 }, weapon = { dps = 50, speed = 3.5 } }
P("%-24s %9s %9s %9s %8s %8s", "spec", "context", "ring", "weapon", "calls", "pvp+")
local worst = 0
for _, spec in ipairs({ { "SHAMAN", "Enhancement" }, { "WARRIOR", "Fury" }, { "ROGUE", "Assassination" }, { "HUNTER", "Marksmanship" },
  { "MAGE", "Frost" }, { "WARLOCK", "Destruction" }, { "PRIEST", "Holy" }, { "DRUID", "Restoration" }, { "PALADIN", "Holy" } }) do
  local p = MakeClassProfile(ns, spec[1], spec[2])
  local ctx
  local tc = time(20, function() ctx = Ev.Context(p, { targetOffset = 3, maxLevel = 60 }) end)
  calls = 0
  local tr = time(50, function() Ev.Compare(ctx, RING) end)
  local cr = calls / 50
  local tw = time(50, function() Ev.Compare(ctx, MACE) end)
  local pc = Ev.Context(p, { targetOffset = 3, maxLevel = 60, pvp = true })
  local tp = time(50, function() Ev.Compare(pc, RING) end)
  worst = math.max(worst, tr, tw)
  P("%-24s %7.2fms %7.2fms %7.2fms %8.0f %6.2fms", spec[1] .. " " .. spec[2], tc, tr, tw, cr, tp - tr)
end
P("slowest tooltip comparison: %.2f ms", worst)
-- what the data takes: Generated.lua loaded on its own, then each part
local function size(fn)
  collectgarbage("collect"); local a = collectgarbage("count")
  local keep = fn()
  collectgarbage("collect"); local b = collectgarbage("count")
  return b - a, keep
end
local gsize, g = size(function() local t = {}; assert(loadfile(ROOT .. "Data/Generated.lua"))("x", t); return t end)
P("Data/Generated.lua: %.0f KB", gsize)
for _, part in ipairs({ "spells", "itemProcs", "physical", "threat", "imbues" }) do
  local x = g.GENERATED[part]
  g.GENERATED[part] = nil
  collectgarbage("collect"); local a = collectgarbage("count")
  x = nil
  collectgarbage("collect")
  P("  .%s: %.0f KB", part, a - collectgarbage("count"))
end
-- after pruning to one class (at login)
collectgarbage("collect"); local m0 = collectgarbage("count")
ns.AbilityInterpreter.PruneToClass("SHAMAN")
collectgarbage("collect")
P("pruned to one class at login (shaman): %.0f KB freed", m0 - collectgarbage("count"))
local f = io.open(ROOT .. "Tests/bench_report.txt", "w"); f:write(table.concat(out, "\n") .. "\n"); f:close()
print(table.concat(out, "\n"))
