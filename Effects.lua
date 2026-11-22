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
  { "[Ii]ncreases the damage dealt by ([%a' :,%-]+) by (%d+%.?%d*)%%", false }, -- "...dealt by your Stormstrike ability by 10%"
  { "[Ii]ncreases the healing dealt by ([%a' :,%-]+) by (%d+%.?%d*)%%", true },
  { "[Ii]ncreases the damage done by ([%a' :,%-]+) by (%d+%.?%d*)%%", false },
  { "[Ii]ncreases the damage of ([%a' :,%-]+) by (%d+%.?%d*)%%", false },
  { "[Ii]ncreases damage done by ([%a' :,%-]+) by (%d+%.?%d*)%%", false },
  { "[Ii]ncreases ([%a' :,%-]+) damage by (%d+%.?%d*)%%", false },
  { "[Ii]ncreases the healing done by ([%a' :,%-]+) by (%d+%.?%d*)%%", true },
  { "[Ii]ncreases the healing of ([%a' :,%-]+) by (%d+%.?%d*)%%", true },
  { "[Ii]ncreases ([%a' :,%-]+) healing by (%d+%.?%d*)%%", true },
}
-- "+X% crit chance to a spell": worth the spell's damage x X% x what a crit adds
local SPELL_CRIT = {
  "[Ii]ncreases the critical strike chance of ([%a' :,%-]+) by (%d+%.?%d*)%%",
  "[Ii]ncreases the crit chance of ([%a' :,%-]+) by (%d+%.?%d*)%%",
  "[Ii]ncreases the chance to crit with ([%a' :,%-]+) by (%d+%.?%d*)%%",
  "[Ii]ncreases the critical strike chance with ([%a' :,%-]+) by (%d+%.?%d*)%%",
  "[Ii]ncreases ([%a' :,%-]+) critical strike chance by (%d+%.?%d*)%%",
}
local function CleanSpellNames(name)
  name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^your ", ""):gsub("^the ", "")
    :gsub(" abilities$", ""):gsub(" ability$", ""):gsub(" spells$", ""):gsub(" spell$", "")
  local list = {}
  -- ("your critical strike chance", "spell critical strike chance": the whole character, not a spell)
  local NOT_A_SPELL = { [""] = true, your = true, spell = true, spells = true, melee = true, ranged = true, your_spell = true }
  for one in (name:gsub(" and ", ", ") .. ","):gmatch("%s*([^,]-)%s*,") do
    if not NOT_A_SPELL[one:lower()] then list[#list + 1] = one end
  end
  return list
end

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
      local critDone = false
      if body then
        for _, pat in ipairs(SPELL_CRIT) do
          local name, pct = body:match(pat)
          if name then
            for _, one in ipairs(CleanSpellNames(name)) do
              out[#out + 1] = { kind = "spellPct", spell = one, pct = tonumber(pct), crit = true, text = t }
            end
            critDone = true
            break
          end
        end
      end
      if body and not critDone then
        for _, p in ipairs(SPELL_PCT) do
          local name, pct = body:match(p[1])
          if name then
            -- "your Stormstrike ability", "Mortal Strike and Overpower", "A, B and C": one effect per spell
            for _, one in ipairs(CleanSpellNames(name)) do
              out[#out + 1] = { kind = "spellPct", spell = one, pct = tonumber(pct), heal = p[2], text = t }
            end
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
  if c then return c.avg, c.cd, c.heal, c.how, c.weapon end
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
  local weapon = (pct or plus or all:find("weapon damage")) and true or false
  if weapon then
    if hit then
      avg = hit * (tonumber(pct) or 100) / 100 + (tonumber(plus) or 0)
      how = format("%s weapon damage%s", pct and (pct .. "%") or "100%", plus and (" + " .. plus) or "")
    end
  end
  if not avg and not weapon then -- (a weapon strike with no weapon to read: no estimate)
    local a, b = all:match("(%d[%d,]*) to (%d[%d,]*)")
    if a then avg = (Num(a) + Num(b)) / 2; how = format("%s to %s", a, b) end
  end
  if not avg and not weapon then
    local n = all:match("for (%d[%d,]*)")
    if n then avg = Num(n); how = n end
  end
  heal = (all:lower():find("heal") ~= nil) and not all:lower():find("damage")
  local cd
  local n, unit = all:match("(%d+%.?%d*) (%a+) cooldown")
  if n then cd = Seconds(n, unit) end
  spellCache[key] = { avg = avg, cd = cd, heal = heal, how = how, weapon = weapon }
  return avg, cd, heal, how, weapon
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

-- 8 -> "8", 2.5 -> "2.5"
local function Secs(x) return (x == math.floor(x)) and tostring(x) or format("%.1f", x) end

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
    if not id then return 0, format("+%s%% %s: you don't know %s", e.pct, e.spell, e.spell) end
    local avg, tcd, heal, how, weapon = SpellUse(id, f)
    if not avg then
      return 0, format("+%s%% %s: %s", e.pct, e.spell, weapon and "no weapon to read its damage from" or "couldn't read its damage")
    end
    local spellCd = math.max(cd or 0, tcd or 0)
    -- does your spec actually spend time on it? A melee spec swings its weapons: it uses spells
    -- with a cooldown (on cooldown), not cast-time fillers; a caster doesn't use weapon strikes
    if melee and not weapon and spellCd <= GCD then
      return 0, format("+%s%% %s: a filler with no cooldown, and your spec fights in melee", e.pct, e.spell)
    end
    if not melee and weapon then
      return 0, format("+%s%% %s: a weapon strike, and your spec doesn't fight with weapons", e.pct, e.spell)
    end
    local every = math.max(spellCd, cast or 0, GCD)
    local gain = e.pct / 100
    local label = format("+%s%%", e.pct)
    if e.crit then -- a crit adds +100% for a weapon strike, +50% for a spell or heal
      local extra = weapon and 1 or 0.5
      gain = gain * extra
      label = format("+%s%% crit (crits add %d%%)", e.pct, extra * 100)
    end
    local per = avg / every * gain
    if heal or e.heal then
      return per * healPts, format("%s %s: %d healing every %ss (%s) = +%.1f HPS", label, e.spell, avg, Secs(every), how or "?", per)
    end
    return dmgPoints(per), format("%s %s: %d damage every %ss (%s) = +%.1f DPS", label, e.spell, avg, Secs(every), how or "?", per)
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
