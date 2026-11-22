-- Item effects that aren't plain stats: procs ("Chance on hit"), Use effects, and "+X% to a spell".
-- Each is estimated as what it adds for YOUR current spec, from live tooltips (the spell's own
-- tooltip on this client, your weapon, your attack power), then counted through your own
-- weights: extra damage per second like weapon DPS (or spell damage, for casters), extra healing
-- per second through Healing, stat buffs through that stat. An effect your spec can't use is
-- worth 0. Reads English tooltips, as the Equip-line stats do.
local _, ns = ...
local E = {}
ns.Effects = E
local Readable = ns.Readable

local PPM = 1        -- "Chance on hit" with no stated chance: about once a minute (Classic's usual rate)
local GCD = 1.5      -- the fastest a spell can be used again
local SP_PER_DPS = 3.5 -- 1 damage (or healing) per second is about 3.5 spell power for a full-time caster

-- words on tooltips -> our stat keys (for "increases your X by N")
local STAT_WORDS = {
  ["attack power"] = "AP", ["ranged attack power"] = "RAP", ["strength"] = "STR", ["agility"] = "AGI",
  ["stamina"] = "STA", ["intellect"] = "INT", ["spirit"] = "SPI", ["armor"] = "ARMOR",
  ["spell damage"] = "SP", ["spell power"] = "SP",
  ["damage and healing done by magical spells and effects"] = "SP",
  ["healing done by spells and effects"] = "HEAL", ["healing"] = "HEAL",
}

local function Num(s) return tonumber((s or ""):gsub(",", ""), 10) end

-- a duration "15 sec" / "2 min" -> seconds
local function Seconds(n, unit)
  n = tonumber(n)
  if not n then return nil end
  unit = (unit or ""):lower()
  if unit:find("^min") then return n * 60 end
  if unit:find("^hour") or unit:find("^hr") then return n * 3600 end
  return n
end

-- "increases your attack power by 300 for 10 sec" -> "AP", 300, 10 (or nil)
local function StatBuff(text)
  local what, n, d, unit = text:match("[Ii]ncreases? your ([%a ]-) by (%d+) for (%d+) (%a+)")
  if not what then what, n, d, unit = text:match("[Ii]ncreases? ([%a ]-) by up to (%d+) for (%d+) (%a+)") end
  if not what then what, n, d, unit = text:match("[Ii]ncreases? ([%a ]-) by (%d+) for (%d+) (%a+)") end
  if not what then return nil end
  local key = STAT_WORDS[what:lower():gsub("^%s+", ""):gsub("%s+$", "")]
  if not key then return nil end
  return key, tonumber(n), Seconds(d, unit)
end

-- "attack speed by 20% for 15 sec" -> 20, 15
local function Haste(text)
  local p, d, unit = text:match("attack speed by (%d+)%% for (%d+) (%a+)")
  if p then return tonumber(p), Seconds(d, unit) end
end

-- the average of "X to Y" / "X" damage in a text, or nil
local function AvgDamage(text)
  local a, b = text:match("(%d[%d,]*) to (%d[%d,]*)")
  if a and text:find("[Dd]amage") then return (Num(a) + Num(b)) / 2 end
  local n = text:match("(%d[%d,]*) %a* ?[Dd]amage") or text:match("[Dd]amage of (%d[%d,]*)") or text:match("for (%d[%d,]*)")
  if n and text:find("[Dd]amage") then return Num(n) end
end

-- "+10% to a spell": the spell's name and the %, and whether it's healing
local SPELL_PCT = {
  { "[Ii]ncreases the damage done by ([%a' :%-]+) by (%d+)%%", false },
  { "[Ii]ncreases the damage of ([%a' :%-]+) by (%d+)%%", false },
  { "[Ii]ncreases damage done by ([%a' :%-]+) by (%d+)%%", false },
  { "[Ii]ncreases ([%a' :%-]+) damage by (%d+)%%", false },
  { "[Ii]ncreases the healing done by ([%a' :%-]+) by (%d+)%%", true },
  { "[Ii]ncreases the healing of ([%a' :%-]+) by (%d+)%%", true },
  { "[Ii]ncreases ([%a' :%-]+) healing by (%d+)%%", true },
}

-- An item's effects from its tooltip lines (left texts). Each: a table with kind and its numbers.
function E.Parse(texts)
  local out = {}
  for _, t in ipairs(texts) do
    if Readable(t) and type(t) == "string" then
      local body = t:match("^Chance on hit: ?(.*)")
      if body then
        local chance = tonumber(body:match("(%d+)%% chance"))
        local key, n, d = StatBuff(body)
        local hp, hd = Haste(body)
        if key then out[#out + 1] = { kind = "procStat", stat = key, amount = n, dur = d, chance = chance, text = t }
        elseif hp then out[#out + 1] = { kind = "procHaste", pct = hp, dur = hd, chance = chance, text = t }
        else
          local avg = AvgDamage(body)
          if avg then out[#out + 1] = { kind = "procDamage", avg = avg, chance = chance, text = t } end
        end
      end
      body = t:match("^Use: ?(.*)")
      if body then
        local key, n, d = StatBuff(body)
        local cd, unit = body:match("%((%d+) (%a+) [Cc]ooldown%)")
        local cds = Seconds(cd, unit)
        if key and cds and cds > 0 then out[#out + 1] = { kind = "useStat", stat = key, amount = n, dur = d, cd = cds, text = t } end
      end
      body = t:match("^Equip: ?(.*)")
      if body then
        for _, p in ipairs(SPELL_PCT) do
          local name, pct = body:match(p[1])
          if name then
            name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^your ", "")
            out[#out + 1] = { kind = "spellPct", spell = name, pct = tonumber(pct), heal = p[2], text = t }
            break
          end
        end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- What you have: your weapon, attack power, spells
---------------------------------------------------------------------------
local lastAP -- the last attack power that read as a number (it can be hidden in combat)
local function AttackPower()
  if UnitAttackPower then
    local ok, base, pos, neg = pcall(UnitAttackPower, "player")
    if ok and Readable(base) and type(base) == "number" then
      lastAP = base + ((Readable(pos) and pos) or 0) + ((Readable(neg) and neg) or 0)
    end
  end
  return lastAP or 0
end

-- a weapon's average hit (with attack power, as Classic adds it: AP / 14 per second of speed),
-- its speed and its DPS: from facts (an item being looked at), or the main hand you wear
local function WeaponHit(f)
  local wf = f
  if not (wf and wf.stats and wf.stats.DPS and wf.speed) then
    local mh = GetInventoryItemLink and GetInventoryItemLink("player", 16)
    wf = mh and ns.Score.Facts(mh)
  end
  if not (wf and wf.stats and wf.stats.DPS and wf.speed) then return nil end
  local speed, dps = wf.speed, wf.stats.DPS
  return dps * speed + AttackPower() / 14 * speed, speed, dps
end

local spellCache = {}
function E.ClearCache() wipe(spellCache) end

-- a spell you know: its ID, cast time (s) and cooldown (s), or nil if you don't know it
local function KnownSpell(name)
  if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
  local ok, info = pcall(C_Spell.GetSpellInfo, name)
  if not (ok and type(info) == "table" and info.spellID) then return nil end
  local id = info.spellID
  if IsPlayerSpell then
    local okK, known = pcall(IsPlayerSpell, id)
    if okK and Readable(known) and not known then return nil end
  end
  local cast = (Readable(info.castTime) and tonumber(info.castTime) or 0) / 1000
  local cd = 0
  if GetSpellBaseCooldown then
    local okC, ms = pcall(GetSpellBaseCooldown, id)
    if okC and Readable(ms) and type(ms) == "number" then cd = ms / 1000 end
  end
  return id, cast, cd
end

-- a spell's average hit (or heal) per use, from its tooltip on this client, with f's weapon
-- for "weapon damage"; and its cooldown if the tooltip says one
local function SpellUse(id, f)
  local hit = WeaponHit(f)
  local key = id .. ":" .. tostring(hit and math.floor(hit * 10) or "-") -- (per weapon hit: two weapons can share a speed)
  local c = spellCache[key]
  if c then return c.avg, c.cd, c.heal, c.how end
  local texts = {}
  if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
    local ok, data = pcall(C_TooltipInfo.GetSpellByID, id)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, l in ipairs(data.lines) do
        if Readable(l.leftText) then texts[#texts + 1] = l.leftText end
        if Readable(l.rightText) then texts[#texts + 1] = l.rightText end
      end
    end
  end
  local all = table.concat(texts, " \n ")
  local avg, how, heal
  local pct = all:match("(%d+)%% weapon damage") or all:match("(%d+)%% of weapon damage")
  local plus = all:match("weapon damage plus (%d+)") or all:match("weapon damage %+ ?(%d+)")
  if pct or plus or all:find("weapon damage") then
    if hit then
      avg = hit * (tonumber(pct) or 100) / 100 + (tonumber(plus) or 0)
      how = format("%s weapon damage%s", pct and (pct .. "%") or "100%", plus and (" + " .. plus) or "")
    end
  end
  if not avg then
    local a, b = all:match("(%d[%d,]*) to (%d[%d,]*)")
    if a then avg = (Num(a) + Num(b)) / 2; how = format("%s to %s", a, b) end
  end
  if not avg then
    local n = all:match("for (%d[%d,]*)")
    if n then avg = Num(n); how = n end
  end
  heal = (all:lower():find("heal") ~= nil) and not all:lower():find("damage")
  local cd
  local n, unit = all:match("(%d+%.?%d*) (%a+) cooldown")
  if n then cd = Seconds(n, unit) end
  spellCache[key] = { avg = avg, cd = cd, heal = heal, how = how }
  return avg, cd, heal, how
end

---------------------------------------------------------------------------
-- Value for your spec
---------------------------------------------------------------------------
-- how a spec turns extra damage / healing per second into points (your weights decide)
local function Rates(weights)
  local dpsPts = ns.PointsPer("DPS", weights.DPS)
  local spPts = ns.PointsPer("SP", weights.SP) * SP_PER_DPS
  local healPts = ns.PointsPer("HEAL", weights.HEAL) * SP_PER_DPS
  return dpsPts, spPts, healPts
end

local function SwingsPerMin(f)
  local _, speed = WeaponHit(f)
  return 60 / (speed or 2.5)
end

-- one effect: its points for these weights, and a line saying how
function E.Value(e, weights, f)
  local dpsPts, spPts, healPts = Rates(weights)
  local melee = dpsPts > 0 -- your spec gets value from hitting with weapons
  local function dmgPoints(dps) return melee and dps * dpsPts or dps * spPts end
  if e.kind == "procDamage" or e.kind == "procStat" or e.kind == "procHaste" then
    if not melee then return 0, "Chance on hit: your spec doesn't hit with weapons" end
    local perMin = e.chance and (e.chance / 100 * SwingsPerMin(f)) or PPM
    if e.kind == "procDamage" then
      local dps = e.avg * perMin / 60
      return dps * dpsPts, format("Chance on hit: %d damage x %.1f/min = +%.1f DPS", e.avg, perMin, dps)
    end
    local uptime = math.min(1, (e.dur or 0) * perMin / 60)
    if e.kind == "procStat" then
      local avg = e.amount * uptime
      return avg * ns.PointsPer(e.stat, weights[e.stat]), format("Chance on hit: +%d %s, up %d%% of the time = +%.0f on average",
        e.amount, ns.STAT_NAMES[e.stat] or e.stat, uptime * 100 + 0.5, avg)
    end
    local hit, speed, wdps = WeaponHit(f)
    if not hit then return 0, "Chance on hit (attack speed): no weapon to read" end
    local white = hit / speed
    local dps = white * e.pct / 100 * uptime
    return dps * dpsPts, format("Chance on hit: +%d%% attack speed, up %d%% of the time = +%.1f DPS", e.pct, uptime * 100 + 0.5, dps)
  end
  if e.kind == "useStat" then
    local uptime = math.min(1, (e.dur or 0) / e.cd)
    local avg = e.amount * uptime
    return avg * ns.PointsPer(e.stat, weights[e.stat]), format("Use: +%d %s for %ds every %ds = +%.0f on average",
      e.amount, ns.STAT_NAMES[e.stat] or e.stat, e.dur or 0, e.cd, avg)
  end
  if e.kind == "spellPct" then
    local id, cast, cd = KnownSpell(e.spell)
    if not id then return 0, format("+%d%% %s: you don't know %s", e.pct, e.spell, e.spell) end
    local avg, tcd, heal, how = SpellUse(id, f)
    if not avg then return 0, format("+%d%% %s: couldn't read its damage", e.pct, e.spell) end
    local every = math.max(cd or 0, tcd or 0, cast or 0, GCD)
    local per = avg / every * e.pct / 100
    if heal or e.heal then
      return per * healPts, format("+%d%% %s: %d healing every %.0fs (%s) = +%.1f HPS", e.pct, e.spell, avg, every, how or "?", per)
    end
    return dmgPoints(per), format("+%d%% %s: %d damage every %.0fs (%s) = +%.1f DPS", e.pct, e.spell, avg, every, how or "?", per)
  end
  return 0, nil
end

-- all of an item's effects: total points, and the lines saying how
function E.Points(f, weights)
  if not (f and f.effects and #f.effects > 0) then return 0, nil end
  local total, why = 0, {}
  for _, e in ipairs(f.effects) do
    local p, w = E.Value(e, weights, f)
    total = total + (p or 0)
    if w then why[#why + 1] = w end
  end
  return total, why
end
