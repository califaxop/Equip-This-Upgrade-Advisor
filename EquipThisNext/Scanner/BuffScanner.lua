-- BuffScanner: the player's buffs and debuffs, read only while the game shows auras to addons
-- (out of combat). The evaluator will need them to tell gear stats from temporary ones (the
-- character sheet includes buffs), so a buffed snapshot can be corrected rather than trusted.
local _, ns = ...
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
  end
  profile.buffs = b
  return b
end
