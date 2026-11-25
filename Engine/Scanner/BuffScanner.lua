-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- BuffScanner: the player's buffs and debuffs, read only while the game shows auras to addons
-- (out of combat). The evaluator will need them to tell gear stats from temporary ones (the
-- character sheet includes buffs), so a buffed snapshot can be corrected rather than trusted.
local _, ns = ...; ns = ns.Engine
local BuffScanner = ns.Module("BuffScanner")
local Aura = ns.AuraAPI

local MAX = 40

local function list(filter)
  local out = {}
  for i = 1, MAX do
    local a = Aura.Get(i, filter)
    if not a then break end
    out[#out + 1] = a
  end
  return out
end

function BuffScanner.Scan(profile)
  local b = { helpful = {}, harmful = {} }
  if Aura.Restricted() then
    b.restricted = true
    ns.CharacterProfile.AddIssue(profile, "info", "auras-hidden", "the game hides auras right now (combat?): buffs not read")
  else
    b.helpful = list("HELPFUL")
    b.harmful = list("HARMFUL")
    -- buffs whose value matters to a talent's model, kept once seen (Flurry: its haste %)
    ns.db.seenBuffs = ns.db.seenBuffs or {}
    for _, a in ipairs(b.helpful) do
      if a.name == "Flurry" and a.points and a.points[1] and a.points[1] > 0 then ns.db.seenBuffs.Flurry = a.points[1] end
    end
  end
  profile.buffs = b
  return b
end
