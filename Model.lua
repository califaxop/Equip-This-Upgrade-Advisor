-- The melee damage model: what an item does to your damage, as a % of it.
--
-- Your numbers come from the game, live, so gear, talents and buffs are all in them: attack
-- power, crit, hit, haste, and what Strength and Agility give you (GetAttackPowerForStat,
-- GetCritChanceFromStat: Forever's own conversions). The rules, checked against Forever's character
-- sheet: 14 attack power = 1 damage per second, added at the weapon's base speed; haste shortens
-- the swing, not the hit. The enemy's side (who you hit, how often you miss) isn't something the
-- game tells addons: those are the Classic rules, all in RULES below.
--
-- Your output is split the way your Skill Weights say (/eqt): white hits, and each skill's share.
-- Each part moves the way it really does with gear:
--   white hits (and weapon imbues like Windfury)  -> your damage per second
--   weapon strikes (Stormstrike, Mortal Strike...) -> one main-hand swing: the weapon's hit plus
--                                                     attack power x its speed / 14 (a slow, heavy
--                                                     weapon makes them hit much harder)
--   attack power skills (Bloodthirst)              -> your attack power
--   spells (shocks, Lightning Bolt...)             -> not melee gear: unchanged
-- An item's value = the change in that output, plus its other stats (Stamina, Intellect, armor...) through your
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

-- Talents that depend on the weapon (per rank; Classic's values): your live crit and hit already
-- include what your current weapon gets, so that's taken out, and each setup gets its own.
--   dmg2h / dmg1h: % damage with a two-hander / one-hander;  oh: % more off-hand damage;
--   dwHit: % hit while dual wielding;  crit + subs: % crit with those weapon kinds (item subclasses)
local AXES, POLEARMS, DAGGERS, FISTS = { [0] = true, [1] = true }, { [6] = true }, { [15] = true }, { [13] = true }
local TALENTS = {
  WARRIOR = { ["two-handed weapon specialization"] = { dmg2h = 1 }, ["dual wield specialization"] = { oh = 5 },
              ["axe specialization"] = { crit = 1, subs = AXES }, ["polearm specialization"] = { crit = 1, subs = POLEARMS } },
  PALADIN = { ["two-handed weapon specialization"] = { dmg2h = 2 }, ["one-handed weapon specialization"] = { dmg1h = 2 } },
  ROGUE   = { ["dual wield specialization"] = { oh = 10 }, ["dagger specialization"] = { crit = 1, subs = DAGGERS },
              ["fist weapon specialization"] = { crit = 1, subs = FISTS } },
  SHAMAN  = { ["dual wield specialization"] = { dwHit = 2 } },
}
M.TALENTS = TALENTS
-- what your talents give: { dmg2h, dmg1h, oh, dwHit, crits = { { pct, subs } }, names = { "Axe Specialization 5/5" } }
function M.Talents()
  local t = { dmg2h = 0, dmg1h = 0, oh = 0, dwHit = 0, crits = {}, names = {} }
  for name, e in pairs(TALENTS[ns.Class()] or {}) do
    local rank = ns.TalentRank(name)
    if rank > 0 then
      for _, k in ipairs({ "dmg2h", "dmg1h", "oh", "dwHit" }) do if e[k] then t[k] = t[k] + e[k] * rank end end
      if e.crit then t.crits[#t.crits + 1] = { e.crit * rank, e.subs } end
      t.names[#t.names + 1] = format("%s (rank %d)", (name:gsub("(%a)([%w']*)", function(x, y) return x:upper() .. y end)), rank)
    end
  end
  return t
end
local function TalentCrit(t, w)
  local c = 0
  if w and w.sub then for _, tc in ipairs(t.crits) do if tc[2][w.sub] then c = c + tc[1] end end end
  return c
end

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
  local sub = C_Item and C_Item.GetItemInfoInstant and select(7, C_Item.GetItemInfoInstant(link))
  return { dps = f.stats.DPS, speed = f.speed or 2.5, twoHand = f.equipLoc == "INVTYPE_2HWEAPON", sub = type(sub) == "number" and sub or nil }
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
  -- your weapon talents: take out what your current weapons get (the setup decides, see Crit / Hit)
  s.tal = M.Talents()
  s.crit = s.crit - TalentCrit(s.tal, s.mh)
  if s.mh and s.oh then s.hit = s.hit - s.tal.dwHit; s.ohHit = s.ohHit - s.tal.dwHit end
  return s
end

local function DW(s) return s.mh ~= nil and s.oh ~= nil end
local function Crit(s) return s.crit + TalentCrit(s.tal, s.mh) end
local function Hit(s, off) return (off and s.ohHit or s.hit) + (DW(s) and s.tal.dwHit or 0) end
-- weapon damage from talents: x(1 + %) with a two-hander / one-hander
local function TalentDamage(s)
  if not s.mh then return 1 end
  return 1 + (s.mh.twoHand and s.tal.dmg2h or s.tal.dmg1h) / 100
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
  local dw = DW(s)
  local total = HandDps(s.mh, s.ap, s.haste) * TalentDamage(s) * Landing(Hit(s), Crit(s), dw, s.expertise)
  if dw then
    total = total + HandDps(s.oh, s.ap, s.haste) * R.offHand * (1 + s.tal.oh / 100) * Landing(Hit(s, true), Crit(s), true, s.expertise)
  end
  return total
end

local function Copy(s) local t = {} for k, v in pairs(s) do t[k] = v end return t end

-- Skills that hit with your weapon (one swing's damage) or scale with attack power. Lower case.
local SWING = { ["stormstrike"] = true, ["heroic strike"] = true, ["mortal strike"] = true, ["sinister strike"] = true,
  ["backstab"] = true, ["ambush"] = true, ["hemorrhage"] = true, ["overpower"] = true, ["slam"] = true, ["cleave"] = true,
  ["whirlwind"] = true, ["crusader strike"] = true, ["lava lash"] = true, ["ghostly strike"] = true, ["riposte"] = true,
  ["raptor strike"] = true, ["mutilate"] = true, ["seal of command"] = true, ["holy strike"] = true }
local APSKILL = { ["bloodthirst"] = true }
local WHITE = { ["windfury weapon"] = true, ["windfury"] = true, ["windfury attack"] = true, ["auto attack"] = true, ["attack"] = true,
  ["rockbiter weapon"] = true, ["flametongue weapon"] = true, ["seal of righteousness"] = true }
function M.SkillKind(name)
  local n = (name or ""):lower()
  if SWING[n] then return "swing" end
  if APSKILL[n] then return "ap" end
  if WHITE[n] then return "white" end
  return "spell"
end

-- a skill or ability's hit: misses and dodges, crits, but no glancing or dual-wield penalty
local function SpecialLanding(s)
  local miss = math.max(0, R.miss - Hit(s)) / 100
  local dodge = math.max(0, R.dodge - s.expertise) / 100
  local c = math.max(0, math.min(Crit(s) / 100, 1 - miss - dodge))
  return 1 - miss - dodge + c * (R.critDamage - 1)
end
-- one main-hand swing's damage, on average (a weapon strike's)
local function Swing(s)
  local w = s.mh
  local speed = w and w.speed or 2.0
  local weaponHit = w and w.dps * speed or 0
  return (weaponHit + s.ap * speed / R.apPerDps) * TalentDamage(s) * SpecialLanding(s)
end
M.Swing = Swing

-- your output, split: { white = share, parts = { { name, share, kind } ... } } (shares add up to 1),
-- from your damage meter once it's learned enough, else your Skill Weights
function M.Split()
  local parts, used = {}, 0
  if ns.Learn and ns.Learn.Active() then
    for _, sp in ipairs(ns.Learn.Shares()) do parts[#parts + 1] = { sp[1], sp[2], M.SkillKind(sp[1]) } end
    return { white = 0, parts = parts, learned = true }
  end
  for _, sk in ipairs(ns.CurrentSkills()) do
    local share = ns.SkillShare(sk[1])
    if share and share > 0 then
      parts[#parts + 1] = { sk[1], share, M.SkillKind(sk[1]) }
      used = used + share
    end
  end
  return { white = math.max(0, 1 - used), parts = parts }
end

-- how much your output changes from state `a` to state `b`: their ratio
local function Ratio(a, b, split)
  split = split or M.Split()
  local da, db = M.Dps(a), M.Dps(b)
  if da <= 0 then return nil end
  local r = split.white * db / da
  local sa, sb = Swing(a), Swing(b)
  local la, lb = SpecialLanding(a), SpecialLanding(b)
  for _, p in ipairs(split.parts) do
    local share, kind = p[2], p[3]
    if kind == "swing" then r = r + share * (sa > 0 and sb / sa or 1)
    elseif kind == "ap" then r = r + share * ((a.ap * la) > 0 and (b.ap * lb) / (a.ap * la) or 1)
    elseif kind == "white" then r = r + share * db / da
    else r = r + share end
  end
  return r
end
M.Ratio = Ratio

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
  if M.Dps(s) <= 0 then return nil end
  local t = Copy(s)
  for _, l in ipairs(swap.out or {}) do local f = ns.Score.Facts(l); if f then Apply(t, f.stats, -1) end end
  for _, l in ipairs(swap.inn or {}) do local f = ns.Score.Facts(l); if f then Apply(t, f.stats, 1) end end
  if swap.mh ~= nil then t.mh = swap.mh or nil end
  if swap.oh ~= nil then t.oh = swap.oh or nil end
  local r = Ratio(s, t)
  if not r then return nil end
  return (r - 1) * 100, t
end

-- What 1 unit of a stat does to your damage, in % (for effects and your other stats)
function M.PerUnit(key, s)
  s = s or M.State()
  local n = (key == "CRIT" or key == "HIT" or key == "HASTE") and 1 or 10
  if M.Dps(s) <= 0 then return 0 end
  local t = Copy(s); Apply(t, { [key] = n }, 1)
  if key == "DPS" then t.mh = t.mh and { dps = t.mh.dps + n, speed = t.mh.speed, twoHand = t.mh.twoHand } end
  local r = Ratio(s, t)
  return r and (r - 1) * 100 / n or 0
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
    s.ap, s.apPerStr, s.apPerAgi, Crit(s), s.critPerAgi, Hit(s), s.haste))
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
  if s.mh then
    local lo, hi = Call(UnitDamage, "player")
    local hit = s.mh.dps * s.mh.speed + s.ap * s.mh.speed / R.apPerDps
    print(format("main-hand hit: %.0f on average (character sheet: %s), weapon speed %.2f",
      hit, (lo and hi) and format("%.0f", (lo + hi) / 2) or "?", s.mh.speed))
  end
  local split = M.Split()
  local parts = {}
  if split.white > 0 then parts[1] = format("white hits %d%%", math.floor(split.white * 100 + 0.5)) end
  local how = { swing = "per hit", ap = "attack power", white = "per second", spell = "not melee" }
  for i, p in ipairs(split.parts) do
    if i <= 10 then parts[#parts + 1] = format("%s %d%% (%s)", p[1], math.floor(p[2] * 100 + 0.5), how[p[3]]) end
  end
  print("your output (" .. (split.learned and "your damage meter" or "Skill Weights") .. "): " .. table.concat(parts, ", "))
  print("weapon talents: " .. (#s.tal.names > 0 and table.concat(s.tal.names, ", ") or "none that depend on the weapon"))
  local land, miss, dodge, crit = Landing(Hit(s), Crit(s), DW(s), s.expertise)
  print(format("against an enemy your level: %.1f%% miss, %.1f%% dodge, %d%% glancing, %.1f%% crit = %.0f%% of your swings' damage lands",
    miss * 100, dodge * 100, R.glance, crit * 100, land * 100))
  print(format("melee damage per second: %.1f. Worth: +10 Strength %.2f%%, +10 Agility %.2f%%, +10 attack power %.2f%%, +1%% crit %.2f%%, +1%% hit %.2f%%",
    M.Dps(s), M.PerUnit("STR", s) * 10, M.PerUnit("AGI", s) * 10, M.PerUnit("AP", s) * 10, M.PerUnit("CRIT", s), M.PerUnit("HIT", s)))
end
