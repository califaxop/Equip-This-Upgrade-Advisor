-- AbilityScanner (milestone 4): what the game says about your damage abilities and weapon imbues,
-- into profile.abilities, for the pure AbilityInterpreter:
--   spells[spellID] = { known, desc, cooldownText }   abilities in Data/Generated.lua you know
--                                                     (desc: C_Spell.GetSpellDescription, the game's
--                                                     own resolved text; cooldownText: the tooltip's
--                                                     right side, "8 sec cooldown")
--   imbues[slot] = { enchantID, castSpell, desc, procDesc }   a temporary weapon enchant on 16/17
--                                                     (Windfury...): the spell of yours that puts it
--                                                     on, and its description
local _, ns = ...
local AbilityScanner = ns.Module("AbilityScanner")
local Spell = ns.SpellAPI

local function cooldownText(id)
  local tip = Spell.Tooltip(id)
  for _, r in pairs(tip and tip.right or {}) do
    if r:find("[Cc]ooldown") then return r end
  end
end

function AbilityScanner.Scan(profile)
  local G = ns.GENERATED or {}
  local known = profile.spells and profile.spells.known or {}
  local out = { spells = {}, imbues = {} }
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
