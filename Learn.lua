-- Your real damage split, learned from the game's own damage meter (C_DamageMeter).
--
-- After each fight (the meter's numbers are hidden during combat, readable after), your damage per
-- spell is added up, per character and spec. Recent fights count most: past KEEP_SECONDS of combat,
-- older ones fade out. With MIN_SECONDS of combat recorded, skill shares come from it instead of
-- your Skill Weights: "+10% Stormstrike" counts by Stormstrike's real share of your damage, and the
-- damage model splits your output the way you really fight (auto attack, weapon strikes, spells).
local _, ns = ...
local L = {}
ns.Learn = L
local Readable = ns.Readable
local isSecret = ns.isSecret

L.MIN_SECONDS = 60   -- combat recorded before it's used
L.KEEP_SECONDS = 900 -- about the last 15 minutes of combat count (older fights fade out)

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and Readable(n) and type(n) == "string" and n ~= "" then return n end
  end
  if GetSpellInfo then
    local ok, n = pcall(GetSpellInfo, id)
    if ok and Readable(n) and type(n) == "string" and n ~= "" then return n end
  end
end

-- the game's damage meter, if it's there and on
function L.MeterAvailable()
  if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetCombatSessionSourceFromID) then
    return false, "this client has no damage meter"
  end
  if C_DamageMeter.IsDamageMeterAvailable then
    local ok, yes, why = pcall(C_DamageMeter.IsDamageMeterAvailable)
    if ok and Readable(yes) and not yes then return false, (Readable(why) and why ~= "" and why) or "the damage meter is off" end
  end
  return true
end

-- what's been learned for your spec: { seconds, fights, spells = { [name] = damage } }
function L.Data(key)
  ns.db.learned = ns.db.learned or {}
  key = key or ns.SpecKey()
  local d = ns.db.learned[key]
  if not d then d = { seconds = 0, fights = 0, spells = {} }; ns.db.learned[key] = d end
  return d
end

-- in use: on, and enough combat recorded
function L.Active()
  if not ns.db or ns.db.learn == false then return false end
  local d = ns.db.learned and ns.db.learned[ns.SpecKey()]
  return d ~= nil and (d.seconds or 0) >= L.MIN_SECONDS
end

-- your damage split: { { name, share }, ... } biggest first, shares adding up to 1
function L.Shares()
  local d = L.Data()
  local total = 0
  for _, v in pairs(d.spells) do total = total + v end
  local list = {}
  if total <= 0 then return list end
  for name, v in pairs(d.spells) do list[#list + 1] = { name, v / total } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  return list
end

-- a spell's share of your damage, 0 to 1 (nil: you don't use it); family: every spell with that
-- word in its name ("Shock" -> Earth Shock + Flame Shock)
function L.Share(name, family)
  name = (name or ""):lower()
  if name == "" then return nil end
  local word = " " .. name .. " "
  local found, share = false, 0
  for _, s in ipairs(L.Shares()) do
    local n = s[1]:lower()
    if n == name or (family and (" " .. n .. " "):find(word, 1, true)) then found = true; share = share + s[2] end
  end
  return found and share or nil
end

-- count a fight: what the meter says you did, spell by spell
local function Count(sessionID, seconds)
  local guid = UnitGUID and UnitGUID("player")
  local okS, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, Enum.DamageMeterType.DamageDone, guid)
  if not (okS and type(src) == "table" and not isSecret(src)) then return false end
  local spells = src.combatSpells
  if type(spells) ~= "table" then return false end
  local d = L.Data()
  local any = false
  for _, sp in ipairs(spells) do
    local id, amount = sp.spellID, sp.totalAmount
    if Readable(id) and Readable(amount) and type(amount) == "number" and amount > 0 then
      local name = SpellName(id)
      if name then d.spells[name] = (d.spells[name] or 0) + amount; any = true end
    end
  end
  if not any then return false end
  d.seconds = (d.seconds or 0) + seconds
  d.fights = (d.fights or 0) + 1
  -- older fights fade out: keep about KEEP_SECONDS of combat
  if d.seconds > L.KEEP_SECONDS then
    local f = L.KEEP_SECONDS / d.seconds
    for name, v in pairs(d.spells) do d.spells[name] = v * f end
    d.seconds = L.KEEP_SECONDS
  end
  return true
end

-- after combat: count the fights the meter has that we haven't yet
function L.Record()
  if not (ns.db and ns.db.learn ~= false) or not L.MeterAvailable() then return end
  local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
  if not (ok and type(sessions) == "table") then return end
  ns.db.learnSeen = ns.db.learnSeen or {}
  for _, ses in ipairs(sessions) do
    local id, secs, name = ses.sessionID, ses.durationSeconds, ses.name
    if Readable(id) and Readable(secs) and type(secs) == "number" and secs > 0 then
      local key = tostring(id) .. ":" .. tostring(Readable(name) and name or "") .. ":" .. format("%.1f", secs)
      if not ns.db.learnSeen[key] then
        if Count(id, secs) then ns.db.learnSeen[key] = true end
      end
    end
  end
end

function L.Reset() if ns.db.learned then ns.db.learned[ns.SpecKey()] = nil end end

-- "/eqt learn": where things stand
function L.Status()
  if ns.db.learn == false then return "off: Skill Weights are used (/eqt learn on)" end
  local ok, why = L.MeterAvailable()
  if not ok then return "can't learn: " .. why .. ". Skill Weights are used." end
  local d = L.Data()
  if not L.Active() then
    return format("learning: %d fight(s), %ds of combat so far (needs %ds). Skill Weights are used until then.",
      d.fights or 0, math.floor(d.seconds or 0), L.MIN_SECONDS)
  end
  local parts = {}
  for i, s in ipairs(L.Shares()) do
    if i > 8 then break end
    parts[#parts + 1] = format("%s %d%%", s[1], math.floor(s[2] * 100 + 0.5))
  end
  return format("from your damage meter (%d fights, %d min of combat): %s", d.fights or 0,
    math.floor((d.seconds or 0) / 60 + 0.5), table.concat(parts, ", "))
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
  if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(L.Record) end) else pcall(L.Record) end
end)
