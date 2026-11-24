-- How your damage splits between auto attack and each skill: a guide's rotation to start, your own
-- damage meter as it learns.
--
-- Guide: each damage spec has a single-target priority list (the usual Classic rotations). It's played
-- out for two minutes with your own spells (the ranks you know, their tooltip numbers, cooldowns and cast
-- times) and your own weapon and attack power (Model.lua): what each skill does, and how often you use it.
-- Meter: Learn.lua adds up what the game's damage meter says you did. The more combat it has, the more
-- it counts: BLEND_SECONDS of combat and it's all yours. A spec without a list (healers, tanks, hunters,
-- feral) uses a built-in split instead.
local _, ns = ...
local R = {}
ns.Rotation = R
local Readable = ns.Readable

R.SECONDS = 120        -- how long the rotation is played out
R.BLEND_SECONDS = 600  -- combat recorded before your meter counts in full (1 min ~10%, 5 min half)
local WHITE = "Attack" -- auto attack, as the damage meter names it

-- Priority lists, top first. Fields:
--   dot: kept up (recast when it runs out);  filler: used when nothing else is ready (the best one);
--   group/groupCd: a shared cooldown (shocks);  cpm: used about this often a minute, outside the
--   priority (procs, rage dumps);  replaces: takes the place of a white swing (Heroic Strike);
--   ap: damage = this x attack power;  cost/cp/finisher: rogue energy and combo points;
--   swings: if the tooltip has no number, about this many main-hand hits
local GUIDES = {
  ["SHAMAN:1"] = { gcd = 1.5,
    { "Flame Shock", dot = true, group = "shock", groupCd = 6 },
    { "Chain Lightning" },
    { "Lightning Bolt", filler = true } },
  ["SHAMAN:2"] = { gcd = 1.5, melee = true, windfury = true,
    { "Stormstrike", swings = 1 },
    { "Flame Shock", dot = true, group = "shock", groupCd = 6 },
    { "Earth Shock", group = "shock", groupCd = 6 } },
  ["WARRIOR:1"] = { gcd = 1.5, melee = true,
    { "Mortal Strike" },
    { "Whirlwind" },
    { "Overpower", cpm = 1.5 },
    { "Heroic Strike", cpm = 5, replaces = true } },
  ["WARRIOR:2"] = { gcd = 1.5, melee = true,
    { "Bloodthirst", ap = 0.45 },
    { "Whirlwind" },
    { "Heroic Strike", cpm = 8, replaces = true } },
  ["PALADIN:3"] = { gcd = 1.5, melee = true,
    { "Seal of Command", cpm = 7 },
    { "Judgement", swings = 1, noTip = true },
    { "Consecration" } },
  ["ROGUE:1"] = { gcd = 1.0, melee = true, energy = true,
    { "Eviscerate", finisher = 5, cost = 35, swings = 2.5 },
    { "Sinister Strike", cost = 40, cp = 1 } },
  ["ROGUE:2"] = { gcd = 1.0, melee = true, energy = true,
    { "Eviscerate", finisher = 5, cost = 35, swings = 2.5 },
    { "Sinister Strike", cost = 40, cp = 1 } },
  ["ROGUE:3"] = { gcd = 1.0, melee = true, energy = true,
    { "Eviscerate", finisher = 5, cost = 35, swings = 2.5 },
    { "Hemorrhage", cost = 35, cp = 1 },
    { "Sinister Strike", cost = 40, cp = 1, fallback = "Hemorrhage" } },
  ["PRIEST:3"] = { gcd = 1.5,
    { "Shadow Word: Pain", dot = true },
    { "Mind Blast" },
    { "Mind Flay", filler = true, channel = true } },
  ["MAGE:1"] = { gcd = 1.5,
    { "Arcane Missiles", filler = true, channel = true },
    { "Frostbolt", filler = true } },
  ["MAGE:2"] = { gcd = 1.5,
    { "Fire Blast" },
    { "Fireball", filler = true } },
  ["MAGE:3"] = { gcd = 1.5,
    { "Fire Blast" },
    { "Frostbolt", filler = true } },
  ["WARLOCK:1"] = { gcd = 1.5,
    { "Corruption", dot = true },
    { "Curse of Agony", dot = true },
    { "Siphon Life", dot = true },
    { "Shadow Bolt", filler = true } },
  ["WARLOCK:2"] = { gcd = 1.5,
    { "Corruption", dot = true },
    { "Curse of Agony", dot = true },
    { "Immolate", dot = true },
    { "Shadow Bolt", filler = true } },
  ["WARLOCK:3"] = { gcd = 1.5,
    { "Immolate", dot = true },
    { "Conflagrate" },
    { "Corruption", dot = true },
    { "Shadow Bolt", filler = true } },
  ["DRUID:1"] = { gcd = 1.5,
    { "Moonfire", dot = true },
    { "Insect Swarm", dot = true },
    { "Starfire", filler = true },
    { "Wrath", filler = true } },
}
R.GUIDES = GUIDES
-- healers: the meter counts damage, not healing, so their split stays the built-in one
local HEALERS = { ["PRIEST:1"] = true, ["PRIEST:2"] = true, ["PALADIN:1"] = true, ["SHAMAN:3"] = true, ["DRUID:3"] = true }

local function Num(v) return (type(v) == "number" and Readable(v)) and v or nil end

-- a spell's damage from its tooltip: what it does at once, and over time ("and 28 Fire damage over 12 sec")
local function SpellDamage(text)
  local t = text:lower():gsub(",", "")
  local dot, dur = t:match("(%d+) %a* ?damage over (%d+%.?%d*) sec")
  if dot then t = t:gsub("(%d+) %a* ?damage over (%d+%.?%d*) sec", "", 1) end
  local a, b = t:match("(%d+) to (%d+) %a* ?damage")
  local direct = a and (tonumber(a) + tonumber(b)) / 2 or tonumber(t:match("(%d+) %a* ?damage") or "")
  local total = (direct or 0) + (tonumber(dot) or 0)
  return total > 0 and total or nil, tonumber(dur)
end
R.SpellDamage = SpellDamage

-- one use of a skill: { name, dmg, cast, cd, dur } (nil: you don't know it, or it can't be read)
local function Use(e, s)
  local E = ns.Effects
  local id, cast, cd = E.KnownSpell(e[1])
  if not id then return nil end
  local avg, tcd, _, _, weapon = E.SpellUse(id)
  local text = E.SpellText(id)
  local M = ns.Model
  local melee = (s and s.mh) and M.SpecialLanding(s) * M.TalentDamage(s) or 1
  local dmg, dur
  if e.noTip then
    -- (its tooltip has no damage: Judgement's depends on the seal)
  elseif e.ap and s then
    dmg = s.ap * e.ap * melee
  elseif e.finisher then
    local t = text:gsub(",", "")
    local a, b = t:match(e.finisher .. " points?: (%d+)%s*%-%s*(%d+)")
    if not a then a, b = t:match(".*%D(%d+) to (%d+)") end
    if a and b then dmg = (tonumber(a) + tonumber(b)) / 2 * melee end
  elseif weapon then
    if avg then dmg = avg * melee end
  else
    local d
    d, dur = SpellDamage(text)
    if d then
      local crit = Num(GetSpellCritChance and select(2, pcall(GetSpellCritChance, 4))) or 5
      dmg = d * (1 + crit / 200) * 0.96 -- (crits do +50%; about 4% of spells miss)
    end
  end
  if not dmg and e.swings and s and s.mh then dmg = M.Swing(s) * e.swings end
  if not dmg or dmg <= 0 then return nil end
  cd = math.max(cd or 0, tcd or 0)
  if e.channel then cast = dur or 3 end
  return { e = e, name = e[1], dmg = dmg, cast = cast or 0, cd = cd, dur = dur or 0 }
end

-- the rotation played out: { parts = { { name, share, kind, cpm } }, melee } or nil
local function Play(guide, s)
  local T, gcd = R.SECONDS, guide.gcd or 1.5
  local list, fixed = {}, {}
  local have = {}
  for _, e in ipairs(guide) do
    if not (e.fallback and have[e.fallback]) then
      local u = Use(e, s)
      if u then
        have[e[1]] = true
        if e.cpm then fixed[#fixed + 1] = u else list[#list + 1] = u end
      end
    end
  end
  if #list == 0 and #fixed == 0 then return nil end
  local count, dmg = {}, {}
  local ready, groupReady, dotEnd = {}, {}, {}
  local energy, cp = 100, 0
  local t, n = 0, 0
  while t < T and n < 5000 do
    n = n + 1
    local pick
    for _, u in ipairs(list) do
      local e = u.e
      if not e.filler and (ready[u.name] or 0) <= t and (not e.group or (groupReady[e.group] or 0) <= t)
        and (not e.dot or (dotEnd[u.name] or 0) <= t)
        and (not e.cost or energy >= e.cost) and (not e.finisher or cp >= e.finisher) then
        pick = u; break
      end
    end
    if not pick then -- the best filler (damage per second of casting)
      local best
      for _, u in ipairs(list) do
        if u.e.filler and (ready[u.name] or 0) <= t then
          local rate = u.dmg / math.max(gcd, u.cast)
          if not best or rate > best then best, pick = rate, u end
        end
      end
    end
    local busy
    if pick then
      local e = pick.e
      count[pick.name] = (count[pick.name] or 0) + 1
      dmg[pick.name] = (dmg[pick.name] or 0) + pick.dmg
      busy = math.max(gcd, pick.cast)
      if pick.cd > 0 then ready[pick.name] = t + math.max(pick.cd, busy) end
      if e.group then groupReady[e.group] = t + (e.groupCd or 6) end
      if e.dot then dotEnd[pick.name] = t + pick.cast + math.max(pick.dur, 6) end
      if e.cost then energy = energy - e.cost end
      if e.cp then cp = math.min(5, cp + e.cp) end
      if e.finisher then cp = 0 end
    else
      busy = 0.1 -- (waiting: a cooldown or energy)
    end
    t = t + busy
    if guide.energy then energy = math.min(100, energy + 10 * busy) end
  end
  for _, u in ipairs(fixed) do
    local c = u.e.cpm * T / 60
    count[u.name] = c
    dmg[u.name] = c * u.dmg
  end
  -- auto attack (and Windfury) for melee specs
  local M = ns.Model
  if guide.melee and s and M.Dps(s) > 0 then
    local white = M.Dps(s) * T
    for _, u in ipairs(fixed) do
      if u.e.replaces then white = white - count[u.name] * M.Swing(s) * 0.9 end -- (a swing that would have been white)
    end
    dmg[WHITE] = math.max(0, white)
    if guide.windfury and ns.Effects.KnownSpell("Windfury Weapon") and s.mh then
      local swings = T * (1 + s.haste / 100) / s.mh.speed
      dmg["Windfury Weapon"] = swings * 0.2 * M.Swing(s) * 1.2 -- (20% of swings; the extra attack has more attack power)
    end
  end
  local total = 0
  for _, v in pairs(dmg) do total = total + v end
  if total <= 0 then return nil end
  local parts = {}
  for name, v in pairs(dmg) do
    parts[#parts + 1] = { name, v / total, M.SkillKind(name), count[name] and count[name] * 60 / T or nil }
  end
  table.sort(parts, function(a, b) return a[2] > b[2] end)
  return { parts = parts }
end

-- the built-in split (specs without a guide list): the old suggested skills, by weight
local function Preset(key)
  local class, tree = key:match("^(%u+):(%d)$")
  local p = class and ns.PRESET_SKILLS[class] and ns.PRESET_SKILLS[class][tonumber(tree)]
  if not p then return { parts = {} } end
  local partPct = (ns.SKILL_PART[class] and ns.SKILL_PART[class][tonumber(tree)]) or 95
  local total = 0
  for _, sk in ipairs(p) do total = total + sk[2] end
  local parts = {}
  local whiteName = class == "HUNTER" and "Auto Shot" or WHITE
  if partPct < 100 then parts[1] = { whiteName, 1 - partPct / 100, "white" } end
  for _, sk in ipairs(p) do
    -- (casts a minute: a 2.5 s cast every time, split by weight)
    parts[#parts + 1] = { sk[1], sk[2] / total * partPct / 100, ns.Model.SkillKind(sk[1]), 24 * sk[2] / total }
  end
  table.sort(parts, function(a, b) return a[2] > b[2] end)
  return { parts = parts, preset = true }
end

local cache = {}
function R.ClearCache() wipe(cache) end

-- the guide's split for your spec (cached: your gear and attack power change it)
function R.Guide(key)
  key = key or ns.SpecKey()
  local guide = GUIDES[key]
  if not guide then return Preset(key) end
  local s = guide.melee and ns.Model.State() or nil
  local stamp = s and format("%s:%d:%.1f", tostring(s.mh and s.mh.dps), s.ap, s.haste) or "-"
  local c = cache[key]
  local now = GetTime and GetTime() or 0
  if c and (c.stamp == stamp or (s and s.ap <= 0)) and now - c.at < 30 then return c.split end
  local ok, split = pcall(Play, guide, s)
  if not (ok and split) then
    if c then return c.split end -- (hidden numbers in combat: the last good one)
    split = Preset(key)
  else
    split.guide = true
  end
  cache[key] = { stamp = stamp, at = now, split = split }
  return split
end

-- how much your damage meter counts (0 to 1), and its seconds of combat
function R.MeterWeight(key)
  key = key or ns.SpecKey()
  local mode = ns.db and ns.db.split or "blend"
  local L = ns.Learn
  if not L or HEALERS[key] or mode == "guide" or (ns.db and ns.db.learn == false) then return 0, 0 end
  local d = ns.db.learned and ns.db.learned[key]
  local secs = d and d.seconds or 0
  if secs < L.MIN_SECONDS then return 0, secs end
  if mode == "meter" then return 1, secs end
  return math.min(1, secs / R.BLEND_SECONDS), secs
end

-- your split: { white = 0, parts = { { name, share, kind, cpm } }, meter = 0..1, guide/preset }
function R.Split()
  local key = ns.SpecKey()
  local g = R.Guide(key)
  local m = R.MeterWeight(key)
  if m <= 0 then return { white = 0, parts = g.parts, meter = 0, guide = g.guide, preset = g.preset } end
  local by, order = {}, {}
  local function add(name, share, kind, cpm, guideShare)
    local k = name:lower()
    local p = by[k]
    if not p then p = { name, 0, kind or ns.Model.SkillKind(name) }; by[k] = p; order[#order + 1] = p end
    p[2] = p[2] + share
    if cpm then p[4], p.g = cpm, guideShare end
  end
  for _, p in ipairs(g.parts) do add(p[1], p[2] * (1 - m), p[3], p[4], p[2]) end
  for _, sp in ipairs(ns.Learn.Shares()) do add(sp[1], sp[2] * m) end
  -- casts a minute: the guide's, scaled by how much more (or less) of your damage the skill really is
  for _, p in ipairs(order) do
    if p[4] and p.g and p.g > 0 then p[4] = p[4] * p[2] / p.g end
    p.g = nil
  end
  table.sort(order, function(a, b) return a[2] > b[2] end)
  return { white = 0, parts = order, meter = m, guide = g.guide, preset = g.preset }
end

-- a skill's share of your output, 0 to 1 (nil: not in your rotation); family: every skill with that
-- word in its name ("Shock" -> Earth Shock + Flame Shock)
function R.Share(name, family)
  name = (name or ""):lower()
  if name == "" then return nil end
  local word = " " .. name .. " "
  local found, share = false, 0
  for _, p in ipairs(R.Split().parts) do
    local n = p[1]:lower()
    if n == name or (family and (" " .. n .. " "):find(word, 1, true)) then found = true; share = share + p[2] end
  end
  return found and share or nil
end

-- how often you use a skill, a minute (nil: not in your rotation)
function R.CastsPerMin(name)
  name = (name or ""):lower()
  for _, p in ipairs(R.Split().parts) do
    if p[1]:lower() == name then
      if p[4] then return p[4] end
      return 24 * p[2] -- (only seen on your meter: about its share of a caster's 24 casts)
    end
  end
end

-- the skills in your rotation (not auto attack)
function R.Names()
  local list = {}
  for _, p in ipairs(R.Split().parts) do if p[1] ~= WHITE then list[#list + 1] = p[1] end end
  return list
end

-- the % of your output from skills (not auto attack / Windfury)
function R.SkillPart()
  local part = 0
  for _, p in ipairs(R.Split().parts) do if p[3] ~= "white" then part = part + p[2] end end
  return part * 100
end

-- where the split comes from, in words
function R.Source(split)
  split = split or R.Split()
  local base = split.guide and "the guide's rotation" or "the built-in split"
  local m = split.meter or 0
  if m >= 1 then return "your damage meter" end
  if m > 0 then return format("%s, %d%% your damage meter", base, math.floor(m * 100 + 0.5)) end
  return base
end

-- what's used by older code
ns.SkillShare = R.Share
ns.SkillPart = R.SkillPart
