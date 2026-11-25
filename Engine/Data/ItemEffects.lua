-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- ItemEffects: which green tooltip lines of an item are just its stats (already counted from
-- C_Item.GetItemStats), which are effects the models count (IE.Model: procs, use effects, ability
-- bonuses, from milestone 4) and which they don't. An effect not counted is listed on the
-- comparison and lowers its confidence: it's never treated as zero without saying so. Pure Lua.
local _, ns = ...; ns = ns.Engine
local IE = ns and ns.Module and ns.Module("ItemEffects") or {}

-- lines that start an effect
IE.PREFIXES = { "^Equip:", "^Use:", "^Chance on hit:", "^Chance on Hit:" }
-- an "Equip:" line that is one of these is a stat the item's stat table already has
IE.STAT_LINES = {
  "^Equip: %+?%d+ [%a ]+$",                                  -- "Equip: +32 Attack Power"
  "^Equip: Increases attack power by %d+%.?$",
  "^Equip: %+%d+ Attack Power",
  "^Equip: Improves your chance to hit by %d+%.?%d*%%%.?$",
  "^Equip: Improves your chance to get a critical strike by %d+%.?%d*%%%.?$",
  "^Equip: Improves your critical strike rating by %d+%.?$",
  "^Equip: Improves your hit rating by %d+%.?$",
  "^Equip: Increases damage and healing done by magical spells and effects by up to %d+%.?$",
  "^Equip: Increases damage done by magical spells and effects by up to %d+%.?$",
  "^Equip: Increases healing done by spells and effects by up to %d+%.?$",
  "^Equip: Increases healing done by up to %d+ and damage done by up to %d+ for all magical spells and effects%.?$",
  "^Equip: Restores %d+ mana per 5 sec%.?$",
  "^Equip: Restores %d+ health per 5 sec%.?$",
  "^Equip: Increased Defense %+%d+%.?$",
  "^Equip: Increases your chance to dodge an attack by %d+%.?%d*%%%.?$",
  "^Equip: Increases your chance to parry an attack by %d+%.?%d*%%%.?$",
  "^Equip: Increases your chance to block attacks with a shield by %d+%.?%d*%%%.?$",
  "^Equip: Increases the block value of your shield by %d+%.?$",
  "^Equip: %+%d+ Weapon Damage%.?$",
  "^Equip: Increases damage done by %a+ spells and effects by up to %d+%.?$",
  "^Equip: Your spells pierce %d+ Magical Resistance%.?$",
  "^Equip: Decreases the magical resistances of your spell targets by %d+%.?$",
}

-- effects that change neither damage nor survivability (listed, but they don't lower confidence)
IE.IRRELEVANT = { "revive", "resurrect", "mana cost", "[Mm]ovement speed", "mount", "[Ff]ishing", "underwater", "breath",
  "threat", "Ghost Wolf", "[Ss]tealth detection", "gathering", "[Mm]ining", "[Hh]erbalism", "[Ss]kinning" }
function IE.IsIrrelevant(line)
  for _, p in ipairs(IE.IRRELEVANT) do if line:find(p) then return true end end
  return false
end

function IE.IsEffect(line)
  if type(line) ~= "string" then return false end
  for _, p in ipairs(IE.PREFIXES) do if line:find(p) then return true end end
  return false
end

function IE.IsStatLine(line)
  -- (case-blind: Forever writes "chance to Block attacks", Classic "block")
  local low = line:lower()
  for _, p in ipairs(IE.STAT_LINES) do if low:find(p:lower()) then return true end end
  return false
end

-- tooltip lines -> the effect lines not counted as stats
function IE.Uncounted(lines)
  local out = {}
  for _, l in ipairs(lines or {}) do
    if IE.IsEffect(l) and not IE.IsStatLine(l) then out[#out + 1] = l end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Milestone 4: effects the models count. IE.Model(line, itemID) -> a record, or nil (not counted):
--   { kind = "abilityPct", ability = "Stormstrike", pct = 10 }       "Increases the damage dealt by your X ability by N%"
--   { kind = "procDamage", avg = , school = , rate }                   "Chance on hit: Blasts the enemy for 80 Fire damage."
--   { kind = "procExtra", attacks = , rate }                           "Chance on hit: ... 1 extra attack"
--   { kind = "procStat", stats = { AP = 120 }, duration = , rate }     "Chance on hit: Increases your attack power by 120 for 10 sec."
--   { kind = "useStat", stats = , duration = , cooldown = }            "Use: Increases attack power by 260 for 20 sec. (2 Min Cooldown)"
-- rate = { chance = % per hit, ppm = procs a minute, icd = s, source = "game data" | "measured" | "assumed" }:
-- from the game's own tables (Data/Generated.lua), else measured on Warcraft Logs (MeasuredProcs),
-- else assumed to be once a minute (and said so).
IE.SCHOOLS = { Fire = true, Frost = true, Nature = true, Shadow = true, Arcane = true, Holy = true, Physical = true }
IE.ASSUMED_PPM = 1

function IE.Rate(itemID)
  local m = ns.MEASURED_PPM and itemID and ns.MEASURED_PPM[itemID]
  local g = ns.GENERATED and ns.GENERATED.itemProcs and itemID and ns.GENERATED.itemProcs[itemID]
  if m then return { ppm = m, icd = g and g.icd or 0, source = "measured" } end
  if g then
    if g.ppm and g.ppm > 0 then return { ppm = g.ppm, icd = g.icd, source = "game data" } end
    if g.chance and g.chance > 0 and g.chance < 100 then return { chance = g.chance, icd = g.icd, source = "game data" } end
  end
  return { ppm = IE.ASSUMED_PPM, icd = g and g.icd or 0, source = "assumed" }
end

local function titled(s) return (s:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b:lower() end)) end
-- "your attack power by 120 for 10 sec" -> { AP = 120 }, 10
local function statFor(text)
  local name, n, dur = text:match("[Ii]ncreases? your (.-) by (%d+) for (%d+) sec")
  if not name then name, n, dur = text:match("[Ii]ncreases? (.-) by (%d+) for (%d+) sec") end
  if not name then return nil end
  local stats
  if name:lower():find("attack speed") then return nil end
  stats = ns.ItemText and ns.ItemText.ParseStatText("+" .. n .. " " .. titled(name))
  if stats then return stats, tonumber(dur) end
end
local function hasteFor(text)
  local p, dur = text:match("attack speed by (%d+)%%? for (%d+) sec")
  if p then return { HASTE_PCT = tonumber(p) }, tonumber(dur) end
end

-- effect lines -> modelled records, and the lines left (not counted)
function IE.Split(lines, itemID)
  local modeled, rest = {}, {}
  for _, e in ipairs(lines or {}) do
    local m = IE.Model(e, itemID)
    if m then m.text = e; modeled[#modeled + 1] = m else rest[#rest + 1] = e end
  end
  return modeled, rest
end

function IE.Model(line, itemID)
  if type(line) ~= "string" then return nil end
  local ab, pct = line:match("^Equip: Increases the damage dealt by your (.-) ability by (%d+)%%%.?$")
  if ab then return { kind = "abilityPct", ability = ab, pct = tonumber(pct) } end
  local body = line:match("^Chance on [Hh]it: (.+)$") or line:match("^Equip: Chance on hit to (.+)$")
  if body then
    local rate = IE.Rate(itemID)
    local lo, hi, school = body:match("(%d+) to (%d+) (%a+) damage")
    if lo and IE.SCHOOLS[school] then
      return { kind = "procDamage", avg = (tonumber(lo) + tonumber(hi)) / 2, school = school, rate = rate }
    end
    local n, sc = body:match("(%d+) (%a+) damage")
    if n and IE.SCHOOLS[sc] then return { kind = "procDamage", avg = tonumber(n), school = sc, rate = rate } end
    local lo2, hi2 = body:match("for (%d+) to (%d+) damage")
    if lo2 then return { kind = "procDamage", avg = (tonumber(lo2) + tonumber(hi2)) / 2, school = "Physical", rate = rate } end
    local n2 = body:match("for (%d+) damage")
    if n2 then return { kind = "procDamage", avg = tonumber(n2), school = "Physical", rate = rate } end
    local ex = body:match("(%d+) extra attacks?") or (body:find("an extra attack") and "1")
    if ex then return { kind = "procExtra", attacks = tonumber(ex), rate = rate } end
    local stats, dur = statFor(body)
    if not stats then stats, dur = hasteFor(body) end
    if stats then return { kind = "procStat", stats = stats, duration = dur, rate = rate } end
    return nil
  end
  local use = line:match("^Use: (.+)$")
  if use then
    local n, unit = use:match("%((%d+) (.-) Cooldown%)")
    if not n then return nil end
    local cd = tonumber(n) * ((unit:find("Min") and 60) or (unit:find("Hour") and 3600) or 1)
    local stats, dur = statFor(use)
    if not stats then stats, dur = hasteFor(use) end
    if stats and dur and cd > 0 then return { kind = "useStat", stats = stats, duration = dur, cooldown = cd } end
  end
  return nil
end
