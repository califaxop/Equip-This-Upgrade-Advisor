-- ItemText: reading numbers from item tooltip text (weapon speed and damage, shield block, set bonus
-- and enchant lines). Pure; English client text (other locales: unknown lines are reported, never
-- guessed).
local _, ns = ...
local IT = ns and ns.Module and ns.Module("ItemText") or {}

function IT.Speed(tooltip)
  for i, r in pairs(tooltip and tooltip.right or {}) do
    local v = tonumber(tostring(r):match("^Speed (%d+%.?%d*)$"))
    if v then return v end
  end
end

function IT.Damage(tooltip)
  for _, l in ipairs(tooltip and tooltip.left or {}) do
    local a, b = l:match("^(%d+) %- (%d+) Damage$")
    if a then return tonumber(a), tonumber(b) end
  end
end

function IT.ShieldBlock(tooltip)
  for _, l in ipairs(tooltip and tooltip.left or {}) do
    local v = tonumber(l:match("^(%d+) Block$"))
    if v then return v end
  end
end

-- "(2) Set: +10 Attack Power." -> { { pieces = 2, text = "+10 Attack Power." } }
function IT.SetBonuses(tooltip)
  local out = {}
  for _, l in ipairs(tooltip and tooltip.left or {}) do
    local n, text = l:match("^%((%d+)%) Set: (.+)$")
    if n then out[#out + 1] = { pieces = tonumber(n), text = text } end
  end
  return out
end

-- An effect text -> engine stats, or nil when it isn't a plain stat ("+3 Stamina", "+10 Attack Power",
-- "Increases attack power by 20.", "Improves your chance to get a critical strike by 1%.",
-- "Increases damage and healing done by magical spells and effects by up to 12.", "+5 All Resistances").
local NAMED = {
  Strength = "STR", Agility = "AGI", Stamina = "STA", Intellect = "INT", Spirit = "SPI", Armor = "ARMOR",
  ["Attack Power"] = "AP", ["Ranged Attack Power"] = "RAP", ["Spell Damage"] = "SP", ["Healing"] = "HEAL",
  ["Defense"] = "DEFENSE_SKILL", ["Fire Resistance"] = "RES_FIRE", ["Frost Resistance"] = "RES_FROST",
  ["Nature Resistance"] = "RES_NATURE", ["Shadow Resistance"] = "RES_SHADOW", ["Arcane Resistance"] = "RES_ARCANE",
  ["Weapon Damage"] = "WEAPON_DMG", ["mana every 5 sec"] = "MP5", ["Mana every 5 sec"] = "MP5",
  ["Critical Strike Rating"] = "CRIT_RATING", ["Hit Rating"] = "HIT_RATING", ["Haste Rating"] = "HASTE_RATING",
}
local SENTENCES = {
  { "^Increases attack power by (%d+)%.?$", "AP" },
  { "^Improves your chance to get a critical strike by (%d+%.?%d*)%%%.?$", "CRIT_PCT" },
  { "^Improves your chance to hit by (%d+%.?%d*)%%%.?$", "HIT_PCT" },
  { "^Improves your chance to get a critical strike with spells by (%d+%.?%d*)%%%.?$", "SPELLCRIT_PCT" },
  { "^Increases damage and healing done by magical spells and effects by up to (%d+)%.?$", "SP", "HEAL" },
  { "^Increases healing done by spells and effects by up to (%d+)%.?$", "HEAL" },
  { "^Restores (%d+) mana per 5 sec%.?$", "MP5" },
  { "^Increased Defense %+(%d+)%.?$", "DEFENSE_SKILL" },
  { "^Increases your chance to dodge an attack by (%d+%.?%d*)%%%.?$", "DODGE_PCT" },
}
function IT.ParseStatText(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("^Enchanted: ", ""):gsub("^Equip: ", ""):gsub("%s+$", "")
  -- a whole sentence
  for _, sn in ipairs(SENTENCES) do
    local v = tonumber(text:match(sn[1]))
    if v then
      local out = {}
      for i = 2, #sn do out[sn[i]] = v end
      return out
    end
  end
  -- "+N Name", or a list of them joined by "and" / ","
  local out, any = {}, false
  local body = text:gsub("%.$", "")
  for part in (body:gsub(",", " and ") .. " and "):gmatch("(.-) and ") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    if part ~= "" then
      local n, name = part:match("^%+(%d+) (.+)$")
      if n and name == "All Resistances" then
        for _, r in ipairs({ "RES_FIRE", "RES_FROST", "RES_NATURE", "RES_SHADOW", "RES_ARCANE" }) do out[r] = (out[r] or 0) + tonumber(n) end
        any = true
      elseif n and NAMED[name] then
        out[NAMED[name]] = (out[NAMED[name]] or 0) + tonumber(n); any = true
      else
        return nil   -- a part that isn't a plain stat: the text isn't plain stats
      end
    end
  end
  return any and out or nil
end
