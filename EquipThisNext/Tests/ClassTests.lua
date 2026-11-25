-- Milestone 5: every class and spec at level 60, offline (test characters: FixtureClass.lua).
MOCK.Reset()
local ns = LoadAddon()
local Ev = ns.Evaluator

local RING = { link = "item:1", itemID = 1, name = "Test Ring", loaded = true, equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0,
  canUse = true, effects = {}, modeled = {}, stats = { ITEM_MOD_STAMINA_SHORT = 10, ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_AGILITY_SHORT = 10,
    ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 10, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 20 } }

local report = {}
for class, trees in pairs(FOREVER_SPECS) do
  for _, tree in ipairs(trees) do
    T.Test("M5: " .. class .. " " .. tree .. ": evaluates, with a rotation, and sensible stat values", function()
      local p = MakeClassProfile(ns, class, tree)
      local ctx = Ev.Context(p, { targetOffset = 3, maxLevel = 60 })
      T.Ok(ctx, "a context")
      local kind = Ev.SpecKind(class, tree)
      local w = Ev.Weights(ctx)
      local function wv(stat, m) return (w[stat] and w[stat][m]) or 0 end
      if kind == "healer" then
        T.Ok((ctx.base.hps or 0) > 0, "HPS")
        T.Ok(wv("HEAL", "hps") > 0, "healing power raises HPS")
        T.Eq(wv("AP", "hps"), 0, "attack power: nothing for a healer")
      else
        T.Ok((ctx.base.dps or 0) > 0, "DPS: " .. tostring(ctx.base.dps) .. " " .. tostring(ctx.base.why and ctx.base.why.dps))
      end
      if kind == "melee" then
        T.Ok(wv("AP", "dps") > 0, "attack power counts")
        T.Ok(wv("STR", "dps") > 0, "strength counts")
        if class == "WARRIOR" or class == "ROGUE" then T.Eq(wv("SP", "dps"), 0, "spell damage: nothing") end
      elseif kind == "ranged" then
        T.Ok(wv("AGI", "dps") > wv("STR", "dps"), "agility over strength")
        T.Ok(wv("SP", "dps") < wv("AGI", "dps") / 10, "spell damage: next to nothing (Serpent Sting's share)")
      elseif kind == "caster" then
        T.Ok(wv("SP", "dps") > 0, "spell damage counts")
        T.Eq(wv("AP", "dps"), 0, "attack power: nothing")
        T.Eq(wv("STR", "dps"), 0, "strength: nothing")
      end
      local res = Ev.Compare(ctx, RING)
      T.Eq(res.status, "ok", "compares a ring")
      local rot = ctx.rotation
      local parts = {}
      for _, part in ipairs((ctx.base.dpsInfo or {}).parts or (ctx.base.hpsInfo or {}).parts or {}) do
        parts[#parts + 1] = string.format("%s %d%%", part.name, (part.dps or part.hps) / (ctx.base.dps or ctx.base.hps) * 100 + 0.5)
      end
      report[#report + 1] = string.format("%-9s %-14s %-7s rotation %-8s %s", class, tree, kind, tostring(rot.source) .. (rot.borrowed and "*" or ""),
        table.concat(parts, ", "):sub(1, 150))
    end)
  end
end
T.Test("M5: the report (every spec's model split)", function()
  table.sort(report)
  local f = io.open(ROOT .. "Tests/class_report.txt", "w")
  if f then f:write(table.concat(report, "\n") .. "\n"); f:close() end
  T.Eq(#report, 27, "27 specs")
end)

T.Test("M5: a hunter's better bow raises DPS through Auto Shot and Multi-Shot; a melee weapon barely matters", function()
  local p = MakeClassProfile(ns, "HUNTER", "Marksmanship")
  local ctx = Ev.Context(p, { targetOffset = 3, maxLevel = 60 })
  local bow = { link = "item:2", itemID = 2, name = "Better Bow", loaded = true, equipLoc = "INVTYPE_RANGED", classID = 2, subclassID = 2,
    canUse = true, effects = {}, modeled = {}, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 60 }, weapon = { dps = 60, speed = 3.0 } }
  local res = Ev.Compare(ctx, bow)
  T.Eq(res.status, "ok")
  T.Ok(res.best.dps > 5, "+10 ranged DPS: " .. tostring(res.best.dps))
  local s = ns.StatEngine.Apply(ctx.state, {}, ctx.talents, { rangedW = { dps = 60, speed = 3.0 } })
  T.Ok(s.rangedSwing > ctx.state.rangedSwing, "a bigger shot")
end)
