-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- CalcScanner: the game's calculators, evaluated for this character into profile.calc, so the pure
-- engine can use the game's own numbers:
--   ratingPct[CR_...]   % per rating point (GetCombatRatingBonusForCombatRatingValue at 100 points)
--   armorEffect[level]  armor reduction at your armor vs an attacker of that level (levels you..+3, and 63)
--   glancing[offset]    { chance, penalty } of your main-hand vs targets 0-3 levels above you
--   talentText[spellID] the descriptions of talents you have points in
-- Calculators are hidden while stats are (combat): then the last readable set is kept.
local _, ns = ...; ns = ns.Engine
local CalcScanner = ns.Module("CalcScanner")
local Char, Spell = ns.CharacterAPI, ns.SpellAPI

local last
function CalcScanner.Scan(profile)
  if profile.stats.restricted then
    profile.calc = last and ns.Database.Copy(last) or {}
    return profile.calc
  end
  local c = { ratingPct = {}, armorEffect = {}, glancing = {}, talentText = {} }
  for _, list in pairs(ns.StatDefs.RATINGS) do
    for _, cr in ipairs(list) do
      if c.ratingPct[cr] == nil then
        local b = Char.RatingBonusFor(cr, 100)
        if type(b) == "number" then c.ratingPct[cr] = b / 100 end
      end
    end
  end
  local v = profile.stats.values
  local L = profile.identity.level or 1
  local armor = v["armor.effective"]
  if armor and armor > 0 then
    for a = L, L + 3 do c.armorEffect[a] = Char.ArmorEffectiveness(armor, a) end
    c.armorEffect[63] = c.armorEffect[63] or Char.ArmorEffectiveness(armor, 63)
  end
  local ws = profile.stats.weaponSkills and profile.stats.weaponSkills[16]
  local skill = ws and ws.rank and (ws.rank + (ws.modifier or 0))
  if skill then
    for off = 0, 3 do c.glancing[off] = Char.Glancing(skill, (L + off) * 5) end
  end
  c.glancingBySkill = {}
  for _, sk in pairs(profile.stats.skillByLine or {}) do
    if not c.glancingBySkill[sk] then
      c.glancingBySkill[sk] = {}
      for off = 0, 3 do c.glancingBySkill[sk][off] = Char.Glancing(sk, (L + off) * 5) end
    end
  end
  for _, n in ipairs(profile.talents and profile.talents.nodes or {}) do
    if (n.rank or 0) > 0 and n.spellID then c.talentText[n.spellID] = Spell.Description(n.spellID) end
  end
  c.seenBuffs = ns.db and ns.db.seenBuffs and ns.Database.Copy(ns.db.seenBuffs) or nil
  profile.calc = c
  last = ns.Database.Copy(c)
  return c
end
