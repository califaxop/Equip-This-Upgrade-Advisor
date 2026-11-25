-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- AbilityScanner (milestone 4): what the game says about your damage abilities and weapon imbues,
-- into profile.abilities, for the pure AbilityInterpreter:
--   spells[spellID] = { known, desc, cooldownText }   abilities in Data/Generated.lua you know
--                                                     (desc: C_Spell.GetSpellDescription, the game's
--                                                     own resolved text; cooldownText: the tooltip's
--                                                     right side, "8 sec cooldown")
--   casts[name] = { spellID, desc, castText, manaText, cooldownText }   your highest rank of each
--                                                     damage or heal spell in Data/Generated.lua
--   imbues[slot] = { enchantID, castSpell, desc, procDesc }   a temporary weapon enchant on 16/17
--                                                     (Windfury...): the spell of yours that puts it
--                                                     on, and its description
local _, ns = ...; ns = ns.Engine
local AbilityScanner = ns.Module("AbilityScanner")
local Spell = ns.SpellAPI

local function cooldownText(id, tip)
  tip = tip or Spell.Tooltip(id)
  for _, r in pairs(tip and tip.right or {}) do
    if r:find("[Cc]ooldown") then return r end
  end
end
-- "2.5 sec cast" / "Instant" and "120 Mana" from a spell's tooltip (left or right side)
local function tipTexts(tip)
  local cast, mana
  for _, side in ipairs({ tip and tip.left or {}, tip and tip.right or {} }) do
    for _, t in pairs(side) do
      if not cast and (t:find("sec cast") or t:find("^Instant")) then cast = t end
      if not mana and t:find("^%d+ Mana") then mana = t end
    end
  end
  return cast, mana
end

function AbilityScanner.Scan(profile)
  local G = ns.GENERATED or {}
  local known = profile.spells and profile.spells.known or {}
  local out = { spells = {}, imbues = {}, casts = {} }
  -- damage and heal spells: your highest rank of each
  local best = {}
  for id in pairs(known) do
    local d = G.spells and G.spells[id]
    if d and (not best[d.name] or d.level > G.spells[best[d.name]].level) then best[d.name] = id end
  end
  for name, id in pairs(best) do
    local tip = Spell.Tooltip(id)
    local castText, manaText = tipTexts(tip)
    out.casts[name] = { spellID = id, desc = Spell.Description(id), castText = castText, manaText = manaText,
      cooldownText = cooldownText(id, tip) }
  end
  for id in pairs(G.abilities or {}) do
    local isKnown = known[id] ~= nil or Spell.IsKnown(id) == true
    if isKnown then out.spells[id] = { known = true, desc = Spell.Description(id), cooldownText = cooldownText(id) } end
  end
  for _, slot in ipairs({ 16, 17 }) do
    local it = profile.equipment and profile.equipment.slots[slot]
    for _, te in ipairs(it and it.tempEnchants or {}) do
      local imb = G.imbues and G.imbues[te.enchantID]
      if imb then
        local cast
        for _, sid in ipairs(imb.spells or {}) do if known[sid] then cast = sid end end
        out.imbues[slot] = { enchantID = te.enchantID, castSpell = cast, desc = cast and Spell.Description(cast),
          procDesc = imb.spell and Spell.Description(imb.spell) }
      else
        out.imbues[slot] = { enchantID = te.enchantID }
      end
    end
  end
  profile.abilities = out
  return out
end
