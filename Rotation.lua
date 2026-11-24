-- How your damage splits between auto attack and each skill, from Forever Upgrades' rotation for your
-- spec as its simulator plays it (Guides.lua): each ability's share of the damage and casts a minute, at
-- levels 30, 50 and 60, blended for the levels between. Items that improve a skill ("+10% Stormstrike")
-- count by its share. Specs the site has no damage split for (healers, tanks) use a built-in split.
local _, ns = ...
local R = {}
ns.Rotation = R

-- auto attack and weapon imbues: not skills
local WHITE = { ["attack"] = true, ["auto shot"] = true, ["windfury weapon"] = true }
R.WHITE = WHITE

-- the site's split at a level: { { name, share, cpm } }, blended between 30 / 50 / 60
local function AtLevel(levels, level)
  local lo, hi
  for _, l in ipairs({ 30, 50, 60 }) do
    if levels[l] then
      if l <= level then lo = l end
      if l >= level and not hi then hi = l end
    end
  end
  lo, hi = lo or hi, hi or lo
  if not lo then return nil end
  local f = (hi ~= lo) and (level - lo) / (hi - lo) or 0
  local by, order = {}, {}
  for _, side in ipairs({ { levels[lo], 1 - f }, { levels[hi], f } }) do
    if side[2] > 0 then
      for _, p in ipairs(side[1]) do
        local k = p[1]:lower()
        local e = by[k]
        if not e then e = { p[1], 0, 0 }; by[k] = e; order[#order + 1] = e end
        e[2] = e[2] + p[2] * side[2]
        e[3] = e[3] + p[3] * side[2]
      end
    end
  end
  table.sort(order, function(a, b) return a[2] > b[2] end)
  return order
end
R.AtLevel = AtLevel

-- the built-in split (healers, tanks): the suggested skills by weight, and the rest auto attack
local function Preset(key)
  local class, tree = key:match("^(%u+):(%d)$")
  local p = class and ns.PRESET_SKILLS[class] and ns.PRESET_SKILLS[class][tonumber(tree)]
  if not p then return {} end
  local partPct = (ns.SKILL_PART[class] and ns.SKILL_PART[class][tonumber(tree)]) or 95
  local total = 0
  for _, sk in ipairs(p) do total = total + sk[2] end
  local parts = {}
  if partPct < 100 then parts[1] = { class == "HUNTER" and "Auto Shot" or "Attack", 1 - partPct / 100, 0 } end
  for _, sk in ipairs(p) do
    parts[#parts + 1] = { sk[1], sk[2] / total * partPct / 100, 24 * sk[2] / total } -- (a 2.5 s cast every time)
  end
  table.sort(parts, function(a, b) return a[2] > b[2] end)
  return parts
end

-- your split: { { name, share, cpm }, ... } biggest first, shares adding up to 1; and whether it's the site's
function R.Split(key)
  key = key or ns.SpecKey()
  local g = ns.GUIDE and ns.GUIDE[key]
  local parts = g and g.levels and AtLevel(g.levels, UnitLevel and UnitLevel("player") or 60)
  if parts and #parts > 0 then return parts, true end
  return Preset(key), false
end

-- a skill's share of your output, 0 to 1 (nil: not in your rotation); family: every skill with that
-- word in its name ("Shock" -> Earth Shock + Flame Shock)
function R.Share(name, family)
  name = (name or ""):lower()
  if name == "" then return nil end
  local word = " " .. name .. " "
  local found, share = false, 0
  for _, p in ipairs((R.Split())) do
    local n = p[1]:lower()
    if n == name or (family and (" " .. n .. " "):find(word, 1, true)) then found = true; share = share + p[2] end
  end
  return found and share or nil
end

-- how often you use a skill, a minute (nil: not in your rotation)
function R.CastsPerMin(name)
  name = (name or ""):lower()
  for _, p in ipairs((R.Split())) do
    if p[1]:lower() == name then return p[3] end
  end
end

-- the skills in your rotation (not auto attack)
function R.Names()
  local list = {}
  for _, p in ipairs((R.Split())) do if not WHITE[p[1]:lower()] then list[#list + 1] = p[1] end end
  return list
end

-- the % of your output from skills (not auto attack / weapon imbues)
function R.SkillPart()
  local part = 0
  for _, p in ipairs((R.Split())) do if not WHITE[p[1]:lower()] then part = part + p[2] end end
  return part * 100
end

-- "/eqt guide": the rotation and the split
function R.Report()
  local key = ns.SpecKey()
  local g = ns.GUIDE and ns.GUIDE[key]
  local lines = {}
  if g and g.rotation and #g.rotation > 0 then
    lines[1] = format("%s rotation (Forever Upgrades): %s", ns.SpecName(key), table.concat(g.rotation, " > "))
  end
  local parts, site = R.Split(key)
  local bits = {}
  for i, p in ipairs(parts) do
    if i > 10 then break end
    bits[#bits + 1] = p[3] > 0 and format("%s %d%% (%.1f/min)", p[1], math.floor(p[2] * 100 + 0.5), p[3])
      or format("%s %d%%", p[1], math.floor(p[2] * 100 + 0.5))
  end
  lines[#lines + 1] = (site and "damage split (Forever Upgrades' sim at your level): " or "split (built-in): ")
    .. table.concat(bits, ", ")
  return lines
end

-- what's used by older code
ns.SkillShare = R.Share
ns.SkillPart = R.SkillPart
