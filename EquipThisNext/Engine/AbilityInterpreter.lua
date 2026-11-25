-- AbilityInterpreter (milestone 4): your damage abilities and weapon imbue as model inputs. Pure Lua.
--
-- Numbers come from what the game shows first (the spell's own description, resolved by the game:
-- "Instantly strike for 100% weapon damage", "a 20% chance of granting you 1 extra attack with 145
-- extra melee attack power"), then from the game's client tables (Data/Generated.lua: cooldowns,
-- internal cooldowns, chances the descriptions don't give). Each value says where it came from, and
-- a value from neither is never used.
--
--   Interpret(profile, talents) -> {
--     strikes = { { name, spellID, weaponPct, cooldown, source } },   (used on cooldown)
--     imbue = { kind = "windfury", slot, chance, icd, attacks, ap, apSource, name } or { kind = "other", name },
--     notes = { ... }, unchecked = n }
local _, ns = ...
local AI = ns and ns.Module and ns.Module("AbilityInterpreter") or {}

-- Elemental Weapons: % more Windfury effect per rank. Forever's talent description shows rank 1's 13%
-- only (as for every talent); Classic's ranks are 13 / 27 / 40. Used until a measurement says otherwise.
AI.ELEMENTAL_WEAPONS_WF = { 13, 27, 40 }

local function rankOf(profile, name)
  for _, n in ipairs(profile.talents and profile.talents.nodes or {}) do
    if n.name == name and (n.rank or 0) > 0 then return n.rank end
  end
  return 0
end

-- "8 sec cooldown" / "1.5 min cooldown" -> seconds
function AI.Cooldown(text)
  if type(text) ~= "string" then return nil end
  local n, unit = text:match("([%d%.]+) (%a+)")
  n = tonumber(n)
  if not n then return nil end
  if unit:find("^min") then return n * 60 elseif unit:find("^sec") then return n end
end

-- confirmed: { [part name] = true } for parts a measurement (/eqn measure) agreed with
function AI.Interpret(profile, talents, confirmed)
  local G = ns.GENERATED or {}
  local A = profile.abilities or {}
  local out = { strikes = {}, notes = {}, unchecked = 0 }
  local level = profile.identity and profile.identity.level or 1
  for id, data in pairs(G.abilities or {}) do
    local sp = A.spells and A.spells[id]
    if sp and sp.known then
      local pct = sp.desc and tonumber(sp.desc:match("(%d+)%% weapon damage"))
      local cd = AI.Cooldown(sp.cooldownText)
      local st = { name = data.name, spellID = id, weaponPct = pct or data.weaponPct, cooldown = cd or data.cooldown,
        source = (pct and "description" or "game data") .. ", cooldown " .. (cd and "tooltip" or "game data") }
      if st.weaponPct and st.weaponPct > 0 and st.cooldown and st.cooldown > 0 then
        out.strikes[#out.strikes + 1] = st
        out.notes[#out.notes + 1] = string.format("%s: %d%% weapon damage every %gs (used on cooldown; %s)", st.name, st.weaponPct, st.cooldown, st.source)
      end
    end
  end
  for _, slot in ipairs({ 16, 17 }) do
    local im = A.imbues and A.imbues[slot]
    local data = im and G.imbues and G.imbues[im.enchantID]
    if im and data and data.kind == "windfury" then
      local d = im.desc or im.procDesc or ""
      local chance = tonumber(d:match("(%d+)%% chance")) or data.chance
      local attacks = tonumber(d:match("(%d+) extra attack"))
      local ap = tonumber(d:match("(%d+) extra melee attack power"))
      local apSource = "description"
      if not ap and data.ap then
        local lv = math.min(level, data.ap.maxLevel > 0 and data.ap.maxLevel or level)
        ap = data.ap.base + data.ap.perLevel * math.max(0, lv - data.ap.baseLevel)
        apSource = "game data"
      end
      if not attacks then
        attacks = 1
        out.unchecked = out.unchecked + 1
        out.notes[#out.notes + 1] = "Windfury: number of extra attacks not in its description: 1 assumed"
      end
      local ew = rankOf(profile, "Elemental Weapons")
      local ewPct = ew > 0 and AI.ELEMENTAL_WEAPONS_WF[math.min(ew, 3)] or 0
      local checked = confirmed and confirmed[data.name]
      if ew > 0 and not checked then out.unchecked = out.unchecked + 1 end
      out.imbue = { kind = "windfury", slot = slot, name = data.name, chance = chance, icd = data.icd or 0,
        attacks = attacks, ap = (ap or 0) * (1 + ewPct / 100), apSource = apSource, elementalWeapons = ewPct }
      out.notes[#out.notes + 1] = string.format("%s: %d%% chance per hit (internal cooldown %gs, game data) for %d extra attack(s) with %d attack power (%s%s)",
        data.name, chance, data.icd or 0, attacks, (ap or 0) * (1 + ewPct / 100) + 0.5, apSource,
        ewPct > 0 and string.format(", +%d%% Elemental Weapons: Classic's rank value, unconfirmed", ewPct) or "")
      break
    elseif im and data then
      out.imbue = { kind = data.kind, slot = slot, name = data.name }
      if data.kind ~= "rockbiter" then
        out.notes[#out.notes + 1] = data.name .. ": not modelled yet (its damage isn't counted)"
      else
        out.notes[#out.notes + 1] = data.name .. ": its attack power is on your character sheet already"
      end
      break
    elseif im then
      out.notes[#out.notes + 1] = "a temporary weapon enchant (" .. tostring(im.enchantID) .. ") that isn't modelled"
    end
  end
  return out
end
