-- Which spells each spec actually uses, and how often (single target). Item effects on a spell
-- ("+10% Lightning Bolt") count for your spec only if the spell is in its rotation, at its rate.
-- Each spell: "cd" (used on cooldown, read from the game) or seconds between casts.
-- From current WoW: Forever guides; numbers marked ~ are estimates where guides give no rate.
-- You can change them: /eqt rotation <spell> <casts per minute> (0 = not used), /eqt rotation reset.
-- A spec with no list here keeps the simple rule (spells with a cooldown on cooldown; fillers
-- with no cooldown only for casters).
local _, ns = ...
local R = {}
ns.Rotations = R

ns.ROTATIONS = {
  SHAMAN = {
    [2] = { -- Enhancement (Wowhead / Zockify / Conquest Capped Forever guides, Nov 2026)
      { "Stormstrike", "cd" },     -- top priority, on cooldown (8 s on Forever since the Nov 13 hotfix)
      { "Lightning Bolt", 12 },    -- ~ at 5 Maelstrom Weapon stacks (instant); no guide gives a rate
      { "Flame Shock", 12 },       -- ~ kept on the target
      { "Earth Shock", 12 },       -- ~ every other shock cooldown
    },
  },
}

-- this spec's rotation as { [spell name] = "cd" or seconds }, with your own changes; nil = no list
function R.For(key)
  key = key or ns.SpecKey()
  local class, tree = key:match("^(%u+):(%d)$")
  local base = class and ns.ROTATIONS[class] and ns.ROTATIONS[class][tonumber(tree)]
  local mine = ns.db and ns.db.rotation and ns.db.rotation[key]
  if not base and not mine then return nil end
  local out, names = {}, {} -- (names: how to write each, for /eqt rotation)
  for _, s in ipairs(base or {}) do out[s[1]:lower()] = s[2]; names[s[1]:lower()] = s[1] end
  for name, v in pairs(mine or {}) do
    local cpm = type(v) == "table" and v.cpm or v
    if cpm == 0 then out[name] = false else out[name] = 60 / cpm end -- casts per minute -> seconds
    if type(v) == "table" and v.name then names[name] = names[name] or v.name end
  end
  return out, names
end

-- for a spell: "cd", seconds between casts, false (not used), or nil (this spec has no list)
function R.Every(spell, key)
  local list = R.For(key)
  if not list then return nil end
  local v = list[spell:lower()]
  if v == nil then return false end
  return v
end

-- /eqt rotation [spell casts-per-minute | reset]
function R.Command(rest)
  local key = ns.SpecKey()
  ns.db.rotation = ns.db.rotation or {}
  if rest:lower() == "reset" then
    ns.db.rotation[key] = nil
    ns.Score.ClearCache()
    ns.Print("rotation for " .. ns.SpecName(key) .. " back to the guide's.")
    return
  end
  local spell, n = rest:match("^(.-)%s+(%d+%.?%d*)$")
  if spell and spell ~= "" then
    ns.db.rotation[key] = ns.db.rotation[key] or {}
    ns.db.rotation[key][spell:lower()] = { cpm = tonumber(n), name = spell }
    ns.Score.ClearCache()
    ns.Print(format("%s: %s %s.", ns.SpecName(key), spell,
      tonumber(n) == 0 and "isn't used" or format("cast %s times a minute", n)))
    return
  end
  local list, names = R.For(key)
  if not list then
    ns.Print(ns.SpecName(key) .. " has no rotation list yet: spells with a cooldown count as used on cooldown.")
  else
    local parts = {}
    for name, v in pairs(list) do
      local secs = type(v) == "number" and ((v == math.floor(v)) and tostring(v) or format("%.1f", v))
      parts[#parts + 1] = (names[name] or name) .. ": " .. (v == "cd" and "on cooldown" or (v == false and "not used") or format("every %ss", secs))
    end
    table.sort(parts)
    ns.Print(ns.SpecName(key) .. " rotation: " .. table.concat(parts, ", "))
  end
  ns.Print("change one: /eqt rotation <spell> <casts per minute> (0 = not used), or /eqt rotation reset")
end
