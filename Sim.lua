-- Your damage (or healing) per second, worked out from your spells, and what an item does to it.
--
--   Rotation: Forever Upgrades' rotation for your spec, as its simulator plays it at your level
--             (Guides.lua): which abilities, and how often each is used (casts a minute).
--   Spells:   each ability's numbers from Forever's own spell tables (Spells.lua, refreshed every week:
--             base damage or healing for your rank and level, spell power and attack power
--             coefficients, weapon %, ticks, cooldown). Casts are capped by the real cooldown, so a
--             patch that slows a spell down is picked up even when the site's sim hasn't caught up.
--   You:      your live numbers (attack power, spell power, healing, crit, hit, haste, weapons).
--
-- DPS = auto attack (or Auto Shot) + every ability's damage per cast x casts a minute / 60.
-- What has no spell of its own (pets, poisons, Windfury, Deep Wounds, Ignite, totems...) keeps the
-- site's share of the total and moves with your auto attack (melee), spells or healing.
-- An item's value: the % change in that number from wearing it, plus its other stats (Stamina,
-- Intellect...) through Forever Upgrades' weights and your priorities, plus its effects.
-- Tanks and feral druids are scored by the weights alone.
local _, ns = ...
local M = {}
ns.Sim = M
local Readable = ns.Readable

-- The enemy's side: Classic rules, against an enemy your level.
M.RULES = {
  miss = 5.0,          -- % a melee swing or ability misses
  dualWieldMiss = 19,  -- % more for white swings while dual wielding
  dodge = 5.0,         -- % it dodges (expertise takes it down)
  glance = 10,         -- % of white swings that glance...
  glanceDamage = 0.95, -- ...for this much damage
  critDamage = 2.0,    -- a melee or ranged crit
  spellCritDamage = 1.5, -- a spell or heal crit
  spellMiss = 4.0,     -- % a spell misses
  offHand = 0.5,       -- the off hand does this much
  apPerDps = 14,       -- attack power per 1 damage per second
}
local R = M.RULES
-- normalized weapon speeds (strikes that say "normalized" use these for attack power)
local NORMAL = { twoHand = 3.3, dagger = 1.7, oneHand = 2.4, ranged = 2.8 }

-- scored by the weights alone: tanks (the site sims damage taken) and feral (form attacks)
local WEIGHTS_ONLY = { ["WARRIOR:3"] = true, ["PALADIN:2"] = true, ["DRUID:2"] = true }
-- hunters who fight at range: their weapon strikes use the ranged weapon
local RANGED = { ["HUNTER:1"] = true, ["HUNTER:2"] = true }
-- the stats the model works out (the rest go through the weights)
local MODEL = { STR = true, AGI = true, AP = true, RAP = true, SP = true, HEAL = true, CRIT = true, SPELLCRIT = true,
  HIT = true, SPELLHIT = true, HASTE = true, DPS = true, EXPERTISE = true }
M.MODEL = MODEL

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok or not Readable(a) then return nil end
  return a, b, c
end
local function Num(v) return (type(v) == "number" and Readable(v)) and v or 0 end
local function Copy(s) local t = {} for k, v in pairs(s) do t[k] = type(v) == "table" and Copy(v) or v end return t end

function M.Active()
  if not (ns.GUIDE and ns.SPELLS) or WEIGHTS_ONLY[ns.SpecKey()] then return false end
  local g = ns.GUIDE[ns.SpecKey()]
  return g ~= nil and g.levels ~= nil and UnitAttackPower ~= nil
end
function M.Unit() local g = ns.GUIDE and ns.GUIDE[ns.SpecKey()]; return g and g.unit or "DPS" end

---------------------------------------------------------------------------
-- You
---------------------------------------------------------------------------
-- A weapon: damage per second, base speed, two-handed, dagger
local function Weapon(link)
  local f = link and ns.Score.Facts(link)
  if not (f and f.stats and f.stats.DPS and f.stats.DPS > 0) then return nil end
  local sub = C_Item and C_Item.GetItemInfoInstant and select(7, C_Item.GetItemInfoInstant(link))
  return { dps = f.stats.DPS, speed = f.speed or 2.5, twoHand = f.equipLoc == "INVTYPE_2HWEAPON", dagger = sub == 15,
    ranged = f.equipLoc == "INVTYPE_RANGED" or f.equipLoc == "INVTYPE_RANGEDRIGHT" or f.equipLoc == "INVTYPE_THROWN" }
end
M.Weapon = Weapon

-- schools: 1 physical, 2 holy, 3 fire, 4 nature, 5 frost, 6 shadow, 7 arcane (GetSpellBonusDamage's numbers)
local function School(mask)
  local best, i, bit = 1, 1, 1
  mask = tonumber(mask) or 1
  while bit <= 64 do
    if mask % (bit * 2) >= bit then best = i end
    i, bit = i + 1, bit * 2
  end
  return best
end

-- your character right now
function M.State()
  local s = { sp = {}, scrit = {} }
  s.level = UnitLevel and UnitLevel("player") or 60
  local b, p, n = Call(UnitAttackPower, "player"); s.ap = Num(b) + Num(p) + Num(n)
  b, p, n = Call(UnitRangedAttackPower, "player"); s.rap = Num(b) + Num(p) + Num(n)
  s.crit = Num(Call(GetCritChance))
  s.rcrit = GetRangedCritChance and Num(Call(GetRangedCritChance)) or s.crit
  for i = 2, 7 do
    s.sp[i] = GetSpellBonusDamage and Num(Call(GetSpellBonusDamage, i)) or 0
    s.scrit[i] = GetSpellCritChance and Num(Call(GetSpellCritChance, i)) or 0
  end
  s.heal = GetSpellBonusHealing and Num(Call(GetSpellBonusHealing)) or 0
  local bonus = function(cr) return (cr and GetCombatRatingBonus) and Num(Call(GetCombatRatingBonus, cr)) or 0 end
  s.hit = bonus(CR_HIT_MELEE or 6) + Num(Call(GetHitModifier))
  s.rhit = bonus(CR_HIT_RANGED or 7) + Num(Call(GetHitModifier))
  s.shit = bonus(CR_HIT_SPELL or 8) + (GetSpellHitModifier and Num(Call(GetSpellHitModifier)) or 0)
  s.haste = Num(Call(GetMeleeHaste))
  s.rhaste = GetRangedHaste and Num(Call(GetRangedHaste)) or s.haste
  s.shaste = (UnitSpellHaste and Num(Call(UnitSpellHaste, "player"))) or bonus(CR_HASTE_SPELL or 20)
  s.expertise = Num(Call(GetExpertise))
  -- what 1 Strength / Agility give you (from 100, for the decimals)
  s.apPerStr = Num(Call(GetAttackPowerForStat, 1, 100)) / 100
  s.apPerAgi = Num(Call(GetAttackPowerForStat, 2, 100)) / 100
  s.rapPerAgi = (ns.Class() == "HUNTER") and 2 or 0 -- (Classic: hunters get 2 ranged attack power per Agility)
  s.critPerAgi = Num(Call(GetCritChanceFromStat, 2, 100))
  local link = function(slot) return GetInventoryItemLink and GetInventoryItemLink("player", slot) end
  s.mh, s.oh, s.rw = Weapon(link(16)), Weapon(link(17)), Weapon(link(18))
  if s.oh and not s.oh.dps then s.oh = nil end
  return s
end

---------------------------------------------------------------------------
-- Hits
---------------------------------------------------------------------------
-- a white swing's average after misses, dodges, glancing blows and crits
local function WhiteLanding(s, dw)
  local miss = math.max(0, R.miss + (dw and R.dualWieldMiss or 0) - s.hit) / 100
  local dodge = math.max(0, R.dodge - s.expertise) / 100
  local glance = R.glance / 100
  local c = math.max(0, math.min(s.crit / 100, 1 - miss - dodge - glance))
  return 1 - miss - dodge - glance * (1 - R.glanceDamage) + c * (R.critDamage - 1)
end
-- an ability's (melee or ranged): misses, dodges, crits
local function StrikeLanding(s, ranged)
  local miss = math.max(0, R.miss - (ranged and s.rhit or s.hit)) / 100
  local dodge = ranged and 0 or math.max(0, R.dodge - s.expertise) / 100
  local c = math.max(0, math.min((ranged and s.rcrit or s.crit) / 100, 1 - miss - dodge))
  return 1 - miss - dodge + c * (R.critDamage - 1)
end
-- a spell's: misses, crits (heals don't miss)
local function SpellLanding(s, school, heal)
  local hit = heal and 1 or (1 - math.max(1, R.spellMiss - s.shit) / 100)
  return hit * (1 + (s.scrit[school] or 0) / 100 * (R.spellCritDamage - 1))
end

-- auto attack per second: melee (both hands), or Auto Shot for ranged hunters
function M.WhiteDps(s, ranged)
  if ranged then
    local w = s.rw
    if not w then return 0 end
    return (w.dps + s.rap / R.apPerDps) * (1 + s.rhaste / 100) * StrikeLanding(s, true)
  end
  if not s.mh then return 0 end
  local dw = s.oh ~= nil
  local function hand(w) return (w.dps + s.ap / R.apPerDps) * (1 + s.haste / 100) end
  local total = hand(s.mh) * WhiteLanding(s, dw)
  if dw then total = total + hand(s.oh) * R.offHand * WhiteLanding(s, true) end
  return total
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
local byName
local function Ranks(name)
  if not byName then
    byName = {}
    for id, d in pairs(ns.SPELLS or {}) do
      local k = d[1]:lower()
      byName[k] = byName[k] or {}
      table.insert(byName[k], id)
    end
    for _, list in pairs(byName) do table.sort(list, function(a, b) return (ns.SPELLS[a][2] or 0) < (ns.SPELLS[b][2] or 0) end) end
  end
  return byName[(name or ""):lower()]
end
-- the rank you have: the game's answer (your spellbook), else the highest your level allows
function M.Rank(name, level)
  local list = Ranks(name)
  if not list then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and type(info) == "table" and Readable(info.spellID) and ns.SPELLS[info.spellID] then return info.spellID, true end
  end
  -- (Forever also has variants of some spells for talents and procs, with IDs in the 400000s:
  -- the trainer ranks come first)
  local best, variant
  for _, id in ipairs(list) do
    if (ns.SPELLS[id][2] or 0) <= level then if id < 400000 then best = id else variant = id end end
  end
  return best or variant, false
end

-- one cast's damage (or healing), on average, for state s; and whether it heals
function M.CastAmount(id, s, ranged)
  local d = ns.SPELLS[id]
  if not d then return nil end
  local _, baseLvl, maxLvl, mask, _, _, dur = d[1], d[2] or 0, d[3] or 0, d[4], d[5], d[6], d[7] or 0
  local level = (maxLvl > 0) and math.min(s.level, maxLvl) or s.level
  local over = math.max(0, level - baseLvl)
  local school = School(mask)
  local physical = school == 1
  local sp = physical and 0 or (s.sp[school] or 0)
  local direct, periodic, heal, hot = 0, 0, 0, 0
  local weapon, flat, pct, normalized = false, 0, 100, false
  for _, e in ipairs(d[8] or {}) do
    local t, aura, bp, ppl, spc, apc, period, ppr = e[1], e[2], e[3] or 0, e[4] or 0, e[5] or 0, e[6] or 0, e[7] or 0, e[8] or 0
    local pts = bp + ppl * over + ppr * 5 -- (finishers: at 5 combo points)
    local ap = ranged and s.rap or s.ap
    if t == 2 then
      direct = direct + pts + sp * spc + ap * apc
    elseif t == 10 then
      heal = heal + pts + s.heal * spc
    elseif t == 31 then
      weapon = true; pct = pct * pts / 100
    elseif t == 121 or t == 58 or t == 17 then
      weapon = true; flat = flat + pts; if t == 121 then normalized = true end
    elseif t == 6 then
      local ticks = (period > 0 and dur > 0) and math.max(1, math.floor(dur / period)) or 1
      if aura == 3 then periodic = periodic + ticks * (pts + sp * spc + ap * apc)
      elseif aura == 8 then hot = hot + ticks * (pts + s.heal * spc)
      elseif aura == 69 then heal = heal + pts + s.heal * spc end -- (an absorb: counted as healing)
    end
  end
  local total, raw = 0, 0 -- (raw: an average hit, before crits and misses: what the tooltip shows)
  if weapon then
    local w = ranged and s.rw or s.mh
    if w then
      local speed = normalized and ((w.ranged and NORMAL.ranged) or (w.twoHand and NORMAL.twoHand) or (w.dagger and NORMAL.dagger) or NORMAL.oneHand) or w.speed
      local ap = ranged and s.rap or s.ap
      local hit = (w.dps * w.speed + ap * speed / R.apPerDps + flat) * pct / 100
      raw = raw + hit
      total = total + hit * StrikeLanding(s, ranged)
    end
  end
  raw = raw + direct + periodic + heal + hot
  if direct > 0 then total = total + direct * (physical and StrikeLanding(s, ranged) or SpellLanding(s, school)) end
  if periodic > 0 then total = total + periodic * (physical and 1 or SpellLanding(s, school) / (1 + (s.scrit[school] or 0) / 100 * (R.spellCritDamage - 1))) end
  local healing = heal * SpellLanding(s, school, true) + hot
  return total + healing, healing > total, raw
end

-- a spell's cooldown, in seconds: the game's, else Forever's tables
local function Cooldown(id)
  if GetSpellBaseCooldown then
    local ok, ms = pcall(GetSpellBaseCooldown, id)
    if ok and Readable(ms) and type(ms) == "number" and ms > 0 then return ms / 1000 end
  end
  local d = ns.SPELLS[id]
  return d and (d[6] or 0) / 1000 or 0
end

---------------------------------------------------------------------------
-- Your rotation, played with your numbers
---------------------------------------------------------------------------
local PET = function(n) return n:find(":", 1, true) or n:lower():find("^pet") or n == "Hawks" end
local CAP_SLACK = 1.2 -- (casts are capped by the cooldown only past this: talents shorten some cooldowns)

-- the rotation for state s: { parts = { { name, perMin, kind ("white" / "spell" / "other" / "pet"), cpm, id } }, total (per second) }
-- base: your current state (the scale for what has no spell of its own, and haste); nil = s itself
function M.Play(s, base)
  base = base or s
  local key = ns.SpecKey()
  local g = ns.GUIDE and ns.GUIDE[key]
  local site = g and g.levels and ns.Rotation.AtLevel(g.levels, s.level)
  if not site then return nil end
  local ranged = RANGED[key]
  local heals = g.unit == "HPS"
  local parts, known, knownShare, other = {}, 0, 0, {}
  for _, p in ipairs(site) do
    local name, share, cpm = p[1], p[2], p[3]
    local e = { name, 0, "other", cpm, nil, share }
    if name == "Attack" or name == "Auto Shot" then
      local r = ranged or name == "Auto Shot"
      e[2], e[3] = M.WhiteDps(s, r) * 60, "white"
      -- (an average swing, and swings a minute: main hand, or the ranged weapon)
      local w = r and s.rw or s.mh
      if w then
        e[7] = w.dps * w.speed + (r and s.rap or s.ap) * w.speed / R.apPerDps
        e[8] = 60 * (1 + (r and s.rhaste or s.haste) / 100) / w.speed * ((not r and s.oh) and 2 or 1)
      end
    elseif PET(name) then
      e[3] = "pet"
    else
      local id = cpm > 0 and M.Rank(name, s.level)
      if id then
        local amount, _, raw = M.CastAmount(id, s, ranged)
        e[7] = raw
        local cd = Cooldown(id)
        if cd > 0 and cpm > 60 / cd * CAP_SLACK then cpm = 60 / cd end -- (a longer cooldown than the site's sim)
        local d = ns.SPELLS[id]
        if (d[5] or 0) > 0 and (d[6] or 0) == 0 and base.shaste then -- (a cast-time filler: haste fits more in)
          cpm = cpm * (1 + s.shaste / 100) / (1 + base.shaste / 100)
        end
        if amount and amount > 0 then e[2], e[3], e[4], e[5] = amount * cpm, "spell", cpm, id end
      end
    end
    if e[3] == "white" or e[3] == "spell" then known, knownShare = known + e[2], knownShare + share end
    parts[#parts + 1] = e
  end
  -- what has no spell of its own: the site's share, at your scale; it moves with your auto attack
  -- (melee, ranged), your spells (casters) or your healing
  local scale = (knownShare > 0) and known / knownShare or 0
  for _, e in ipairs(parts) do
    if e[3] == "other" or e[3] == "pet" then e[2] = e[6] * scale end
  end
  local total = 0
  for _, e in ipairs(parts) do total = total + e[2] end
  return { parts = parts, total = total / 60, heals = heals, ranged = ranged }
end

-- your number for state s, with what has no spell of its own following the right part from `base`
function M.Total(s, base)
  base = base or s
  local now, cur = M.Play(s, base), (base == s) and nil or M.Play(base, base)
  if not now then return 0 end
  if not cur then return now.total end
  -- the "other" parts: scaled as at your current state, then moved with their driver
  local function part(play, kind) local t = 0 for _, e in ipairs(play.parts) do if e[3] == kind then t = t + e[2] end end return t end
  local driverNow, driverCur
  if now.heals or not (base.mh or base.rw) then driverNow, driverCur = part(now, "spell"), part(cur, "spell")
  else driverNow, driverCur = part(now, "white"), part(cur, "white") end
  local total = 0
  for i, e in ipairs(now.parts) do
    local c = cur.parts[i]
    if e[3] == "other" then
      total = total + (c and c[2] or 0) * ((driverCur > 0) and driverNow / driverCur or 1)
    elseif e[3] == "pet" then
      total = total + (c and c[2] or 0)
    else
      total = total + e[2]
    end
  end
  return total / 60
end

-- your split for item effects on skills: { { name, share, cpm } }
function M.Breakdown()
  local s = M.Cached()
  local play = M.Play(s)
  if not (play and play.total > 0) then return nil end
  local out = {}
  for _, e in ipairs(play.parts) do out[#out + 1] = { e[1], e[2] / 60 / play.total, e[4] or 0 } end
  table.sort(out, function(a, b) return a[2] > b[2] end)
  return out
end

-- (your state, kept for a second: tooltips ask often)
local cached, cachedAt
function M.Cached()
  local now = GetTime and GetTime() or 0
  if not cached or now - (cachedAt or 0) > 1 then cached, cachedAt = M.State(), now end
  return cached
end
function M.Forget() cached = nil end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- `s` with `stats` added (sign 1) or taken away (sign -1)
local function Apply(s, stats, sign)
  local g = function(k) return (stats[k] or 0) * sign end
  s.ap = s.ap + g("STR") * s.apPerStr + g("AGI") * s.apPerAgi + g("AP")
  s.rap = s.rap + g("AGI") * s.rapPerAgi + g("RAP") + g("AP")
  s.crit = s.crit + g("AGI") * s.critPerAgi + g("CRIT")
  s.rcrit = s.rcrit + g("AGI") * s.critPerAgi + g("CRIT")
  s.hit = s.hit + g("HIT"); s.rhit = s.rhit + g("HIT"); s.shit = s.shit + g("SPELLHIT")
  for i = 2, 7 do s.sp[i] = s.sp[i] + g("SP"); s.scrit[i] = s.scrit[i] + g("SPELLCRIT") end
  s.heal = s.heal + g("HEAL") + g("SP") -- (Forever's spell power is damage and healing)
  s.haste = s.haste + g("HASTE"); s.rhaste = s.rhaste + g("HASTE"); s.shaste = s.shaste + g("HASTE")
  s.expertise = s.expertise + g("EXPERTISE")
end

-- your number with these items out and those in: { out = { link }, inn = { link }, mh / oh / rw = weapon or false }
-- -> the change in %, and the new state
function M.Change(swap, s)
  s = s or M.Cached()
  local before = M.Total(s)
  if before <= 0 then return nil end
  local t = Copy(s)
  for _, l in ipairs(swap.out or {}) do local f = ns.Score.Facts(l); if f then Apply(t, f.stats, -1) end end
  for _, l in ipairs(swap.inn or {}) do local f = ns.Score.Facts(l); if f then Apply(t, f.stats, 1) end end
  for _, k in ipairs({ "mh", "oh", "rw" }) do if swap[k] ~= nil then t[k] = swap[k] or nil end end
  return (M.Total(t, s) / before - 1) * 100, t
end

-- what 1 of a stat does to your number, in %
function M.PerUnit(key, s)
  s = s or M.Cached()
  local n = (key == "CRIT" or key == "HIT" or key == "HASTE" or key == "SPELLCRIT" or key == "SPELLHIT" or key == "EXPERTISE") and 1 or 10
  local before = M.Total(s)
  if before <= 0 then return 0 end
  local t = Copy(s)
  if key == "DPS" then
    if t.mh then t.mh.dps = t.mh.dps + n end
    if t.rw and RANGED[ns.SpecKey()] then t.rw.dps = t.rw.dps + n end
  else
    Apply(t, { [key] = n }, 1)
  end
  return (M.Total(t, s) / before - 1) * 100 / n
end

-- the exchange rate between the weights and %: what 1 point of weight is worth, from what your
-- spec's main stat does for your number (Forever Upgrades' own yardstick)
function M.Rate(s)
  local site = ns.PresetImportance(ns.SpecKey())
  local best, bestPts
  for _, k in ipairs({ "STR", "AGI", "SP", "HEAL", "AP" }) do
    local pts = ns.PointsPer(k, site[k])
    if pts > 0 and (not bestPts or pts > bestPts) then best, bestPts = k, pts end
  end
  if not best then return 0 end
  local per = M.PerUnit(best, s)
  return per > 0 and per / bestPts or 0
end

-- An item's value beyond the model's stats, in %: its other stats through the weights (with your
-- priorities), your priorities on the model's stats, and its effects
function M.Extra(f, weights, s, rate)
  if not f or rate <= 0 then return 0, {} end
  local site = ns.PresetImportance(ns.SpecKey())
  local pts, adj = 0, 0
  for k, v in pairs(f.stats) do
    if not MODEL[k] then
      pts = pts + v * ns.PointsPer(k, weights[k])
    elseif (weights[k] or 0) ~= (site[k] or 0) then
      -- a model stat you've moved (Higher, Ignore...): scale its model value by your change
      local base = site[k] or 0
      if base > 0 then adj = adj + v * M.PerUnit(k, s) * ((weights[k] or 0) / base - 1)
      else adj = adj + v * ns.PointsPer(k, weights[k]) * rate end
    end
  end
  local why, eff = {}, 0
  if ns.Effects and f.effects and #f.effects > 0 then
    -- effects score in weight points: give them the model's values, and 1% = 1/rate
    local w = {}
    for k, v in pairs(weights) do w[k] = v end
    for k in pairs(MODEL) do
      if ns.NORM[k] and ns.NORM[k] > 0 then w[k] = M.PerUnit(k, s) / rate * 5 / ns.NORM[k] end
    end
    local saved = ns.OUTPUT_PTS
    ns.OUTPUT_PTS = 1 / rate
    local ok, p, y = pcall(ns.Effects.Points, f, w)
    ns.OUTPUT_PTS = saved
    if ok then eff = (p or 0) * rate; why = y or {} end
  end
  return pts * rate + adj + eff, why
end

-- The % change from wearing `link` in place of `out` (links), weapons into the hand `hand`
-- ("mh" / "oh" / "rw"; a two-hander clears the off hand)
function M.Gain(link, out, weights, hand, s)
  s = s or M.Cached()
  local f = ns.Score.Facts(link)
  if not f then return nil end
  local swap = { out = out, inn = { link } }
  if hand then swap[hand] = Weapon(link) or false end
  if f.equipLoc == "INVTYPE_2HWEAPON" then swap.oh = false end
  local change = M.Change(swap, s)
  if not change then return nil end
  local rate = M.Rate(s)
  local gain = change + M.Extra(f, weights, s, rate)
  for _, l in ipairs(out or {}) do gain = gain - M.Extra(ns.Score.Facts(l), weights, s, rate) end
  return gain
end

---------------------------------------------------------------------------
-- The numbers, ability by ability (the DPS window, Options.lua)
---------------------------------------------------------------------------
-- { unit, total, stats = "...", rows = { { name, average hit (as the tooltip) or nil, casts or swings a minute or nil,
--   per second (with crits and misses), share, estimated } },
--   worth = { { label, % } } }, or nil and why
function M.ReportData()
  if not M.Active() then return nil, format("%s is scored by its stat weights.", ns.SpecName(ns.SpecKey())) end
  local s = M.Cached()
  local play = M.Play(s)
  if not (play and play.total > 0) then return nil, "No rotation for your spec at this level yet." end
  local sp, sc = 0, 0
  for i = 2, 7 do sp, sc = math.max(sp, s.sp[i] or 0), math.max(sc, s.scrit[i] or 0) end
  local data = { unit = M.Unit(), total = play.total, rows = {}, worth = {} }
  if play.heals then
    data.stats = format("Healing %d   Spell crit %.1f%%   Haste %.1f%%", s.heal, sc, s.shaste)
  elseif sp > s.ap then
    data.stats = format("Spell power %d   Spell crit %.1f%%   Spell hit %.1f%%   Haste %.1f%%", sp, sc, s.shit, s.shaste)
  else
    data.stats = format("Attack power %d   Crit %.1f%%   Hit %.1f%%   Haste %.1f%%", play.ranged and s.rap or s.ap,
      play.ranged and s.rcrit or s.crit, s.hit, s.haste)
  end
  local rows = {}
  for _, e in ipairs(play.parts) do
    local perSec = e[2] / 60
    if perSec > 0 then
      local spell, white = e[3] == "spell", e[3] == "white"
      rows[#rows + 1] = { e[1], (spell or white) and e[7] or nil,
        spell and e[4] or (white and e[8]) or nil, perSec, perSec / play.total, e[3] == "other" or e[3] == "pet" }
    end
  end
  table.sort(rows, function(a, b) return a[4] > b[4] end)
  data.rows = rows
  local list = play.heals and { { "HEAL", "+10 Healing" }, { "SP", "+10 Spell power" }, { "SPELLCRIT", "+1% Spell crit" }, { "HASTE", "+1% Haste" } }
    or { { "STR", "+10 Strength" }, { "AGI", "+10 Agility" }, { "AP", "+10 Attack power" }, { "SP", "+10 Spell power" },
         { "CRIT", "+1% Crit" }, { "SPELLCRIT", "+1% Spell crit" }, { "HIT", "+1% Hit" }, { "SPELLHIT", "+1% Spell hit" },
         { "HASTE", "+1% Haste" }, { "DPS", "+1 Weapon DPS" } }
  for _, w in ipairs(list) do
    local n = w[2]:find("^%+10") and 10 or 1
    local v = M.PerUnit(w[1], s) * n
    if v > 0.005 then data.worth[#data.worth + 1] = { w[2], v } end
  end
  return data
end

-- (as text, for chat)
function M.Report(print)
  local d, why = M.ReportData()
  if not d then print(why) return end
  print(format("your %s: %.1f", d.unit, d.total))
  for _, r in ipairs(d.rows) do print(format("  %s: %.1f per sec (%d%%)", r[1], r[4], r[5] * 100 + 0.5)) end
end
