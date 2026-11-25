-- MeterAPI: the game's own damage meter (C_DamageMeter, Blizzard_APIDocumentationGenerated, build
-- 71091), used to check the DPS model against real fights: damage per spell for you in a finished
-- combat session. Its values are secret in combat, so it's read after combat.
-- Enum values from DamageMeterConstantsDocumentation: DamageMeterType.DamageDone = 0.
local _, ns = ...
local Meter = ns.Module("MeterAPI")
local Compat = ns.Compat
Meter.DAMAGE_DONE = 0

function Meter.Available()
  local ok, yes, why = Compat.Call("C_DamageMeter.IsDamageMeterAvailable")
  if not ok then return false, "the game has no damage meter API here" end
  if yes == Compat.SECRET then return false, "hidden right now" end
  return yes and true or false, Compat.Plain(why)
end

-- the newest finished session: { id, name, duration }
function Meter.LastSession()
  local ok, list = Compat.Call("C_DamageMeter.GetAvailableCombatSessions")
  if not ok or type(list) ~= "table" then return nil end
  local best
  for _, s in ipairs(list) do
    local id = Compat.Field(s, "sessionID")
    if type(id) == "number" and (not best or id > best.id) then
      best = { id = id, name = Compat.Field(s, "name"), duration = Compat.Field(s, "durationSeconds") }
    end
  end
  return best
end

-- your damage per spell in a session: { total, duration, spells = { [spellID] = amount } } or nil, why
function Meter.MySpells(sessionID, guid)
  local ok, src = Compat.Call("C_DamageMeter.GetCombatSessionSourceFromID", sessionID, Meter.DAMAGE_DONE, guid)
  if not ok or type(src) ~= "table" then return nil, "no data for that fight" end
  local spells, total = {}, 0
  local list = Compat.Field(src, "combatSpells")
  if type(list) ~= "table" then return nil, "no spells in that fight" end
  for _, sp in ipairs(list) do
    local id, amt = Compat.Field(sp, "spellID"), Compat.Field(sp, "totalAmount")
    if type(id) == "number" and type(amt) == "number" then
      spells[id] = (spells[id] or 0) + amt
      total = total + amt
    elseif amt == Compat.SECRET then
      return nil, "the values are hidden (in combat): try again after the fight"
    end
  end
  return { total = total, spells = spells }
end
