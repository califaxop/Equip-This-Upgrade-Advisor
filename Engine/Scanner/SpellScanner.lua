-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- SpellScanner: the spells in the player's spellbook (spell ID -> name and rank text). Abilities
-- and their ranks decide which spells a performance model can use (Milestone 4).
local _, ns = ...; ns = ns.Engine
local SpellScanner = ns.Module("SpellScanner")
local Spell = ns.SpellAPI

function SpellScanner.Scan(profile)
  local known, count = {}, 0
  for line = 1, Spell.NumSkillLines() do
    local info = Spell.SkillLine(line)
    if info and info.offset and info.count and not info.hidden then
      for i = info.offset + 1, info.offset + info.count do
        local s = Spell.BookItem(i)
        if s and s.spellID and s.name then
          known[s.spellID] = s.subName and s.subName ~= "" and (s.name .. " (" .. s.subName .. ")") or s.name
          count = count + 1
        end
      end
    end
  end
  profile.spells = { known = known, count = count }
  if count == 0 then
    ns.CharacterProfile.AddIssue(profile, "warn", "spellbook-empty", "no spells read from the spellbook")
  end
  return profile.spells
end
