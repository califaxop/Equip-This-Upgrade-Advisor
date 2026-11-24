-- How your damage splits between auto attack and each skill: a guide's rotation to start, your own
-- damage meter as it learns.
--
-- Guide: Forever Upgrades' rotation for your spec, played out in its simulator (Guides.lua): each
-- ability's share of the damage and how often it's used, at levels 30, 50 and 60 (blended for the
-- levels between). Its spell numbers can trail Forever's patches, so each ability's damage per use is
-- read from its tooltip in your game (your rank, your weapon and attack power), auto attack comes
-- from your weapon (Model.lua), and casts a minute are capped by the ability's real cooldown.
-- What has no tooltip number (poisons, Deep Wounds, Windfury, pets...) keeps the guide's share, scaled
-- with the rest. Spells you don't know are left out.
-- Meter: Learn.lua adds up what the game's damage meter says you did. The more combat it has, the more
-- it counts: BLEND_SECONDS of combat and it's all yours. Specs the guide has no damage split for
-- (healers, tanks) use a built-in split instead.
local _, ns = ...
local R = {}
ns.Rotation = R
local Readable = ns.Readable

R.BLEND_SECONDS = 600  -- combat recorded before your meter counts in full (1 min ~10%, 5 min half)
R.CAP_SLACK = 1.2      -- casts are capped by the cooldown only past this (talents shorten some cooldowns)
local WHITE = "Attack" -- auto attack, as the damage meter names it

-- healers: the meter counts damage, not healing, so their split stays the built-in one
local HEALERS = { ["PRIEST:1"] = true, ["PRIEST:2"] = true, ["PALADIN:1"] = true, ["SHAMAN:3"] = true, ["DRUID:3"] = true }
local MELEE = { ["WARRIOR:1"] = true, ["WARRIOR:2"] = true, ["PALADIN:3"] = true, ["ROGUE:1"] = true,
  ["ROGUE:2"] = true, ["ROGUE:3"] = true, ["SHAMAN:2"] = true }

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

-- is it a spell of yours? true: you know it; false: a spell you don't know (yet); nil: not a spell
-- by that name (auto attack, a pet, a proc)
local function Knows(name)
  if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
  local ok, info = pcall(C_Spell.GetSpellInfo, name)
  if not (ok and type(info) == "table" and info.spellID) then return nil end
  if not IsPlayerSpell then return true end
  local okK, known = pcall(IsPlayerSpell, info.spellID)
  if okK and Readable(known) then return known and true or false end
  return true
end

-- one use of a skill, from its tooltip: damage, kind (swing / ap / spell) and cooldown (s); nil if unread
local function Use(name, s)
  local E = ns.Effects
  local id, _, cd = E.KnownSpell(name)
  if not id then return nil end
  local avg, tcd, heal, _, weapon = E.SpellUse(id)
  if heal then return nil end
  local text = E.SpellText(id) or ""
  local M = ns.Model
  local melee = (s and s.mh) and M.SpecialLanding(s) * M.TalentDamage(s) or 1
  local dmg, kind
  local apPct = text:lower():match("(%d+)%% of your attack power")
  local a5, b5 = text:gsub(",", ""):match("5 points?: (%d+)%s*%-%s*(%d+)")
  if a5 then
    dmg = (tonumber(a5) + tonumber(b5)) / 2 * melee           -- (a finisher at 5 combo points)
  elseif apPct and s then
    dmg, kind = s.ap * tonumber(apPct) / 100 * melee, "ap"
  elseif weapon then
    if avg then dmg, kind = avg * melee, "swing" end
  else
    local d = SpellDamage(text)
    if d then
      local crit = Num(GetSpellCritChance and select(2, pcall(GetSpellCritChance, 4))) or 5
      dmg = d * (1 + crit / 200) * 0.96 -- (crits do +50%; about 4% of spells miss)
    end
  end
  return dmg and dmg > 0 and dmg or nil, kind, math.max(cd or 0, tcd or 0)
end

-- the guide's split at your level: { { name, share, cpm, cd, isSpell } }, blended between 30 / 50 / 60
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
        if not e then e = { p[1], 0, 0, 0, p[5] }; by[k] = e; order[#order + 1] = e end
        e[2] = e[2] + p[2] * side[2]
        e[3] = e[3] + p[3] * side[2]
        e[4] = math.max(e[4], p[4] or 0)
      end
    end
  end
  return order
end

-- the guide's split, played with your spells: { parts = { { name, share, kind, cpm } } } or nil
local function Play(key, s)
  local g = ns.GUIDE and ns.GUIDE[key]
  local base = g and g.levels and AtLevel(g.levels, UnitLevel and UnitLevel("player") or 60)
  if not base then return nil end
  local M = ns.Model
  local list = {}
  for _, p in ipairs(base) do
    local name, share, cpm, dbcd, isSpell = p[1], p[2], p[3], p[4], p[5]
    local e = { name = name, share = share, cpm = cpm > 0 and cpm or nil, kind = M.SkillKind(name) }
    if name == WHITE then
      if s and M.Dps(s) > 0 then e.live = M.Dps(s) * 60 end
      list[#list + 1] = e
    elseif not (isSpell and e.cpm and C_Spell and C_Spell.GetSpellInfo and not Knows(name)) then
      -- (left out: an ability you'd cast that you haven't learned; passives and procs always count)
      if e.cpm then
        local dmg, kind, cd = Use(name, s)
        cd = (cd and cd > 0) and cd or dbcd
        if cd and cd > 0 and e.cpm > 60 / cd * R.CAP_SLACK then e.cpm = 60 / cd end -- (a longer cooldown than the guide's)
        if kind then e.kind = kind end
        if dmg then e.live = dmg * e.cpm end
      end
      list[#list + 1] = e
    end
  end
  if #list == 0 then return nil end
  -- the scale between your numbers and the guide's: the middle one of (yours / its) for what was read;
  -- something read far off that (a tooltip misread) keeps the guide's share instead
  local ratios = {}
  for _, e in ipairs(list) do if e.live and e.share > 0 then ratios[#ratios + 1] = e.live / e.share end end
  table.sort(ratios)
  local k = #ratios > 0 and ratios[math.floor((#ratios + 1) / 2)] or 1
  local total = 0
  for _, e in ipairs(list) do
    local r = e.live and e.share > 0 and e.live / e.share / k
    e.dmg = (r and r > 0.25 and r < 4) and e.live or e.share * k
    total = total + e.dmg
  end
  if total <= 0 then return nil end
  local parts = {}
  for _, e in ipairs(list) do parts[#parts + 1] = { e.name, e.dmg / total, e.kind, e.cpm } end
  table.sort(parts, function(a, b) return a[2] > b[2] end)
  return { parts = parts }
end
R.Play = Play

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

-- the guide's split for your spec (cached: your gear, attack power and level change it)
function R.Guide(key)
  key = key or ns.SpecKey()
  local s = MELEE[key] and ns.Model.State() or nil
  local level = UnitLevel and UnitLevel("player") or 60
  local stamp = format("%s:%d:%.1f:%d", tostring(s and s.mh and s.mh.dps), s and s.ap or 0, s and s.haste or 0, level)
  local c = cache[key]
  local now = GetTime and GetTime() or 0
  if c and (c.stamp == stamp or (s and s.ap <= 0)) and now - c.at < 30 then return c.split end
  local ok, split = pcall(Play, key, s)
  if ok and split then
    split.guide = true
  elseif c then
    return c.split -- (hidden numbers in combat: the last good one)
  else
    split = Preset(key)
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
  local base = split.guide and "Forever Upgrades' rotation" or "the built-in split"
  local m = split.meter or 0
  if m >= 1 then return "your damage meter" end
  if m > 0 then return format("%s, %d%% your damage meter", base, math.floor(m * 100 + 0.5)) end
  return base
end

-- what's used by older code
ns.SkillShare = R.Share
ns.SkillPart = R.SkillPart
