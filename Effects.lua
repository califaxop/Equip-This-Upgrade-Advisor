-- Item effects that aren't plain stats: procs ("Chance on hit"), Use effects, and "+X% to a skill".
-- Procs: extra damage as DPS through your Weapon Damage weight (about once a minute unless the text
-- says otherwise), stat buffs through that stat's weight by how long they're up. Skill effects
-- ("+10% Stormstrike", "+1% crit chance of Healing Wave", "-1 sec cooldown") count by that skill's
-- share of your output (its relative weight in your skill list, Weights.lua), read as a % of the
-- skill from its live tooltip where needed. Reads English tooltips, as the Equip-line stats do.
local _, ns = ...
local E = {}
ns.Effects = E
local Readable = ns.Readable

local PPM = 1        -- "Chance on hit" with no stated chance: about once a minute (Classic's usual rate)
local GCD = 1.5      -- the fastest a spell can be used again

-- words on tooltips -> our stat keys (for "increases your X by N")
local STAT_WORDS = {
  ["attack power"] = "AP", ["ranged attack power"] = "RAP", ["strength"] = "STR", ["agility"] = "AGI",
  ["stamina"] = "STA", ["intellect"] = "INT", ["spirit"] = "SPI", ["armor"] = "ARMOR",
  ["spell damage"] = "SP", ["spell power"] = "SP",
  ["damage and healing done by magical spells and effects"] = "SP",
  ["healing done by spells and effects"] = "HEAL", ["healing"] = "HEAL",
  ["spell damage and healing"] = "SP", ["damage and healing"] = "SP", ["ranged attack"] = "RAP",
  ["dodge rating"] = "DODGE", ["defense"] = "DEF", ["block value"] = "BLOCKVALUE",
  -- % buffs: "grants 5% critical strike chance for 10 sec", "increases your chance to hit by 2% for 20 sec"
  ["critical strike chance"] = "CRIT", ["crit chance"] = "CRIT", ["chance to critically hit"] = "CRIT",
  ["chance to crit"] = "CRIT", ["critical strike"] = "CRIT", ["melee critical strike chance"] = "CRIT",
  ["hit chance"] = "HIT", ["chance to hit"] = "HIT", ["melee hit chance"] = "HIT",
  ["spell critical strike chance"] = "SPELLCRIT", ["spell crit chance"] = "SPELLCRIT",
  ["chance to critically hit with spells"] = "SPELLCRIT", ["chance to get a critical strike with spells"] = "SPELLCRIT",
  ["spell hit chance"] = "SPELLHIT", ["chance to hit with spells"] = "SPELLHIT",
  ["dodge chance"] = "DODGE", ["chance to dodge"] = "DODGE", ["parry chance"] = "PARRY", ["chance to parry"] = "PARRY",
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
-- (amounts can be "300", "2.5" or "5%"; a % buff reads as that many points of the % stat)
local function StatBuff(text)
  local N, D = "(%d+%.?%d*)%%?", "(%d+%.?%d*) (%a+)"
  local what, n, d, unit = text:match("[Ii]ncreases? your ([%a ]-) by up to " .. N .. " for " .. D)
  if not what then what, n, d, unit = text:match("[Ii]ncreases? your ([%a ]-) by " .. N .. " for " .. D) end
  if not what then what, n, d, unit = text:match("[Ii]ncreases? ([%a ]-) by up to " .. N .. " for " .. D) end
  if not what then what, n, d, unit = text:match("[Ii]ncreases? ([%a ]-) by " .. N .. " for " .. D) end
  -- "grants 300 attack power for 10 sec", "you gain 120 Agility for 30 sec", "+40 Strength for 20 sec",
  -- "grants 5% critical strike chance for 10 sec", "grants you a 3% chance to hit for 15 sec"
  if not what then n, what, d, unit = text:match("[Gg]rants? you an? " .. N .. " ([%a ]-) for " .. D) end
  if not what then n, what, d, unit = text:match("[Gg]rants? you " .. N .. " ([%a ]-) for " .. D) end
  if not what then n, what, d, unit = text:match("[Gg]rants? an? " .. N .. " ([%a ]-) for " .. D) end
  if not what then n, what, d, unit = text:match("[Gg]rants? " .. N .. " ([%a ]-) for " .. D) end
  if not what then n, what, d, unit = text:match("[Gg]ain an? " .. N .. " ([%a ]-) for " .. D) end
  if not what then n, what, d, unit = text:match("[Gg]ain " .. N .. " ([%a ]-) for " .. D) end
  if not what then n, what, d, unit = text:match("%+" .. N .. " ([%a ]-) for " .. D) end
  if not what then return nil end
  what = what:gsub("^increased ", ""):gsub("^additional ", ""):gsub("^extra ", "")
  local key = STAT_WORDS[what:lower():gsub("^%s+", ""):gsub("%s+$", "")]
  if not key then return nil end
  return key, tonumber(n), Seconds(d, unit)
end

-- "attack speed by 20% for 15 sec" -> 20, 15
local function Haste(text)
  -- "attack speed by 20% for 15 sec", "attack and casting speed by 10% for 20 sec"
  local p, d, unit = text:match("speed by (%d+)%% for (%d+) (%a+)")
  if p and text:lower():find("attack") then return tonumber(p), Seconds(d, unit) end
end

-- "gain 1 extra attack" / "grants 2 extra attacks"
local function ExtraAttacks(text)
  local n = text:match("(%d+) extra attacks?")
  if n then return tonumber(n) end
  if text:find("an extra attack") then return 1 end
end

-- the average of "X to Y" / "X" damage in a text, or nil
local function AvgDamage(text)
  if not text:find("[Dd]amage") then return nil end
  local base
  local a, b = text:match("(%d[%d,]*) to (%d[%d,]*)")
  if a then base = (Num(a) + Num(b)) / 2
  else
    local n = text:match("(%d[%d,]*) %a* ?[Dd]amage") or text:match("[Dd]amage of (%d[%d,]*)") or text:match("for (%d[%d,]*)")
    base = n and Num(n)
  end
  if not base then return nil end
  -- "...and an additional 40 damage over 8 sec" (or "an additional 40 Fire damage over 8 sec")
  local dot = text:match("additional (%d[%d,]*) %a* ?[Dd]amage over") or text:match("additional (%d[%d,]*) [Dd]amage over")
  return base + (dot and Num(dot) or 0)
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
-- "+N damage to a spell", "reduces the cooldown / casting time of a spell by N sec"
local SPELL_FLAT = {
  "[Ii]ncreases the damage done by ([%a' :,%-]+) by (%d+)%.?$",
  "[Ii]ncreases the damage done by ([%a' :,%-]+) by (%d+)[^%%%d]",
  "[Ii]ncreases the damage of ([%a' :,%-]+) by (%d+)%.?$",
  "[Ii]ncreases the damage of ([%a' :,%-]+) by (%d+)[^%%%d]",
  "[Ii]ncreases the damage dealt by ([%a' :,%-]+) by (%d+)%.?$",
  "[Ii]ncreases the damage dealt by ([%a' :,%-]+) by (%d+)[^%%%d]",
}
local SPELL_CD = {
  "[Rr]educes the cooldown of ([%a' :,%-]+) by (%d+%.?%d*) (%a+)",
  "[Rr]educes the cooldown on ([%a' :,%-]+) by (%d+%.?%d*) (%a+)",
  "[Rr]educes ([%a' :,%-]+) cooldown by (%d+%.?%d*) (%a+)",
}
local SPELL_CAST = {
  "[Rr]educes the casting time of ([%a' :,%-]+) by (%d+%.?%d*) (%a+)",
  "[Rr]educes the cast time of ([%a' :,%-]+) by (%d+%.?%d*) (%a+)",
  "[Rr]educes ([%a' :,%-]+) cast time by (%d+%.?%d*) (%a+)",
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
      t = t:gsub("[Ii]mproves", "Increases") -- (both verbs are used for the same thing)
      local body = t:match("^Chance on hit: ?(.*)")
      local equipBody = t:match("^Equip: ?(.*)")
      if not body and equipBody then
        -- on-hit procs worded on an Equip line
        local low = equipBody:lower()
        if low:find("chance on hit") or low:find("chance on melee hit") or low:find("your attacks have a chance")
          or low:find("your melee attacks have a chance") or low:find("when struck in melee")
          or low:find("chance to gain") or low:find("chance when you hit") then
          body = equipBody
        end
      end
      if body then
        local chance = tonumber(body:match("(%d+%.?%d*)%% chance"))
        local key, n, d = StatBuff(body)
        local hp, hd = Haste(body)
        local extra = ExtraAttacks(body)
        if body:lower():find("when struck") then
          -- procs when you're hit: tanking, not your damage
        elseif extra then out[#out + 1] = { kind = "procExtra", attacks = extra, chance = chance, text = t }
        elseif key then out[#out + 1] = { kind = "procStat", stat = key, amount = n, dur = d, chance = chance, text = t }
        elseif hp then out[#out + 1] = { kind = "procHaste", pct = hp, dur = hd, chance = chance, text = t }
        else
          local avg = AvgDamage(body)
          if avg then out[#out + 1] = { kind = "procDamage", avg = avg, chance = chance, text = t } end
        end
      end
      local procLine = body ~= nil and equipBody ~= nil -- (an Equip line already read as a proc)
      body = t:match("^Use: ?(.*)")
      if body then
        local key, n, d = StatBuff(body)
        local cds
        local m, sec = body:match("%((%d+) [Mm]in, (%d+) [Ss]ec [Cc]ooldown%)")
        if m then cds = tonumber(m) * 60 + tonumber(sec)
        else
          local cd, unit = body:match("%((%d+) (%a+) [Cc]ooldown%)")
          cds = Seconds(cd, unit)
        end
        if key and cds and cds > 0 then out[#out + 1] = { kind = "useStat", stat = key, amount = n, dur = d, cd = cds, text = t } end
      end
      body = (not procLine) and t:match("^Equip: ?(.*)") or nil
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
      -- cooldown / cast time cuts and flat bonuses (checked before "+X%", which they don't overlap)
      if body and not critDone then
        for _, list in ipairs({ { SPELL_CD, "spellCd" }, { SPELL_CAST, "spellCast" } }) do
          for _, pat in ipairs(list[1]) do
            local name, n, unit = body:match(pat)
            if name then
              for _, one in ipairs(CleanSpellNames(name)) do
                out[#out + 1] = { kind = list[2], spell = one, secs = Seconds(n, unit), text = t }
              end
              critDone = true
              break
            end
          end
          if critDone then break end
        end
      end
      if body and not critDone and not body:find("%%") then
        for _, pat in ipairs(SPELL_FLAT) do
          local name, n = body:match(pat)
          if name then
            for _, one in ipairs(CleanSpellNames(name)) do
              out[#out + 1] = { kind = "spellFlat", spell = one, amount = tonumber(n), text = t }
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
-- 8 -> "8", 2.5 -> "2.5"
local function Secs(x) return (x == math.floor(x)) and tostring(x) or format("%.1f", x) end

-- a stat amount as the tooltip says it: "300 Attack Power", "5% Crit"
local PCT_STATS = { CRIT = true, HIT = true, SPELLCRIT = true, SPELLHIT = true, DODGE = true, PARRY = true }
local function Amount(n, stat)
  local num = (n == math.floor(n)) and tostring(n) or format("%.1f", n)
  local name = (ns.STAT_NAMES[stat] or stat):gsub(" %%$", "") -- ("5% Crit", not "5% Crit %")
  return (PCT_STATS[stat] and (num .. "%") or num) .. " " .. name
end
local function Avg(n, stat) return PCT_STATS[stat] and format("%.2f%%", n) or format("%.0f", n) end

local function SwingsPerMin(f)
  local _, speed = WeaponHit(f)
  return 60 / (speed or 2.5)
end

-- one effect: its points for these weights, and a line saying how
function E.Value(e, weights, f)
  local dpsPts = ns.PointsPer("DPS", weights.DPS) -- extra damage per second counts as weapon DPS
  local melee = dpsPts > 0 -- your spec gets value from hitting with weapons
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
      return avg * ns.PointsPer(e.stat, weights[e.stat]), format("Chance on hit: +%s, up %d%% of the time = +%s on average",
        Amount(e.amount, e.stat), uptime * 100 + 0.5, Avg(avg, e.stat))
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
    return avg * ns.PointsPer(e.stat, weights[e.stat]), format("Use: +%s for %ss every %ss = +%s on average",
      Amount(e.amount, e.stat), Secs(e.dur or 0), Secs(e.cd), Avg(avg, e.stat))
  end
  if e.kind == "procExtra" then
    -- extra swings: each one a weapon hit
    if not melee then return 0, "Extra attack: your spec doesn't hit with weapons" end
    local hit = WeaponHit(f)
    if not hit then return 0, "Extra attack: no weapon to read" end
    local perMin = e.chance and (e.chance / 100 * SwingsPerMin(f)) or PPM
    local dps = e.attacks * hit * perMin / 60
    return dps * dpsPts, format("Extra attack: %d x %d damage x %.1f/min = +%.1f DPS", e.attacks, hit, perMin, dps)
  end
  if e.kind == "spellPct" or e.kind == "spellFlat" or e.kind == "spellCd" or e.kind == "spellCast" then
    local label
    if e.kind == "spellPct" then label = e.crit and format("+%s%% crit", e.pct) or format("+%s%%", e.pct)
    elseif e.kind == "spellFlat" then label = format("+%d", e.amount)
    elseif e.kind == "spellCd" then label = format("-%ss cooldown", Secs(e.secs))
    else label = format("-%ss cast time", Secs(e.secs)) end
    label = label .. " " .. e.spell
    -- counts only if it's in your skill list, by its weight there (/eqt, Skills)
    local share = ns.SkillShare(e.spell)
    if not share then return 0, format("%s: not in your skills", label) end
    if share <= 0 then return 0, format("%s: %s is at 0 in your skills", label, e.spell) end
    -- what it adds, as a % of the skill
    local pct, detail
    local id, cast, cd = KnownSpell(e.spell)
    local avg, tcd, weapon
    if id then avg, tcd, _, _, weapon = SpellUse(id, f) end
    if e.kind == "spellPct" then
      pct = e.pct
      if e.crit then -- a crit adds +100% for a weapon strike, +50% for a spell or heal
        local extra = weapon and 1 or 0.5
        pct = e.pct * extra
        detail = format("crits add %d%%", extra * 100)
      end
    elseif e.kind == "spellFlat" then
      if not id then return 0, format("%s: you don't know %s, so its damage can't be read", label, e.spell) end
      if not avg or avg <= 0 then
        return 0, format("%s: %s", label, weapon and "no weapon to read its damage from" or "couldn't read its damage")
      end
      pct = e.amount / avg * 100
      detail = format("of %d", avg)
    elseif e.kind == "spellCd" then
      local spellCd = math.max(cd or 0, tcd or 0)
      if not id then return 0, format("%s: you don't know %s, so its cooldown can't be read", label, e.spell) end
      if spellCd <= GCD then return 0, format("%s: it has no cooldown to cut", label) end
      local now = math.max(spellCd - e.secs, cast or 0, GCD)
      pct = (spellCd / now - 1) * 100
      detail = format("every %ss instead of %ss", Secs(now), Secs(spellCd))
    else
      if not id then return 0, format("%s: you don't know %s, so its cast time can't be read", label, e.spell) end
      if (cast or 0) <= GCD then return 0, format("%s: it's already instant (or as fast as it gets)", label) end
      local now = math.max(cast - e.secs, GCD)
      pct = (cast / now - 1) * 100
      detail = format("%ss cast instead of %ss", Secs(now), Secs(cast))
    end
    local gain = pct * share -- % added to your whole output
    local pctText = (pct == math.floor(pct)) and tostring(pct) or format("%.1f", pct)
    return gain * ns.OUTPUT_PTS, format("%s: %s+%s%% to it x %.0f%% of your output = +%.2f%% output%s", label,
      detail and (detail .. " = ") or "", pctText, share * 100, gain, id and "" or " (not learned yet)")
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
