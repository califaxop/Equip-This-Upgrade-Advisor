-- The melee damage model: what an item does to your damage, as a % of it.
--
-- Your numbers come from the game, live, so gear, talents and buffs are all in them: attack
-- power, crit, hit, haste, and what Strength and Agility give you (GetAttackPowerForStat,
-- GetCritChanceFromStat: Forever's own conversions). The rules, checked against Forever's character
-- sheet: 14 attack power = 1 damage per second, added at the weapon's base speed; haste shortens
-- the swing, not the hit. The enemy's side (who you hit, how often you miss) isn't something the
-- game tells addons: those are the Classic rules, all in RULES below.
--
-- An item's value = the change in your melee DPS (white hits; skills that use your weapon and
-- attack power move with it), plus its other stats (Stamina, Intellect, armor...) through your
-- weights, valued against what 1 Strength (or 1 attack power) does for your damage, plus its
-- effects (procs, "+10% Stormstrike"), which are already a % of your output. One currency: % damage.
local _, ns = ...
local M = {}
ns.Model = M
local Readable = ns.Readable

-- The enemy's side: Classic 1.12, against an enemy your level (where you spend most of your time).
M.RULES = {
  miss = 5.0,          -- % a white swing or skill misses
  dualWieldMiss = 19,  -- % more for white swings while dual wielding
  dodge = 5.0,         -- % it dodges (expertise takes it down)
  glance = 10,         -- % of white swings that glance...
  glanceDamage = 0.95, -- ...for this much damage
  critDamage = 2.0,    -- a crit does this much
  offHand = 0.5,       -- the off hand does this much
  apPerDps = 14,       -- attack power per 1 damage per second
}
local R = M.RULES

-- which specs the model scores (melee damage); everyone else keeps their weights
local MELEE = { ["WARRIOR:1"] = true, ["WARRIOR:2"] = true, ["PALADIN:3"] = true, ["ROGUE:1"] = true,
  ["ROGUE:2"] = true, ["ROGUE:3"] = true, ["SHAMAN:2"] = true }
-- the stats the model covers (the rest go through your weights)
local DAMAGE = { STR = true, AGI = true, AP = true, CRIT = true, HIT = true, DPS = true, HASTE = true }
M.DAMAGE = DAMAGE

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  if not (Readable(a)) then return nil end
  return a, b, c
end
local function Num(v) return (type(v) == "number" and Readable(v)) and v or 0 end

function M.Active(weights)
  if ns.db and ns.db.model == false then return false end
  if not MELEE[ns.SpecKey()] then return false end
  if not (UnitAttackPower and GetCritChance) then return false end
  return true
end

-- A weapon as the model sees it: damage per second and base speed (nil: not a weapon)
local function Weapon(link)
  local f = link and ns.Score.Facts(link)
  if not (f and f.stats and f.stats.DPS and f.stats.DPS > 0) then return nil end
  return { dps = f.stats.DPS, speed = f.speed or 2.5, twoHand = f.equipLoc == "INVTYPE_2HWEAPON" }
end
M.Weapon = Weapon

-- your character right now
function M.State()
  local s = {}
  local base, pos, neg = Call(UnitAttackPower, "player")
  s.ap = Num(base) + Num(pos) + Num(neg)
  s.crit = Num(Call(GetCritChance))
  local hitRating = (CR_HIT_MELEE and GetCombatRatingBonus) and Num(Call(GetCombatRatingBonus, CR_HIT_MELEE)) or 0
  s.hit = hitRating + Num(Call(GetHitModifier))
  s.ohHit = hitRating + (GetOffhandHitModifier and Num(Call(GetOffhandHitModifier)) or Num(Call(GetHitModifier)))
  s.haste = Num(Call(GetMeleeHaste))
  s.expertise = Num(Call(GetExpertise))
  -- what 1 Strength / Agility give you (from 100, for the decimals)
  s.apPerStr = Num(Call(GetAttackPowerForStat, 1, 100)) / 100
  s.apPerAgi = Num(Call(GetAttackPowerForStat, 2, 100)) / 100
  s.critPerAgi = Num(Call(GetCritChanceFromStat, 2, 100)) -- (a fraction for 100 Agility = % per 1)
  s.mh = Weapon(GetInventoryItemLink and GetInventoryItemLink("player", 16))
  s.oh = Weapon(GetInventoryItemLink and GetInventoryItemLink("player", 17))
  return s
end

-- how much of a white swing lands, on average (misses, dodges and glancing blows out, crits double)
local function Landing(hit, crit, dualWield, expertise)
  local miss = math.max(0, R.miss + (dualWield and R.dualWieldMiss or 0) - hit) / 100
  local dodge = math.max(0, R.dodge - expertise) / 100
  local glance = R.glance / 100
  local c = math.max(0, math.min(crit / 100, 1 - miss - dodge - glance))
  return 1 - miss - dodge - glance * (1 - R.glanceDamage) + c * (R.critDamage - 1), miss, dodge, c
end
M.Landing = Landing

-- a hand's damage per second before the attack table
local function HandDps(w, ap, haste)
  local weaponDps = w and w.dps or 0
  return (weaponDps + ap / R.apPerDps) * (1 + haste / 100)
end

-- your melee damage per second for state `s`
function M.Dps(s)
  local dw = s.mh ~= nil and s.oh ~= nil
  local total = HandDps(s.mh, s.ap, s.haste) * Landing(s.hit, s.crit, dw, s.expertise)
  if dw then total = total + HandDps(s.oh, s.ap, s.haste) * R.offHand * Landing(s.ohHit, s.crit, true, s.expertise) end
  return total
end

local function Copy(s) local t = {} for k, v in pairs(s) do t[k] = v end return t end

-- `s` with `stats` added (sign 1) or taken away (sign -1)
local function Apply(s, stats, sign)
  local g = function(k) return (stats[k] or 0) * sign end
  s.ap = s.ap + g("STR") * s.apPerStr + g("AGI") * s.apPerAgi + g("AP")
  s.crit = s.crit + g("AGI") * s.critPerAgi + g("CRIT")
  s.hit = s.hit + g("HIT"); s.ohHit = s.ohHit + g("HIT")
  s.haste = s.haste + g("HASTE")
end

-- Your damage with these items out and those in (links; a weapon's hand: "mh" / "oh"):
-- { out = { link, ... }, inn = { link, ... }, mh = weapon or false (unchanged: nil), oh = ... }
function M.Change(swap, s)
  s = s or M.State()
  local before = M.Dps(s)
  if before <= 0 then return nil end
  local t = Copy(s)
  for _, l in ipairs(swap.out or {}) do local f = ns.Score.Facts(l); if f then Apply(t, f.stats, -1) end end
  for _, l in ipairs(swap.inn or {}) do local f = ns.Score.Facts(l); if f then Apply(t, f.stats, 1) end end
  if swap.mh ~= nil then t.mh = swap.mh or nil end
  if swap.oh ~= nil then t.oh = swap.oh or nil end
  return (M.Dps(t) / before - 1) * 100, t
end

-- What 1 unit of a stat does to your damage, in % (for effects and your other stats)
function M.PerUnit(key, s)
  s = s or M.State()
  local n = (key == "CRIT" or key == "HIT" or key == "HASTE") and 1 or 10
  local before = M.Dps(s)
  if before <= 0 then return 0 end
  local t = Copy(s); Apply(t, { [key] = n }, 1)
  return (M.Dps(t) / before - 1) * 100 / n
end

-- the exchange rate between your weights and % damage: what 1 point of weight is worth, from
-- what Strength (or, with Strength at 0, attack power) does for your damage
local function Rate(weights, s)
  for _, k in ipairs({ "STR", "AP", "AGI" }) do
    local pts = ns.PointsPer(k, weights[k])
    if pts > 0 then return M.PerUnit(k, s) / pts end
  end
  return 0
end

-- An item's own value beyond the model's damage stats, in % damage: its other stats through your
-- weights, and its effects (at the model's values for damage stats)
local function Extra(f, weights, s, rate)
  if not f then return 0, {} end
  local pts = 0
  for k, v in pairs(f.stats) do
    if not DAMAGE[k] then pts = pts + v * ns.PointsPer(k, weights[k]) end
  end
  local why = {}
  local eff = 0
  if ns.Effects and f.effects and #f.effects > 0 and rate > 0 then
    -- effects score in weight points: give them the model's damage stats, and 1% output = 1/rate
    local w = {}
    for k, v in pairs(weights) do w[k] = v end
    for k in pairs(DAMAGE) do
      if ns.NORM[k] and ns.NORM[k] > 0 then w[k] = M.PerUnit(k, s) / rate * 5 / ns.NORM[k] end
    end
    local saved = ns.OUTPUT_PTS
    ns.OUTPUT_PTS = 1 / rate
    local ok, p, y = pcall(ns.Effects.Points, f, w)
    ns.OUTPUT_PTS = saved
    if ok then eff = (p or 0) * rate; why = y or {} end
  end
  return pts * rate + eff, why
end
M.Extra = Extra

-- Your best off hand you own (worn or in your bags) to go with a new one-hander, and its weapon
-- (nil: none, the comparison is then without an off hand)
local OFFHAND = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }
local function Owned()
  local list = {}
  local get = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
  local count = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  if get and count then
    for bag = 0, 4 do
      local ok, n = pcall(count, bag)
      for slot = 1, (ok and tonumber(n) or 0) do
        local okL, l = pcall(get, bag, slot)
        if okL and type(l) == "string" then list[#list + 1] = l end
      end
    end
  end
  local worn = GetInventoryItemLink and GetInventoryItemLink("player", 17)
  if worn then list[#list + 1] = worn end
  return list
end
function M.BestPartner(newLink, weights, dualWield, s)
  s = s or M.State()
  local rate = Rate(weights, s)
  local best, bestGain = nil, nil
  for _, l in ipairs(Owned()) do
    local f = l ~= newLink and ns.Score.Facts(l)
    if f and f.usable and (OFFHAND[f.equipLoc] or (dualWield and f.equipLoc == "INVTYPE_WEAPON")) then
      local gain = M.Change({ inn = { l }, oh = Weapon(l) or false }, s) or 0
      gain = gain + (Extra(f, weights, s, rate))
      if not bestGain or gain > bestGain then best, bestGain = l, gain end
    end
  end
  return best
end

-- The change in your damage, in %, from wearing `link` instead of `out` (links), with `partner` in
-- your off hand when a one-hander replaces a two-hander; `hand` "mh" / "oh" for a weapon.
function M.Gain(link, out, weights, hand, partner, s)
  s = s or M.State()
  local rate = Rate(weights, s)
  local swap = { out = out, inn = { link } }
  local f = ns.Score.Facts(link)
  if f and (f.equipLoc == "INVTYPE_2HWEAPON") then swap.mh, swap.oh = Weapon(link) or false, false
  elseif hand == "mh" then swap.mh = Weapon(link) or false
  elseif hand == "oh" then swap.oh = Weapon(link) or false end
  if partner then swap.inn[#swap.inn + 1] = partner; swap.oh = Weapon(partner) or false end
  local dmg = M.Change(swap, s)
  if not dmg then return nil end
  local gain = dmg + Extra(f, weights, s, rate)
  if partner then gain = gain + Extra(ns.Score.Facts(partner), weights, s, rate) end
  for _, l in ipairs(out or {}) do gain = gain - Extra(ns.Score.Facts(l), weights, s, rate) end
  return gain
end

-- /eqt model: the model's numbers, next to your character sheet's
function M.Report(print)
  local s = M.State()
  print(format("attack power %d (1 Strength = %.2f, 1 Agility = %.2f), crit %.2f%% (1 Agility = %.3f%%), hit %.2f%%, haste %.1f%%",
    s.ap, s.apPerStr, s.apPerAgi, s.crit, s.critPerAgi, s.hit, s.haste))
  local function sheet(off)
    local lo, hi, olo, ohi = Call(UnitDamage, "player")
    local sp, osp = Call(UnitAttackSpeed, "player")
    if off then lo, hi, sp = olo, ohi, osp end
    if not (lo and hi and sp and sp > 0) then return nil end
    return (lo + hi) / 2 / sp
  end
  for _, h in ipairs({ { "main hand", s.mh, false }, { "off hand", s.oh, true } }) do
    if h[2] then
      local mine = HandDps(h[2], s.ap, s.haste) * (h[3] and R.offHand or 1)
      local theirs = sheet(h[3])
      print(format("%s: %.1f damage per second (character sheet: %s)", h[1], mine, theirs and format("%.1f", theirs) or "?"))
    end
  end
  local land, miss, dodge, crit = Landing(s.hit, s.crit, s.mh ~= nil and s.oh ~= nil, s.expertise)
  print(format("against an enemy your level: %.1f%% miss, %.1f%% dodge, %d%% glancing, %.1f%% crit = %.0f%% of your swings' damage lands",
    miss * 100, dodge * 100, R.glance, crit * 100, land * 100))
  print(format("melee damage per second: %.1f. Worth: +10 Strength %.2f%%, +10 Agility %.2f%%, +10 attack power %.2f%%, +1%% crit %.2f%%, +1%% hit %.2f%%",
    M.Dps(s), M.PerUnit("STR", s) * 10, M.PerUnit("AGI", s) * 10, M.PerUnit("AP", s) * 10, M.PerUnit("CRIT", s), M.PerUnit("HIT", s)))
end
