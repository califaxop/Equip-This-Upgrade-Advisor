-- Item effects that aren't plain stats: procs ("Chance on hit", "your spells have a chance"), Use
-- effects, and effects on a skill ("+10% Stormstrike").
-- Procs and Use effects: extra damage as DPS (weapon DPS for melee, spell damage for casters), stat
-- buffs through that stat's weight by how long they're up, mana as mana per 5 sec, haste as extra
-- swings or casts. A proc with no stated chance is about once a minute.
-- Skill effects ("+10% Stormstrike", "+1% crit chance of Healing Wave", "-1 sec cooldown", "+3 sec
-- duration") count by that skill's share of your output (its relative weight in your skill list,
-- Weights.lua), read as a % of the skill from its live tooltip where needed.
-- Each effect is read in three layers: trigger (hit, spell, crit, kill, being hit, Use), payload
-- (damage, buff, haste, mana, extra attack) and target (you, or the enemy: debuffs and slows on the
-- enemy aren't buffs on you). Procs when you're hit and on kills are named but not counted.
-- Checked against every effect line on Forever's gear (wow-forever-kb, build 1.60.1.71037).
-- Reads English tooltips, as the Equip-line stats do.
local _, ns = ...
local E = {}
ns.Effects = E
local Readable = ns.Readable

local PPM = 1             -- a proc with no stated chance: about once a minute (Classic's usual rate)
local CASTS_PER_MIN = 24  -- a caster's casts a minute (2.5 s each), for "N% chance on spell cast"
local GCD = 1.5           -- the fastest a spell can be used again
local SP_PER_DPS = 3.5    -- 1 damage (or healing) per second is about 3.5 spell power for a full-time caster
local CHAIN_BOUNCES = 0.43 -- Chain Heal's jumps (50% + 25%) are ~43% of what it heals
local CRIT_RATE = 0.25    -- for "chance on critical strike": about a quarter of hits crit (your sheet's, when readable)
local SPELL_CRIT_RATE = 0.15
local USE_CD_GUESS = 120  -- a Use line with no cooldown shown: about 2 minutes, like most trinkets
local SKILL_PER_POINT = 0.2 -- "Increased Swords +5": each point of weapon skill about +0.2% hit vs. raid bosses

-- words on tooltips -> our stat keys (for buffs: "increases your X by N", "grants N X")
local STAT_WORDS = {
  ["attack power"] = "AP", ["melee attack power"] = "AP", ["melee and ranged attack power"] = "AP", ["ranged attack power"] = "RAP", ["ranged attack"] = "RAP",
  ["strength"] = "STR", ["agility"] = "AGI", ["stamina"] = "STA", ["intellect"] = "INT", ["spirit"] = "SPI",
  ["armor"] = "ARMOR", ["armor value"] = "ARMOR",
  ["spell damage"] = "SP", ["spell power"] = "SP", ["spell damage and healing"] = "SP", ["damage and healing"] = "SP",
  ["damage and healing done by magical spells and effects"] = "SP", ["damage done by magical spells and effects"] = "SP",
  ["damage done by spells and effects"] = "SP", ["damage of your spells and effects"] = "SP",
  ["damage and healing of your spells"] = "SP", ["damage and healing of your spells and effects"] = "SP",
  ["damage of your spells"] = "SP", ["spell damage done"] = "SP", ["magical damage"] = "SP",
  ["healing"] = "HEAL", ["healing done"] = "HEAL", ["healing done by spells and effects"] = "HEAL",
  ["healing done by magical spells and effects"] = "HEAL", ["healing of your spells"] = "HEAL",
  ["healing spells"] = "HEAL", ["healing power"] = "HEAL", ["spell healing"] = "HEAL",
  ["defense"] = "DEF", ["defense skill"] = "DEF", ["block value"] = "BLOCKVALUE", ["shield block value"] = "BLOCKVALUE",
  ["dodge rating"] = "DODGE",
  -- % buffs: "grants 5% critical strike chance for 10 sec", "increases your chance to hit by 2% for 20 sec"
  ["critical strike chance"] = "CRIT", ["crit chance"] = "CRIT", ["chance to critically hit"] = "CRIT",
  ["chance to crit"] = "CRIT", ["critical strike"] = "CRIT", ["melee critical strike chance"] = "CRIT",
  ["chance to get a critical strike"] = "CRIT", ["critical hit chance"] = "CRIT",
  ["hit chance"] = "HIT", ["chance to hit"] = "HIT", ["melee hit chance"] = "HIT",
  ["spell critical strike chance"] = "SPELLCRIT", ["spell crit chance"] = "SPELLCRIT",
  ["chance to critically hit with spells"] = "SPELLCRIT", ["chance to get a critical strike with spells"] = "SPELLCRIT",
  ["critical strike chance with spells"] = "SPELLCRIT", ["spell critical chance"] = "SPELLCRIT",
  ["spell hit chance"] = "SPELLHIT", ["chance to hit with spells"] = "SPELLHIT",
  ["dodge chance"] = "DODGE", ["chance to dodge"] = "DODGE", ["parry chance"] = "PARRY", ["chance to parry"] = "PARRY",
  ["chance to block"] = "BLOCK", ["block chance"] = "BLOCK",
  -- turned into a stat: 10 health = 1 Stamina, 15 mana = 1 Intellect
  ["health"] = "STA", ["maximum health"] = "STA", ["max health"] = "STA",
  ["mana"] = "INT", ["maximum mana"] = "INT", ["max mana"] = "INT",
  ["all attributes"] = "ALL", ["all stats"] = "ALL", ["all attribute"] = "ALL",
}
local ALL_STATS = { "STR", "AGI", "STA", "INT", "SPI" }
local STAT_FACTOR = { ["health"] = 0.1, ["maximum health"] = 0.1, ["max health"] = 0.1,
  ["mana"] = 1 / 15, ["maximum mana"] = 1 / 15, ["max mana"] = 1 / 15 }

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
local function IsTimeUnit(u) u = (u or ""):lower(); return u:find("^sec") or u:find("^min") or u:find("^hour") or u:find("^hr") end

-- "chance on melee hit to increase your attack power" -> "AP" (and how much of it one point is:
-- 10 health = 1 Stamina): the longest run of words at the end that names a stat
local function StatKey(what)
  local words = {}
  what = (what or ""):lower():gsub("%s+for%s*$", ""):gsub(" for .*$", "") -- ("150 strength for 10 sec")
  for w in what:gmatch("%a+") do words[#words + 1] = w end
  for i = 1, #words do
    local tail = table.concat(words, " ", i)
    if STAT_WORDS[tail] then return STAT_WORDS[tail], STAT_FACTOR[tail] or 1 end
  end
end

-- stat buffs with a duration: "increases your attack power by 300 for 10 sec", "grants 5% critical
-- strike chance for 10 sec", "increases your spell damage by up to 204 and your healing by up to 408
-- for 20 sec", "knocks target silly for 3 sec and increases Strength by 75 for 12 sec", "Defense +20
-- for 10 sec". Returns { { stat, amount, seconds }, ... } (or nil).
local function StatBuffs(text)
  local low = text:lower():gsub("by up to", "by")
  if low:find("pet") or low:find("party member") and not low:find("you and") then return nil end
  -- how long: each "for N sec/min" and where it is
  local durs = {}
  for at, n, unit in low:gmatch("()for (%d+%.?%d*) (%a+)") do
    if IsTimeUnit(unit) then durs[#durs + 1] = { at, Seconds(n, unit) } end
  end
  if #durs == 0 then return nil end
  local function durAfter(at) for _, d in ipairs(durs) do if d[1] > at then return d[2] end end end
  local out = {}
  local PCT_KEYS = { CRIT = true, HIT = true, SPELLCRIT = true, SPELLHIT = true, DODGE = true, PARRY = true, BLOCK = true }
  local function add(what, n, at, pct)
    -- the clause it's in (from the last " and ", ",", "." or " to "): a debuff on the enemy ("reduce
    -- target's attack power", "lowering all stats") isn't a buff on you
    local seg, from = low:sub(1, at), 1
    for _, b in ipairs({ " and ", ", ", "%. ", " to " }) do
      for pos in seg:gmatch("()" .. b) do if pos > from and pos < at - #what then from = pos end end
    end
    local clause = seg:sub(from)
    if clause:find("target") or clause:find("enem") or clause:find("decreas") or clause:find("reduc")
      or clause:find("lower") or clause:find("their") or clause:find("its ") or clause:find("attacker") then return end
    local key, f = StatKey(what)
    local d = durAfter(at - #what) -- (the first "for N sec" after the stat's name)
    if not (key and d) then return end
    if pct and not PCT_KEYS[key] then return end -- ("spell damage by 20%": a % of a flat stat, can't be read as points)
    if key == "ALL" then for _, k in ipairs(ALL_STATS) do out[#out + 1] = { k, tonumber(n), d } end
    else out[#out + 1] = { key, tonumber(n) * f, d } end
  end
  -- "X by N" (any number of them: "your armor by 2000 and your defense by 30")
  for what, n, pct, at in low:gmatch("([%a ]+) by (%d+%.?%d*)(%%?)()") do add(what, n, at, pct == "%") end
  -- "N X": "grants 300 attack power", "you gain 120 Agility", "+40 Strength", "a 3% chance to hit"; "X +N"
  if #out == 0 then
    for n, pct, what, at in low:gmatch("(%d+%.?%d*)(%%?) ([%a ]+)()") do add(what, n, at, pct == "%") end
    for what, n, at in low:gmatch("([%a ]+) %+(%d+%.?%d*)()") do add(what, n, at, false) end
  end
  if #out == 0 then return nil end
  return out
end

-- "attack speed by 20% for 15 sec" -> 20, 15, casting (true: casting speed only)
local function Haste(text)
  local low = text:lower()
  local p, d, unit = low:match("speed by (%d+%.?%d*)%% for (%d+%.?%d*) (%a+)")
  if not p then p, d, unit = low:match("haste by (%d+%.?%d*)%% for (%d+%.?%d*) (%a+)") end
  if not (p and IsTimeUnit(unit)) then return nil end
  -- slowing the enemy ("slowing its attack speed", "increases the time between their attacks"): not yours
  local at = low:find("speed by %d") or low:find("haste by %d") or 1
  local before = low:sub(math.max(1, at - 30), at)
  if before:find("slow") or before:find("its ") or before:find("their") or before:find("target") or before:find("enem")
    or before:find("reduc") or before:find("decreas") or low:find("time between") then return nil end
  local attack, casting = low:find("attack") ~= nil, (low:find("cast") or low:find("spell")) ~= nil
  if not (attack or casting) then return nil end -- (movement speed)
  return tonumber(p), Seconds(d, unit), casting and not attack, attack and casting
end

-- "gain 1 extra attack" / "grants 2 extra attacks"
local function ExtraAttacks(text)
  local n = text:match("(%d+) extra attacks?")
  if n then return tonumber(n) end
  if text:find("an extra attack") or text:find("one extra attack") then return 1 end
end

-- mana restored: "restores 375 to 625 mana", "restore 200 mana", "gain 100 mana"
local function Mana(text)
  local low = text:lower():gsub("up to ", "")
  if low:find("per 5 sec") or low:find("every 5 sec") or low:find("mana cost") then return nil end
  local a, b = low:match("(%d[%d,]*) to (%d[%d,]*) mana")
  if a and (low:find("restor") or low:find("gain") or low:find("regain")) then return (Num(a) + Num(b)) / 2 end
  local n = low:match("restores? (%d[%d,]*) mana") or low:match("gains? (%d[%d,]*) mana") or low:match("regains? (%d[%d,]*) mana")
  return n and Num(n)
end

-- the average damage in a text, or nil: "150 Fire damage", "286 to 314 Fire damage and an additional
-- 40 damage over 8 sec", "7 Nature damage every 2 sec for 30 sec", "steals 48 life"
local function AvgDamage(text)
  local low = text:lower():gsub("up to ", "")
  -- healing yourself, not damage ("heals the wielder for 100 damage over 10 sec")
  if low:find("^heal") or low:find("heals? the wielder") or low:find("heals? wielder") or low:find("heals? you")
    or low:find("heal yourself") or low:find("heals? the bearer") then return nil end
  local tick, every, dur = low:match("transfers (%d[%d,]*) health every (%d+%.?%d*) sec%a* [%a ]-for (%d+) sec")
  if not tick then tick, every, dur = low:match("loses (%d[%d,]*) health[%a ]- every (%d+%.?%d*) sec%a* for (%d+) sec") end
  if tick then return Num(tick) * tonumber(dur) / tonumber(every) end
  local life = low:match("steals (%d[%d,]*) to (%d[%d,]*) life") and { low:match("steals (%d[%d,]*) to (%d[%d,]*) life") }
  if life then return (Num(life[1]) + Num(life[2])) / 2 end
  local n = low:match("steals (%d[%d,]*) life") or low:match("drains (%d[%d,]*) life") or low:match("drains (%d[%d,]*) health")
    or low:match("(%d[%d,]*) life from")
  if n then return Num(n) end
  if not low:find("damage") then return nil end
  if low:find("damage taken") or low:find("absorb") or low:find("protects") or low:find("shield") then return nil end -- (shields: not damage done)
  -- a damage over time: "7 nature damage every 2 sec for 30 sec", "...140 damage every 2 sec. ... Lasts for 20 sec."
  local t1, every, rest = low:match("(%d[%d,]*) %a* ?damage every (%d+%.?%d*) sec%a*(.*)")
  if t1 then
    local dur = rest:match("for (%d+) sec") or rest:match("lasts (%d+) sec") or rest:match("lasts for (%d+) sec")
    if dur then return Num(t1) * tonumber(dur) / tonumber(every) end
  end
  local base
  local a, b = low:match("(%d[%d,]*) to (%d[%d,]*) %a* ?damage")
  if not a then a, b = low:match("(%d[%d,]*) to (%d[%d,]*)") end
  if a then base = (Num(a) + Num(b)) / 2
  else
    n = low:match("(%d[%d,]*) %a* ?damage") or low:match("damage of (%d[%d,]*)") or low:match("for (%d[%d,]*) damage")
    base = n and Num(n)
  end
  if not base then return nil end
  local dot = low:match("additional (%d[%d,]*) %a* ?damage over")
  return base + (dot and Num(dot) or 0)
end

-- a cooldown at the end of a Use line: "(2 Min Cooldown)", "(1 Min, 30 Sec Cooldown)"
local function Cooldown(text)
  local m, sec = text:match("%((%d+) [Mm]ins?, (%d+) [Ss]ecs? [Cc]ooldown%)")
  if m then return tonumber(m) * 60 + tonumber(sec) end
  local cd, unit = text:match("%((%d+%.?%d*) (%a+) [Cc]ooldown%)")
  return Seconds(cd, unit)
end

-- Proc triggers. A line's prefix ("Chance on hit:", "When struck:", "Use:") or, on an Equip line, its
-- words: hit (melee or ranged), spell (cast or landed), crit, spellcrit, reactive (when you're hit:
-- tanking), kill. Each sets how often it goes off; reactive and kill procs aren't counted.
local PREFIX = {
  ["chance on hit"] = "melee", ["chance on melee hit"] = "melee", ["chance on ranged attack"] = "melee",
  ["chance on a melee or ranged attack"] = "melee", ["chance on melee or ranged attack"] = "melee",
  ["chance on striking"] = "melee", ["chance when you hit"] = "melee", ["when you hit"] = "melee", ["on hit"] = "melee",
  ["when struck"] = "reactive", ["when struck in combat"] = "reactive", ["when struck in melee"] = "reactive",
  ["when hit"] = "reactive", ["when attacked"] = "reactive", ["when you are hit"] = "reactive",
  ["when you block"] = "reactive", ["when you dodge"] = "reactive", ["when you parry"] = "reactive",
  ["chance on spell cast"] = "spell", ["chance on successful spellcast"] = "spell", ["chance on casting"] = "spell",
  ["chance on spell hit"] = "spell",
  ["chance on spell critical strike"] = "spellcrit", ["chance when your spell critically strikes"] = "spellcrit",
  ["chance on critical hit"] = "crit", ["chance on critical strike"] = "crit", ["when you critically strike"] = "crit",
  ["on a critical strike"] = "crit", ["when your attack critically hits"] = "crit",
  ["when you kill an enemy"] = "kill", ["upon killing an enemy"] = "kill", ["killing an enemy"] = "kill",
  ["chance when killing an enemy"] = "kill",
  ["equip"] = "equip", ["when equipped"] = "equip",
  ["use"] = "use", ["upon activation"] = "use", ["chance on use"] = "use",
}
local DEFENSIVE = { "when struck", "when hit", "when you are hit", "when you are struck", "when attacked",
  "when you block", "when you dodge", "when you parry", "you take damage", "when damaged", "strikes you",
  "every time you block", "victim of" }
local PROC_WORDS = { "chance on", "chance when", "chance per", "have a chance", "has a chance", "gives a chance",
  "% chance", "chance of hitting", "on successful", "on a successful", "each time you", "every time you",
  "when you hit", "on landing", "chance to strike", "chance to deal", "chance to decapitate", "chance to discharge",
  "chance to restore", "chance to gain", "chance to increase", "chance to grant", "chance to heal" }
-- the trigger of an Equip line (nil: not a proc), and whether it goes off every time (no chance stated)
local function ProcTrigger(low)
  for _, w in ipairs(DEFENSIVE) do if low:find(w, 1, true) then return "reactive" end end
  local proc = false
  for _, w in ipairs(PROC_WORDS) do if low:find(w, 1, true) then proc = true; break end end
  if not proc then return nil end
  -- what sets it off: the words up to "chance ... to" (or the whole line)
  local trig = low:match("^(.-chance.-) to ") or low
  local always = not low:find("chance") and (low:find("each time") or low:find("every time") or low:find("on successful")
    or low:find("on a successful") or low:find("when you hit")) and true or false
  if trig:find("kill") then return "kill" end
  if trig:find("critical") or trig:find("critically") then
    return (trig:find("spell") or trig:find("heal")) and "spellcrit" or "crit", always
  end
  if trig:find("spell") or trig:find("cast") or trig:find("heal") or trig:find("causes ") then return "spell", always end
  return "melee", always
end
-- a skill a proc is tied to ("Causes Wrath to have...", "Your Frostbolt spells have...", "each time you cast Healing Touch")
local SCHOOLS_WORD = { holy = true, fire = true, nature = true, frost = true, shadow = true, arcane = true }
local GENERIC = { harmful = true, healing = true, damaging = true, damage = true, melee = true, ranged = true,
  offensive = true, attacks = true, spells = true, spell = true, direct = true, periodic = true }
local function TriggerSkill(text)
  local name = text:match("[Cc]auses ([%a' :%-]-) to have") or text:match("[Yy]our ([%a' :%-]-) spells? ha[sv]e? ")
    or text:match("[Yy]our ([%a' :%-]-) abilit[%a]* ha[sv]e? ") or text:match("[Yy]our ([%a' :%-]-) ha[sv]e? a")
    or text:match("time you cast ([%a' :%-]+)") or text:match("when you cast ([%a' :%-]+)")
  if not name then return nil end
  name = name:gsub("%s+$", ""):gsub(" spells?$", ""):gsub(" abilit%a+$", "")
  local low = name:lower()
  local first = low:match("^(%a+)")
  if not first or GENERIC[low] or SCHOOLS_WORD[low] or (GENERIC[first] and not low:find(" ")) or low:find("attack")
    or low:find("^harmful") or low:find("^damaging") then return nil end
  return name
end

-- "+10% to a skill": the skill's name and the %, and whether it's healing
local NAME = "([%a' :,%-]+)"
local PCT = "(%d+%.?%d*)%%"
local SPELL_PCT = {
  { "[Ii]ncreases the damage dealt by " .. NAME .. " by " .. PCT, false }, -- "...dealt by your Stormstrike ability by 10%"
  { "[Ii]ncreases the damage done by " .. NAME .. " by " .. PCT, false },
  { "[Ii]ncreases the damage caused by " .. NAME .. " by " .. PCT, false },
  { "[Ii]ncreases the damage from " .. NAME .. " by " .. PCT, false },
  { "[Ii]ncreases the damage of " .. NAME .. " by " .. PCT, false },
  { "[Ii]ncreases " .. NAME .. " damage by " .. PCT, false },
  { "[Ii]ncreases the healing dealt by " .. NAME .. " by " .. PCT, true },
  { "[Ii]ncreases the healing done by " .. NAME .. " by " .. PCT, true },
  { "[Ii]ncreases the healing from " .. NAME .. " by " .. PCT, true },
  { "[Ii]ncreases the healing of " .. NAME .. " by " .. PCT, true },
  { "[Ii]ncreases the amount healed by " .. NAME .. " by " .. PCT, true },
  { "[Ii]ncreases " .. NAME .. " healing by " .. PCT, true },
  { "[Ii]ncreases the effect of " .. NAME .. " by " .. PCT, false },
  { "[Ii]ncreases the effectiveness of " .. NAME .. " by " .. PCT, false },
}
-- "+X% crit chance to a skill": worth X% x what a crit adds
local SPELL_CRIT = {
  "[Ii]ncreases the critical strike chance of " .. NAME .. " by " .. PCT,
  "[Ii]ncreases the critical hit chance of " .. NAME .. " by " .. PCT,
  "[Ii]ncreases the crit chance of " .. NAME .. " by " .. PCT,
  "[Ii]ncreases the chance to crit with " .. NAME .. " by " .. PCT,
  "[Ii]ncreases the critical strike chance with " .. NAME .. " by " .. PCT,
  "[Ii]ncreases the chance to critically hit with " .. NAME .. " by " .. PCT,
  "[Ii]ncreases your chance to get a critical strike with " .. NAME .. " by " .. PCT,
  "[Ii]ncreases your chance to critically hit with " .. NAME .. " by " .. PCT,
  "[Ii]ncreases " .. NAME .. " critical strike chance by " .. PCT,
}
-- "+N damage (or healing) to a skill" (written "by N" or "by up to N": read after "up to" is dropped)
local function Flat(verb) -- "...by 30." / "...by 30 and..."
  return { "[Ii]ncreases the " .. verb .. " " .. NAME .. " by (%d+)%.?$", "[Ii]ncreases the " .. verb .. " " .. NAME .. " by (%d+)[^%%%d%.]" }
end
local SPELL_FLAT, SPELL_FLAT_HEAL = {}, {}
for _, v in ipairs({ "damage done by", "damage of", "damage dealt by", "damage caused by", "damage from" }) do
  for _, p in ipairs(Flat(v)) do SPELL_FLAT[#SPELL_FLAT + 1] = p end
end
for _, v in ipairs({ "healing done by", "healing of", "healing dealt by", "amount healed by", "healing from" }) do
  for _, p in ipairs(Flat(v)) do SPELL_FLAT_HEAL[#SPELL_FLAT_HEAL + 1] = p end
end
local SECS = "(%d+%.?%d*) (%a+)"
local SPELL_CD = {
  "[Rr]educes the cooldown of " .. NAME .. " by " .. SECS,
  "[Rr]educes the cooldown on " .. NAME .. " by " .. SECS,
  "[Rr]educes " .. NAME .. " cooldown by " .. SECS,
}
local SPELL_CAST = {
  "[Rr]educes the casting time of " .. NAME .. " by " .. SECS,
  "[Rr]educes the cast time of " .. NAME .. " by " .. SECS,
  "[Rr]educes " .. NAME .. " casting time by " .. SECS,
  "[Rr]educes " .. NAME .. " cast time by " .. SECS,
}
local SPELL_DUR = {
  "[Ii]ncreases the duration of " .. NAME .. " by " .. SECS,
}
local SPELL_MANA = {
  "[Rr]educes the mana cost of " .. NAME .. " by (%d+%.?%d*%%?)",
  "[Rr]educes the energy cost of " .. NAME .. " by (%d+%.?%d*%%?)",
  "[Rr]educes the rage cost of " .. NAME .. " by (%d+%.?%d*%%?)",
}

-- wordings written with or without "the" ("Increases healing of X" = "Increases the healing of X")
local NO_THE = { "damage dealt by", "damage done by", "damage caused by", "damage of", "damage from",
  "healing dealt by", "healing done by", "healing of", "healing from", "amount healed by",
  "critical strike chance of", "critical hit chance of", "critical strike chance with", "crit chance of",
  "chance to crit with", "chance to critically hit with", "effect of", "effectiveness of", "duration of",
  "cooldown of", "cooldown on", "casting time of", "cast time of", "mana cost of", "energy cost of", "rage cost of" }
-- the whole character, not a skill: a school of magic, "spells and effects"
local SCHOOLS = { holy = true, fire = true, nature = true, frost = true, shadow = true, arcane = true,
  magical = true, physical = true, all = true, melee = true, ranged = true, healing = true, damage = true, damaging = true }

-- "your Stormstrike ability" -> { "Stormstrike" }; "Mortal Strike and Overpower" -> both;
-- "your Shock spells" -> { "Shock" } and family (every listed skill with "Shock" in its name);
-- "Chain Heal to targets beyond the first" -> { "Chain Heal" }, part of it
local function CleanSpellNames(name)
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  local low = name:lower()
  if low:find("effects") or low:find("weapons?$") or low:find("attacks$") or low:find("^spells?$") or low:find("^your spells?$")
    or low:find("pet") then return {} end
  local part
  if low:find(" to targets beyond the first$") then
    name = name:gsub(" to targets beyond the first$", ""); part = CHAIN_BOUNCES
  end
  local family = false
  name = name:gsub("^your ", ""):gsub("^the ", "")
  local a = name:gsub(" abilities$", ""):gsub(" spells$", ""):gsub(" totems$", ""):gsub(" shouts$", ""):gsub(" stings$", "")
  if a ~= name then family = true end
  name = a:gsub(" ability$", ""):gsub(" spell$", ""):gsub(" talent$", "")
  local list = {}
  local NOT_A_SPELL = { [""] = true, your = true, spell = true, spells = true }
  local names = {}
  for one in (name:gsub(" and ", ", ") .. ","):gmatch("%s*([^,]-)%s*,") do names[#names + 1] = one end
  if #names > 1 then family = false end -- ("Mortal Strike and Overpower abilities": two skills, not a family)
  for _, one in ipairs(names) do
    one = one:gsub("^your ", ""):gsub("^and ", "")
    local first = one:lower():match("^(%a+)")
    if not NOT_A_SPELL[one:lower()] and not (family and first and SCHOOLS[first] and not one:find(" ")) and not SCHOOLS[one:lower()] then
      list[#list + 1] = { one, family, part }
    end
  end
  return list
end

-- the first pattern in a list that matches: its captures
local function First(body, list)
  for _, p in ipairs(list) do
    local pat = type(p) == "table" and p[1] or p
    local a, b, c = body:match(pat)
    if a then return a, b, c, p end
  end
end

-- the effects of one proc or Use body: damage, stat buffs, haste, extra attacks, mana
local function ReadBody(body, out, base)
  local function add(e) for k, v in pairs(base) do e[k] = v end; out[#out + 1] = e end
  local extra = base.use == nil and ExtraAttacks(body)
  if extra then add({ kind = "procExtra", attacks = extra }); return end
  local hp, hd, casting, both = Haste(body)
  if hp then add({ kind = base.use and "useHaste" or "procHaste", pct = hp, dur = hd, casting = casting, both = both }) end
  local buffs = StatBuffs(body)
  if buffs then
    for _, b in ipairs(buffs) do add({ kind = base.use and "useStat" or "procStat", stat = b[1], amount = b[2], dur = b[3] }) end
  end
  if hp or buffs then return end
  local mana = Mana(body)
  if mana then add({ kind = base.use and "useMana" or "procMana", amount = mana }) end
  local avg = AvgDamage(body)
  if avg then add({ kind = base.use and "useDamage" or "procDamage", avg = avg }) end
end

-- An item's effects from its tooltip lines (left texts). Each: a table with kind and its numbers.
function E.Parse(texts)
  local out = {}
  for _, t in ipairs(texts) do
    if Readable(t) and type(t) == "string" then
      t = t:gsub("[Ii]mproves", "Increases"):gsub("[Dd]ecreases the cooldown", "Reduces the cooldown")
        :gsub("[Dd]ecreases the cast", "Reduces the cast"):gsub("[Ll]owers the cooldown", "Reduces the cooldown")
      for _, w in ipairs(NO_THE) do t = t:gsub("([IiRr]%a+s) (" .. w .. ")", "%1 the %2") end
      t = t:gsub("by %-(%d)", "by %1") -- ("by -2 sec")
      local pre, rest = t:match("^([%a ]-): ?(.*)$")
      local what = pre and PREFIX[pre:lower()]
      local function chanceOf(b) return tonumber(b:match("(%d+%.?%d*)%% chance")) end
      local equip = (what == "equip") and rest or nil
      local low = (rest or ""):lower()
      if what == "reactive" or what == "kill" then
        out[#out + 1] = { kind = "note", why = format("%s: %s", pre, what == "kill" and "kill procs aren't counted" or "procs when you're hit aren't counted (tanking)"), text = t }
      elseif what == "melee" or what == "spell" or what == "crit" or what == "spellcrit" then
        ReadBody(rest, out, { trigger = what, chance = chanceOf(rest), skillTrig = TriggerSkill(rest), text = t })
      elseif what == "use" then
        local cd = Cooldown(rest)
        ReadBody(rest, out, { use = true, cd = (cd and cd > 0) and cd or USE_CD_GUESS, cdGuess = not (cd and cd > 0), text = t })
      elseif equip then
        local trig, always = ProcTrigger(low)
        local adds = low:match("adds (%d+) %a* ?damage to your") -- damage on every swing
        local wskill, wn = rest:match("^Increased ([%a%- ]+) %+(%d+)")
        if adds then
          out[#out + 1] = { kind = "procDamage", avg = tonumber(adds), trigger = "melee", chance = 100, text = t }
        elseif wskill and not ({ defense = true, fishing = true, skinning = true, mining = true, herbalism = true,
          lockpicking = true, ["first aid"] = true, cooking = true })[wskill:lower()] then
          out[#out + 1] = { kind = "weaponSkill", skill = wskill, amount = tonumber(wn), text = t }
        elseif trig == "reactive" or trig == "kill" then
          out[#out + 1] = { kind = "note", why = trig == "kill" and "Kill proc: not counted" or "Proc when you're hit: not counted (tanking)", text = t }
        elseif trig then
          ReadBody(rest, out, { trigger = trig, chance = always and 100 or chanceOf(rest), skillTrig = TriggerSkill(rest), text = t })
        elseif not low:find("pet") and not low:find("your imp") then
          -- effects on a skill (flat bonuses are often written "by up to N")
          local body = equip:gsub("by up to", "by")
          -- read by name at score time (your skill list); the patterns below name the skill when it
          -- isn't on your list, and catch families ("your Shock spells")
          local line = { kind = "skillLine", body = body, parsed = {}, text = t }
          local function each(name, fn) for _, s in ipairs(CleanSpellNames(name)) do
            local e = fn(); e.spell, e.family, e.part, e.text = s[1], s[2], s[3], t; line.parsed[#line.parsed + 1] = e end end
          local name, n, unit = First(body, SPELL_CRIT)
          if name then each(name, function() return { kind = "spellPct", pct = tonumber(n), crit = true } end)
          else
            name, n, unit = First(body, SPELL_CD)
            if name then each(name, function() return { kind = "spellCd", secs = Seconds(n, unit) } end)
            else
              name, n, unit = First(body, SPELL_CAST)
              if name then each(name, function() return { kind = "spellCast", secs = Seconds(n, unit) } end)
              else
                name, n, unit = First(body, SPELL_DUR)
                if name and IsTimeUnit(unit) then each(name, function() return { kind = "spellDur", secs = Seconds(n, unit) } end)
                else
                  name, n = First(body, SPELL_MANA)
                  if name then each(name, function() return { kind = "spellMana", cut = n } end)
                  else
                    local p
                    name, n, _, p = First(body, SPELL_PCT)
                    if name then each(name, function() return { kind = "spellPct", pct = tonumber(n), heal = p[2] } end)
                    else
                      name, n = First(body, SPELL_FLAT)
                      if name then each(name, function() return { kind = "spellFlat", amount = tonumber(n) } end)
                      else
                        name, n = First(body, SPELL_FLAT_HEAL)
                        if name then each(name, function() return { kind = "spellFlat", amount = tonumber(n), heal = true } end) end
                      end
                    end
                  end
                end
              end
            end
          end
          if #line.parsed > 0 or body:find("%d") then out[#out + 1] = line end
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
-- for "weapon damage"; its cooldown if the tooltip says one; and how long it lasts ("over 12 sec")
local function SpellUse(id, f)
  local hit = WeaponHit(f)
  local key = id .. ":" .. tostring(hit and math.floor(hit * 10) or "-") -- (per weapon hit: two weapons can share a speed)
  local c = spellCache[key]
  if c then return c.avg, c.cd, c.heal, c.how, c.weapon, c.dur end
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
    local n = all:match("absorbing (%d[%d,]*)") or all:match("absorbs (%d[%d,]*)") or all:match("for (%d[%d,]*)")
    if n then avg = Num(n); how = n end
  end
  heal = (all:lower():find("heal") ~= nil) and not all:lower():find("damage")
  local cd
  local n, unit = all:match("(%d+%.?%d*) (%a+) cooldown")
  if n then cd = Seconds(n, unit) end
  local dn, du = all:match("over (%d+%.?%d*) (%a+)")
  local dur = dn and IsTimeUnit(du) and Seconds(dn, du) or nil
  spellCache[key] = { avg = avg, cd = cd, heal = heal, how = how, weapon = weapon, dur = dur }
  return avg, cd, heal, how, weapon, dur
end

---------------------------------------------------------------------------
-- Value for your spec
---------------------------------------------------------------------------
-- 8 -> "8", 2.5 -> "2.5"
local function Secs(x) return (x == math.floor(x)) and tostring(x) or format("%.1f", x) end

-- a stat amount as the tooltip says it: "300 Attack Power", "5% Crit"
local PCT_STATS = { CRIT = true, HIT = true, SPELLCRIT = true, SPELLHIT = true, DODGE = true, PARRY = true, BLOCK = true }
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

-- your crit chance (0-1) from the character sheet when it can be read, else a typical one
local function CritRate(spell)
  local fn = spell and GetSpellCritChance or GetCritChance
  if fn then
    local ok, v = pcall(fn, spell and 4 or nil) -- (4: Nature; any school will do)
    if ok and Readable(v) and type(v) == "number" and v > 0 then return v / 100 end
  end
  return spell and SPELL_CRIT_RATE or CRIT_RATE
end

-- how often a proc goes off a minute: its stated chance per swing (or per cast, or per crit), else about once.
-- A proc tied to one skill goes off on that skill's casts: its part of your casts (its weight over the list's).
local function PerMin(e, f)
  local spell = e.trigger == "spell" or e.trigger == "spellcrit"
  local per = spell and CASTS_PER_MIN or SwingsPerMin(f)
  if e.skillTrig then
    local w = ns.SkillWeight(e.skillTrig) or 0
    local total = 0
    for _, s in ipairs(ns.CurrentSkills()) do total = total + math.max(0, tonumber(s[2]) or 0) end
    per = (total > 0) and (CASTS_PER_MIN * w / total) or 0
  end
  if e.trigger == "crit" or e.trigger == "spellcrit" then per = per * CritRate(spell) end
  if not e.chance then return e.skillTrig and math.min(per, PPM) or PPM end
  return e.chance / 100 * per
end

-- one effect: its points for these weights, and a line saying how
function E.Value(e, weights, f)
  local dpsPts = ns.PointsPer("DPS", weights.DPS) -- extra damage per second counts as weapon DPS...
  local spPts = ns.PointsPer("SP", weights.SP) * SP_PER_DPS -- ...or as spell damage, for a caster
  local melee = dpsPts > 0 -- your spec gets value from hitting with weapons
  if e.kind == "note" then return 0, e.why end
  if e.kind == "weaponSkill" then return E.WeaponSkill(e, weights, f) end
  local what = e.use and (e.cdGuess and "Use (no cooldown shown: 2 min assumed)" or "Use")
    or (e.trigger == "spell" and "Spell proc") or (e.trigger == "crit" and "Crit proc")
    or (e.trigger == "spellcrit" and "Spell crit proc") or "Chance on hit"
  if e.skillTrig then
    if not ns.SkillWeight(e.skillTrig) then return 0, format("%s (on %s): not in your skills", what, e.skillTrig) end
    what = format("%s (on %s)", what, e.skillTrig)
  end
  -- damage per second -> points: weapon DPS for melee, spell damage for casters
  local function dmg(dps) if melee and e.trigger ~= "spell" then return dps * dpsPts end return dps * spPts end
  if (e.trigger == "melee" or e.trigger == "crit") and not melee then return 0, what .. ": your spec doesn't hit with weapons" end
  local perMin = e.use and (60 / e.cd) or PerMin(e, f)
  local every = e.use and format(" every %ss", Secs(e.cd)) or format(" x %.1f/min", perMin)
  if e.kind == "procDamage" or e.kind == "useDamage" then
    local dps = e.avg * perMin / 60
    return dmg(dps), format("%s: %d damage%s = +%.1f DPS", what, e.avg, every, dps)
  end
  if e.kind == "procMana" or e.kind == "useMana" then
    local mp5 = e.amount * perMin / 12
    return mp5 * ns.PointsPer("MP5", weights.MP5), format("%s: %d mana%s = +%.1f mana per 5 sec", what, e.amount, every, mp5)
  end
  local uptime = math.min(1, (e.dur or 0) * perMin / 60)
  if e.kind == "procStat" or e.kind == "useStat" then
    local avg = e.amount * uptime
    return avg * ns.PointsPer(e.stat, weights[e.stat]), format("%s: +%s for %ss, up %d%% of the time = +%s on average",
      what, Amount(e.amount, e.stat), Secs(e.dur or 0), uptime * 100 + 0.5, Avg(avg, e.stat))
  end
  if e.kind == "procHaste" or e.kind == "useHaste" then
    if not melee and not (e.casting or e.both) then return 0, what .. ": attack speed, and your spec doesn't fight with weapons" end
    if melee and e.casting then return 0, what .. ": casting speed, and your spec fights in melee" end
    if not melee then
      -- faster casts: that much more of the output that comes from skills
      local gain = e.pct * uptime * ns.SkillPart() / 100
      return gain * ns.OUTPUT_PTS, format("%s: +%s%% casting speed, up %d%% of the time = +%.2f%% output", what,
        Secs(e.pct), uptime * 100 + 0.5, gain)
    end
    local hit, speed = WeaponHit(f)
    if not hit then return 0, what .. " (attack speed): no weapon to read" end
    local dps = hit / speed * e.pct / 100 * uptime
    return dps * dpsPts, format("%s: +%s%% attack speed, up %d%% of the time = +%.1f DPS", what, Secs(e.pct), uptime * 100 + 0.5, dps)
  end
  if e.kind == "procExtra" then
    -- extra swings: each one a weapon hit
    local hit = WeaponHit(f)
    if not hit then return 0, "Extra attack: no weapon to read" end
    local dps = e.attacks * hit * perMin / 60
    return dps * dpsPts, format("Extra attack: %d x %d damage x %.1f/min = +%.1f DPS", e.attacks, hit, perMin, dps)
  end
  if e.kind == "skillLine" then return E.SkillLine(e, weights, f) end
  if e.spell then
    local label
    if e.kind == "spellPct" then label = e.crit and format("+%s%% crit", e.pct) or format("+%s%%", e.pct)
    elseif e.kind == "spellFlat" then label = format("+%d", e.amount)
    elseif e.kind == "spellCd" then label = format("-%ss cooldown", Secs(e.secs))
    elseif e.kind == "spellCast" then label = format("-%ss cast time", Secs(e.secs))
    elseif e.kind == "spellDur" then label = format("+%ss duration", Secs(e.secs))
    elseif e.kind == "skillMana" then label = format("+%d mana", e.mana)
    else label = format("-%s cost", e.cut) end
    label = label .. " " .. e.spell .. (e.family and " (all)" or "") .. (e.part and " (jumps)" or "")
    -- counts only if it's in your skill list, by its share of your output (/eqt, Skill Weights)
    local share = ns.SkillShare(e.spell, e.family)
    if not share then return 0, format("%s: not in your skills", label) end
    if share <= 0 then return 0, format("%s: %s is at 0 in your skills", label, e.spell) end
    if e.kind == "spellMana" then return 0, format("%s: costs aren't counted (only what it does)", label) end
    if e.kind == "skillMana" then
      local total = 0
      for _, s in ipairs(ns.CurrentSkills()) do total = total + math.max(0, tonumber(s[2]) or 0) end
      local casts = CASTS_PER_MIN * (ns.SkillWeight(e.spell) or 0) / math.max(total, 0.01)
      local mp5 = e.mana * casts / 12
      return mp5 * ns.PointsPer("MP5", weights.MP5), format("+%d mana per %s: ~%.1f casts/min = +%.1f mana per 5 sec",
        e.mana, e.spell, casts, mp5)
    end
    share = share * (e.part or 1)
    -- what it adds, as a % of the skill (a family: the first listed skill stands for the rest)
    local pct, detail
    local id, cast, cd = KnownSpell(e.spell)
    if not id and e.family then
      for _, s in ipairs(ns.CurrentSkills()) do
        if (" " .. s[1]:lower() .. " "):find(" " .. e.spell:lower() .. " ", 1, true) then
          id, cast, cd = KnownSpell(s[1]); if id then break end
        end
      end
    end
    local avg, tcd, weapon, dur
    if id then avg, tcd, _, _, weapon, dur = SpellUse(id, f) end
    if e.kind == "spellPct" then
      pct = e.pct
      if e.crit then -- a crit adds +100% for a weapon strike, +50% for a spell or heal
        local extra = weapon and 1 or 0.5
        pct = e.pct * extra
        detail = format("crits add %d%%", extra * 100)
      end
    elseif e.kind == "spellFlat" then
      if not id then return 0, format("%s: you don't know %s, so its %s can't be read", label, e.spell, e.heal and "healing" or "damage") end
      if not avg or avg <= 0 then
        return 0, format("%s: %s", label, weapon and "no weapon to read its damage from" or "couldn't read its numbers")
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
    elseif e.kind == "spellCast" then
      if not id then return 0, format("%s: you don't know %s, so its cast time can't be read", label, e.spell) end
      if (cast or 0) <= GCD then return 0, format("%s: it's already instant (or as fast as it gets)", label) end
      local now = math.max(cast - e.secs, GCD)
      pct = (cast / now - 1) * 100
      detail = format("%ss cast instead of %ss", Secs(now), Secs(cast))
    else -- spellDur: more ticks of a heal or damage over time
      if not id then return 0, format("%s: you don't know %s, so its duration can't be read", label, e.spell) end
      if not dur or dur <= 0 then return 0, format("%s: it isn't an over-time effect (no ticks to add)", label) end
      pct = e.secs / dur * 100
      detail = format("%ss instead of %ss", Secs(dur + e.secs), Secs(dur))
    end
    local gain = pct * share -- % added to your whole output
    local pctText = (pct == math.floor(pct)) and tostring(pct) or format("%.1f", pct)
    return gain * ns.OUTPUT_PTS, format("%s: %s+%s%% to it x %.0f%% of your output = +%.2f%% output%s", label,
      detail and (detail .. " = ") or "", pctText, share * 100, gain, id and "" or " (not learned yet)")
  end
  return 0, nil
end

-- "Increased Swords +5": counts when the item, or the main hand you wear, is that kind of weapon
local function WeaponKind(link)
  if not (link and C_Item and C_Item.GetItemInfoInstant) then return nil end
  local ok, _, _, sub = pcall(C_Item.GetItemInfoInstant, link)
  return ok and Readable(sub) and type(sub) == "string" and sub:lower() or nil
end
local function SkillFits(skill, sub)
  if not sub then return false end
  skill = skill:lower()
  if skill:find("two%-handed") then return sub == skill end
  return sub == skill or sub == "one-handed " .. skill
end
function E.WeaponSkill(e, weights, f)
  local label = format("+%d %s skill", e.amount, e.skill)
  local fits = (f and SkillFits(e.skill, f.subType))
    or SkillFits(e.skill, WeaponKind(GetInventoryItemLink and GetInventoryItemLink("player", 16)))
    or SkillFits(e.skill, WeaponKind(GetInventoryItemLink and GetInventoryItemLink("player", 18)))
  if not fits then return 0, label .. ": you don't use that kind of weapon" end
  local hit = e.amount * SKILL_PER_POINT
  return hit * ns.PointsPer("HIT", weights.HIT), format("%s: about +%.1f%% hit against raid bosses", label, hit)
end

-- a skill effect worded any way: find your listed skills by name in the line, then read the number
-- next to it and what it changes from the words around it
local function Norm(x) return " " .. x:lower():gsub("[^%a'%d%%%.]+", " ") .. " " end
function E.SkillLine(line, weights, f)
  local low = Norm(line.body)
  local skills = {}
  for _, s in ipairs(ns.CurrentSkills()) do if s[1] and s[1] ~= "" then skills[#skills + 1] = s[1] end end
  table.sort(skills, function(a, b) return #a > #b end) -- ("Lesser Healing Wave" before "Healing Wave")
  local found = {}
  for _, name in ipairs(skills) do
    local key = Norm(name):gsub("^ ", ""):gsub(" $", "")
    local at = low:find(" " .. key .. " ", 1, true)
    if at then
      found[#found + 1] = { name, at }
      low = low:sub(1, at) .. string.rep("_", #key) .. low:sub(at + 1 + #key) -- (not matched again by a shorter name)
    end
  end
  local effects = {}
  local text = line.body:lower()
  -- a change to how a skill works ("can now also trigger...", "a 50% reduced chance"), not a bonus to it
  if (text:find("chance") and not text:find("crit")) or text:find("can now") or text:find("talent") then found = {} end
  for _, fs in ipairs(found) do
    local name = fs[1]
    -- the number tied to it: "by N" after the name, else the first "by N", else the first number
    local after = text:sub(fs[2])
    local n, isPct = after:match("by (%d+%.?%d*)(%%?)")
    if not n then n, isPct = text:match("by (%d+%.?%d*)(%%?)") end
    if not n then n, isPct = text:match("(%d+%.?%d*)(%%?)") end
    if n then
      n = tonumber(n); isPct = isPct == "%"
      local unit = text:match(tostring(n):gsub("%.", "%%.") .. "%.?%d* (%a+)") or ""
      local e = { spell = name, text = line.text }
      if text:find("beyond the first") then e.part = CHAIN_BOUNCES end
      if text:find("mana") and not text:find("cost") and (text:find("cast") or text:find("restore") or text:find("gain")) then
        e.kind, e.mana = "skillMana", n -- "gain up to 50 mana each time you cast Healing Touch"
      elseif text:find("mana cost") or text:find("energy cost") or text:find("rage cost") then
        e.kind, e.cut = "spellMana", n .. (isPct and "%" or "")
      elseif text:find("cooldown") and not isPct then
        e.kind, e.secs = "spellCd", Seconds(n, unit)
      elseif (text:find("cast time") or text:find("casting time")) and not isPct then
        e.kind, e.secs = "spellCast", Seconds(n, unit)
      elseif text:find("duration") or ((not isPct) and IsTimeUnit(unit)) then
        e.kind, e.secs = "spellDur", Seconds(n, unit)
      elseif text:find("crit") and isPct then
        e.kind, e.pct, e.crit = "spellPct", n, true
      elseif isPct then
        e.kind, e.pct, e.heal = "spellPct", n, text:find("heal") ~= nil
      else
        e.kind, e.amount, e.heal = "spellFlat", n, text:find("heal") ~= nil
      end
      if e.secs or e.kind ~= "spellCd" then effects[#effects + 1] = e end
    end
  end
  -- none of your skills named: what the wording patterns found (a family, or a skill not on your list)
  if #effects == 0 then effects = line.parsed end
  local total, why = 0, {}
  for _, e in ipairs(effects) do
    local p, w = E.Value(e, weights, f)
    total = total + (p or 0)
    if w then why[#why + 1] = w end
  end
  return total, (#why > 0) and table.concat(why, " / ") or nil
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
