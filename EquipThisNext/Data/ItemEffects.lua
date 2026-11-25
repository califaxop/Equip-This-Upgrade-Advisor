-- ItemEffects: which green tooltip lines of an item are just its stats (already counted from
-- C_Item.GetItemStats) and which are effects the models don't count yet (procs, use effects, ability
-- bonuses). An effect not counted is listed on the comparison and lowers its confidence: it's never
-- treated as zero without saying so. Pure data + matching.
local _, ns = ...
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
