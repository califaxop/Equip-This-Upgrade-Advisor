-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- TalentInterpreter: the profile's raw talents -> modifiers the stat engine and the models use.
-- Pure Lua. Talents are matched by spell ID, then by class and name (Data/Talents.lua).
--   conversions = { { from = "INT", to = "AP", pct = 1.0, talent, check } }
--   flurry      = { haste = 0.20, swings = 3, talent, check } or nil
--   notes       = { text }           (how each number was found)
--   unchecked   = n                  (effects whose number isn't confirmed: lowers confidence)
local _, ns = ...; ns = ns.Engine
local TI = ns and ns.Module and ns.Module("TalentInterpreter") or {}

local function find(class, n)
  local TD = ns.TalentData
  return (n.spellID and TD.BY_SPELL[n.spellID]) or TD.BY_NAME[tostring(class) .. ":" .. tostring(n.name)]
end

-- the number in a talent's description (calc.talentText[spellID]) or nil
local function fromText(calc, n, pattern)
  local text = calc and calc.talentText and n.spellID and calc.talentText[n.spellID]
  if type(text) ~= "string" or not pattern then return nil end
  local v = tonumber(text:match(pattern))
  return v
end

-- sheetMinusGear: { SP = x, HEAL = y, AP = z } what the sheet has beyond gear and buffs (for measured conversions)
function TI.Interpret(profile, sheetMinusGear)
  local out = { conversions = {}, notes = {}, unchecked = 0 }
  local class = profile.identity and profile.identity.class
  local INT = profile.stats and profile.stats.values and profile.stats.values["stat.INT.effective"]
  for _, n in ipairs(profile.talents and profile.talents.nodes or {}) do
    local rank = n.rank or 0
    local e = rank > 0 and find(class, n)
    if e and e.kind == "convert" then
      for _, to in ipairs(e.to) do
        local pct, check = nil, e.check
        if e.measure then
          local extra = sheetMinusGear and sheetMinusGear[to]
          if extra and INT and INT > 0 then pct = extra / INT end
          if not pct then pct, check = 0, "unmeasured" end
        else
          pct = (e.pctPerRank or 0) * rank
        end
        out.conversions[#out.conversions + 1] = { from = e.from, to = to, pct = pct, talent = e.name, rank = rank, check = check }
        out.notes[#out.notes + 1] = string.format("%s %d/%s: %s -> %s x%.3f (%s)", e.name, rank, tostring(n.maxRank), e.from, to, pct, check)
        if check ~= "sheet" then out.unchecked = out.unchecked + 1 end
      end
    elseif e and e.kind == "flurry" then
      -- the buff's own value, seen on you (aura points), else the Classic table for your rank
      local v, check
      for _, a in ipairs(profile.buffs and profile.buffs.helpful or {}) do
        if a.name == e.buffName and type(a.points) == "table" and type(a.points[1]) == "number" and a.points[1] > 0 then
          v, check = a.points[1], "buff"
        end
      end
      if not v and profile.calc and profile.calc.seenBuffs and profile.calc.seenBuffs[e.buffName or ""] then
        v, check = profile.calc.seenBuffs[e.buffName], "buff"
      end
      if not v and e.forever and e.forever[rank] then v, check = e.forever[rank], "forever" end
      if not v then v, check = e.hastePerRankDefault and e.hastePerRankDefault[rank], "source" end
      if v then
        out.flurry = { haste = v / 100, swings = e.swings or 3, talent = e.name, rank = rank, check = check }
        out.notes[#out.notes + 1] = string.format("%s %d/%s: +%g%% attack speed for %d swings after a crit (%s)",
          e.name, rank, tostring(n.maxRank), v, e.swings or 3,
          check == "buff" and "from the Flurry buff seen on you" or check == "forever" and "Forever's value for this rank"
            or "Classic value for this rank, not confirmed on Forever yet")
        if check == "source" then out.unchecked = out.unchecked + 1 end
      end
    end
  end
  return out
end
