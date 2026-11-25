-- MeterAPI: the game's own damage meter (C_DamageMeter, Blizzard_APIDocumentationGenerated, build
-- 71091), used to check the DPS model against real fights: damage per spell for you in a finished
-- combat session. Its values are secret in combat, so it's read after combat.
-- Enum values from DamageMeterConstantsDocumentation: DamageMeterType.DamageDone = 0.
local _, ns = ...
local Meter = ns.Module("MeterAPI")
local Compat = ns.Compat
Meter.DAMAGE_DONE = 0
Meter.HEALING_DONE = 2

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

-- every finished fight the meter keeps: { { id, name, duration } }
function Meter.Sessions()
  local ok, list = Compat.Call("C_DamageMeter.GetAvailableCombatSessions")
  local out = {}
  if not ok or type(list) ~= "table" then return out end
  for _, s in ipairs(list) do
    local id, d = Compat.Field(s, "sessionID"), Compat.Field(s, "durationSeconds")
    if type(id) == "number" then out[#out + 1] = { id = id, name = Compat.Field(s, "name"), duration = type(d) == "number" and d or nil } end
  end
  return out
end

-- all fights since the meter was last reset (DamageMeterSessionType.Overall = 0)
Meter.OVERALL = 0
function Meter.OverallDuration() return Compat.Value("C_DamageMeter.GetSessionDurationSeconds", Meter.OVERALL) end
function Meter.Reset() return Compat.Call("C_DamageMeter.ResetAllCombatSessions") end

-- your damage per spell in a session (sessionID, or "overall"): { total, spells = { [spellID] = amount } } or nil, why
function Meter.MySpells(sessionID, guid, kind)
  local ok, src
  kind = kind or Meter.DAMAGE_DONE
  if sessionID == "overall" then
    ok, src = Compat.Call("C_DamageMeter.GetCombatSessionSourceFromType", Meter.OVERALL, kind, guid)
  else
    ok, src = Compat.Call("C_DamageMeter.GetCombatSessionSourceFromID", sessionID, kind, guid)
  end
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
