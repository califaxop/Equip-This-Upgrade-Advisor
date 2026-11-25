-- Threat model (milestone 4c): threat per second, kept apart from survivability (EHP). Pure Lua.
--
-- Threat = damage x the threat modifiers on you for that damage's school. The modifiers are the
-- game's own (Data/Generated.lua `threat`: Forever's "mod threat" auras): stances and forms through
-- their passives (Defensive Stance Passive +80%, Bear Form +115%), Righteous Fury (+90% Holy, +33%
-- all), class passives (Rogue -29%), talents (Defiance...). Several multiply together (assumed).
-- Not counted: abilities' own extra threat (Sunder Armor, Heroic Strike, Rockbiter...: the server
-- keeps those, not the client's tables), threat from healing, taunts.
local _, ns = ...
local T = ns and ns.Module and ns.Module("ThreatModel") or {}

T.SCHOOL_BIT = { Physical = 1, Holy = 2, Fire = 4, Nature = 8, Frost = 16, Shadow = 32, Arcane = 64 }
T.CLASS_PASSIVE = { ROGUE = "Rogue Passive" }

local function hasBit(mask, bit) return math.floor(mask / bit) % 2 == 1 end

-- the threat modifiers active for this character: { { name, pct, mask, source } }
function T.Sources(profile)
  local G = ns.GENERATED and ns.GENERATED.threat or {}
  local out, seen = {}, {}
  local function add(id, source, scale)
    local t = G[id]
    if not t or seen[id] then return end
    seen[id] = true
    for _, m in ipairs(t.mods) do out[#out + 1] = { name = t.name, pct = m[1] * (scale or 1), mask = m[2], source = source } end
  end
  local byName = {}
  for id, t in pairs(G) do byName[t.name] = id end
  -- your auras (stances and forms by their passive: "Defensive Stance" -> "Defensive Stance Passive")
  for _, a in ipairs(profile.buffs and profile.buffs.helpful or {}) do
    if a.spellId then add(a.spellId, "aura") end
    if a.name then
      for id, t in pairs(G) do
        local base = t.name:gsub(" %(Passive.-%)$", ""):gsub(" Passive$", "")
        if base ~= t.name and (a.name == base or a.name:sub(-#base - 1) == " " .. base) then add(id, "aura") end
      end
    end
  end
  local class = profile.identity and profile.identity.class
  local cp = T.CLASS_PASSIVE[class]
  if cp then for id, t in pairs(G) do if t.name:find("^" .. cp) then add(id, "class") end end end
  -- talents: the description's value is rank 1's; times the rank (unconfirmed)
  for _, n in ipairs(profile.talents and profile.talents.nodes or {}) do
    if (n.rank or 0) > 0 and n.spellID and G[n.spellID] then add(n.spellID, "talent", n.rank) end
  end
  return out
end

-- the threat multiplier for damage of a school
function T.Multiplier(sources, school)
  local bit = T.SCHOOL_BIT[school or "Physical"] or 1
  local m = 1
  for _, s in ipairs(sources or {}) do
    if hasBit(s.mask, bit) then m = m * (1 + s.pct / 100) end
  end
  return m
end

-- threat per second from the DPS parts ({ name, dps, school })
function T.TPS(parts, sources)
  local tps = 0
  for _, p in ipairs(parts or {}) do tps = tps + (p.dps or 0) * T.Multiplier(sources, p.school) end
  return tps
end
