-- Talents: what a talent does to the value of stats, by its spell ID (locale-independent; names are
-- for reading). Only talents that change how stats turn into performance are listed: a talent that
-- adds flat crit or damage is already in the character sheet, which the engine starts from.
--
-- Effect kinds:
--   convert  { from, to, pctPerRank }   part of one stat counts as another (Intellect -> attack power)
--   flurry   { hastePerRank, swings }   after a melee crit, the next swings are faster
-- "check" says how the number is known: "sheet" = confirmed by rebuilding the character sheet from
-- gear in game, "text" = read from the talent's own description in game at run time (when given),
-- "source" = from a guide or another addon, not yet confirmed (lowers confidence).
local _, ns = ...
local TD = ns and ns.Module and ns.Module("TalentData") or {}

TD.BY_SPELL = {
  -- Shaman
  [415140] = { name = "Mental Dexterity", class = "SHAMAN", kind = "convert", from = "INT", to = { "AP" },
    pctPerRank = 1 / 3, check = "sheet",
    note = "3/3: all of Intellect as attack power. Level 42 sheet: base AP 429 = 2 x 139 Str + (2 x 42 - 20) + 87 Int." },
  [30812] = { name = "Mental Quickness", class = "SHAMAN", kind = "convert", from = "INT", to = { "SP", "HEAL" },
    measure = true, check = "sheet",
    note = "Intellect as spell damage and healing. Its share is measured from the sheet (sheet value minus gear) at run time." },
  [16256] = { name = "Flurry", class = "SHAMAN", kind = "flurry", hastePerRankDefault = { 10, 15, 20, 25, 30 }, swings = 3,
    buffName = "Flurry",
    -- Forever's own values where known: rank 1 from its data (buff spell 16257: 10), rank 2 seen on the
    -- buff in game (12, not Classic's 15). Ranks 3-5: Classic's, until seen.
    forever = { [1] = 10, [2] = 12 },
    note = "Attack speed after a critical strike, for the next 3 swings. The talent's description can't be used: on " ..
      "Forever its spell (16256) is a marker whose value is 1 (the in-game text says 1%), and the haste is on the buff " ..
      "spell (16257: 10% at rank 1 in Forever's data). So: the Flurry buff's own value when it's seen on you, else " ..
      "the Classic table (10/15/20/25/30%), marked unconfirmed." },
}
-- (spell IDs above are the ones Forever's talent nodes gave in the level-42 Shaman dump)

-- by class and name: the entries above, plus talents whose Forever spell ID hasn't been seen yet
-- (never guess an ID: these match by name until a dump shows the ID)
TD.BY_NAME = {
  ["WARRIOR:Flurry"] = { name = "Flurry", class = "WARRIOR", kind = "flurry", hastePerRankDefault = { 10, 15, 20, 25, 30 },
    swings = 3, buffName = "Flurry" },
}
for _, e in pairs(TD.BY_SPELL) do TD.BY_NAME[e.class .. ":" .. e.name] = e end
