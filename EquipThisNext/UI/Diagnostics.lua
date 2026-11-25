-- Diagnostics: /eqn commands that print what the scanners collected, so Milestone 1 can be checked
-- in the real client, and /eqn dump to save it (with the API results) for offline tests.
local _, ns = ...
local Diag = ns.Module("Diagnostics")
local Compat = ns.Compat

local P = ns.Print
local function f(fmt, ...) P(string.format(fmt, ...)) end
local GOOD, BAD, NOTE, DIM = "|cff60ff60", "|cffff6060", "|cffffd200", "|cff9d9d9d"

local function profile(force)
  if force or not ns.profile then return ns.CharacterScanner.Refresh(true) end
  return ns.profile
end

local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

function Diag.Status()
  local p = profile()
  local id = p.identity
  f("version %s, client %s (build %s, interface %s), locale %s", ns.version, tostring(id.client and id.client.version),
    tostring(id.client and id.client.build), tostring(id.client and id.client.interface), tostring(id.locale))
  local mods = {}
  for name in pairs(ns.modules) do mods[#mods + 1] = name end
  table.sort(mods)
  f("modules (%d): %s", #mods, table.concat(mods, ", "))
  f("scans: %d; last scan %ds ago%s; profile %s; pending items %d", ns.CharacterScanner.scans,
    (time and time() or 0) - (p.meta.time or 0), p.meta.inCombat and " (in combat)" or "",
    p.meta.complete and (GOOD .. "complete|r") or (NOTE .. "incomplete|r"), p.meta.pendingItems or 0)
  -- right now (not from the last scan): combat and what the game hides
  local hiddenStats = ns.CharacterAPI.StatsRestricted()
  local hiddenAuras = ns.AuraAPI.Restricted()
  local probe = Compat.Value("GetCritChance")
  f("now: in combat %s; stats hidden %s (crit reads %s); auras hidden %s; waiting for combat to end: %s",
    tostring(Compat.InCombat()), tostring(hiddenStats), probe and string.format("%.2f", probe) or "hidden", tostring(hiddenAuras),
    tostring(ns.CharacterScanner.waitingForCombat == true))
  local bad = ns.EquipmentAPI.VerifySlots()
  f("equipment slots vs the client: %s", #bad == 0 and (GOOD .. "all " .. #ns.EquipmentAPI.SLOTS .. " match|r") or (BAD .. table.concat(bad, "; ") .. "|r"))
  local failed = {}
  for e, err in pairs(ns.Events.failed) do failed[#failed + 1] = e .. " (" .. err .. ")" end
  f("events: %s", #failed == 0 and (GOOD .. "all registered|r") or (BAD .. "not registered: " .. table.concat(failed, ", ") .. "|r"))
  f("errors caught: %d%s", ns.errors.count, ns.errors.recent[1] and (" - last: " .. ns.errors.recent[1]) or "")
  if #p.issues == 0 then f("issues: %snone|r", GOOD) end
  for _, i in ipairs(p.issues) do f("%s%s|r [%s] %s", i.level == "warn" and BAD or NOTE, i.level, i.code, i.text) end
end

function Diag.Char()
  local p = profile()
  local id, t = p.identity, p.talents
  f("%s%s: level %s %s %s (race %s, class %s/%s), spec index %s", tostring(id.name), (id.realm and id.realm ~= "") and ("-" .. id.realm) or "", tostring(id.level),
    tostring(id.raceName), tostring(id.className), tostring(id.race), tostring(id.class), tostring(id.classID), tostring(id.specIndex))
  local trees = {}
  for _, tr in ipairs(t.trees) do trees[#trees + 1] = string.format("%s %d", tostring(tr.name), tr.points or 0) end
  f("talents: %s (%d points%s)", #trees > 0 and table.concat(trees, " / ") or "none read", t.totalPoints or 0,
    t.primaryTree and (", mostly " .. t.primaryTree) or "")
  f("stats: %d read, %d hidden, %d unavailable%s", count(p.stats.values), count(p.stats.hidden), count(p.stats.missing),
    p.stats.stale and " (last readable set: the game hides them now)" or "")
  f("spells known: %d; buffs %d, debuffs %d%s", p.spells.count or 0, #p.buffs.helpful, #p.buffs.harmful,
    p.buffs.restricted and " (hidden now)" or "")
  f("fingerprint: %s", tostring(p.meta.fingerprint):sub(1, 120))
end

function Diag.Stats(filter)
  local p = profile()
  local keys = {}
  for k in pairs(p.stats.values) do if not filter or k:lower():find(filter, 1, true) then keys[#keys + 1] = k end end
  table.sort(keys)
  local line = {}
  for _, k in ipairs(keys) do
    line[#line + 1] = string.format("%s=%s", k, string.format("%.4g", p.stats.values[k]))
    if #line == 4 then P(table.concat(line, "  ")); line = {} end
  end
  if #line > 0 then P(table.concat(line, "  ")) end
  for k, v in pairs(p.stats.text or {}) do if not filter or k:find(filter, 1, true) then f("%s = %s", k, v) end end
  local hidden, missing = {}, {}
  for k in pairs(p.stats.hidden) do if not filter or k:lower():find(filter, 1, true) then hidden[#hidden + 1] = k end end
  for k, why in pairs(p.stats.missing) do if not filter or k:lower():find(filter, 1, true) then missing[#missing + 1] = k .. " (" .. tostring(why) .. ")" end end
  table.sort(hidden); table.sort(missing)
  if #hidden > 0 then f("%shidden by the game:|r %s", NOTE, table.concat(hidden, ", ")) end
  if #missing > 0 then f("%snot available:|r %s", BAD, table.concat(missing, ", ")) end
  for slot, w in pairs(p.stats.weaponSkills) do
    f("weapon skill, slot %d: %s %s%s/%s (skill line %s)", slot, tostring(w.name), tostring(w.rank),
      (w.modifier and w.modifier ~= 0) and (" +" .. w.modifier) or "", tostring(w.maxRank), tostring(w.skillLineID))
  end
end

function Diag.Gear()
  local p = profile()
  for _, s in ipairs(ns.EquipmentAPI.SLOTS) do
    local it = p.equipment.slots[s.id]
    if not it or it.empty then
      f("%s%-14s empty|r", DIM, s.name)
    elseif not it.loaded then
      f("%-14s %sitem %s loading...|r", s.name, NOTE, tostring(it.itemID))
    else
      local extra = {}
      if it.enchantID then extra[#extra + 1] = "enchant " .. it.enchantID end
      if #(it.gemIDs or {}) > 0 then extra[#extra + 1] = "gems " .. table.concat(it.gemIDs, ",") end
      if (it.sockets or 0) > 0 then extra[#extra + 1] = it.sockets .. " sockets" end
      if it.setID then extra[#extra + 1] = "set " .. it.setID end
      if it.tempEnchants and #it.tempEnchants > 0 then extra[#extra + 1] = "temp enchant " .. it.tempEnchants[1].enchantID end
      if it.useSpell then extra[#extra + 1] = "use/equip spell " .. tostring(it.useSpell.spellID) end
      f("%-14s %s ilvl %s, %d stats%s", s.name, it.link or it.name, tostring(it.itemLevel), count(it.stats),
        #extra > 0 and (" - " .. table.concat(extra, ", ")) or "")
    end
  end
  for setID, set in pairs(p.sets) do f("set %d %s: %d piece(s) worn", setID, tostring(set.name), set.count) end
end

function Diag.Item(slotText)
  local p = profile()
  local slot = tonumber(slotText)
  local it = slot and p.equipment.slots[slot]
  if not it then return P("usage: /eqn item <slot number> (1 head, 2 neck, 3 shoulders, 15 back, 5 chest, 9 wrists, 10 hands, 6 waist, 7 legs, 8 feet, 11-12 rings, 13-14 trinkets, 16 main hand, 17 off hand, 18 ranged)") end
  if it.empty then return f("slot %d is empty", slot) end
  f("slot %d: %s (item %s, %s)", slot, tostring(it.link), tostring(it.itemID), it.loaded and "loaded" or "loading")
  local keys = {}
  for k in pairs(it.stats or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do f("  %s = %s", k, tostring(it.stats[k])) end
  f("  equipLoc %s, class %s/%s, quality %s, req level %s", tostring(it.equipLoc), tostring(it.classID),
    tostring(it.subclassID), tostring(it.quality), tostring(it.minLevel))
end

function Diag.Talents(all)
  local p = profile()
  local t = p.talents
  if not t.readable then return P(BAD .. "talents not readable|r (see /eqn status)") end
  for _, tr in ipairs(t.trees) do
    local list = {}
    for _, n in ipairs(t.nodes) do
      if n.groupID == tr.groupID and (all or (n.rank or 0) > 0) then
        list[#list + 1] = string.format("%s %d/%s", n.name, n.rank or 0, tostring(n.maxRank))
      end
    end
    f("%s%s|r (%d): %s", NOTE, tostring(tr.name), tr.points or 0, #list > 0 and table.concat(list, ", ") or "-")
  end
  local loose = {}
  for _, n in ipairs(t.nodes) do
    if not n.groupID and (all or (n.rank or 0) > 0) then
      loose[#loose + 1] = string.format("%s %d/%s (groups %s)", n.name, n.rank or 0, tostring(n.maxRank), table.concat(n.groupIDs or {}, ","))
    end
  end
  if #loose > 0 then f("%snot matched to a tree:|r %s", BAD, table.concat(loose, ", ")) end
  local ids = {}
  for _, tr in ipairs(t.trees) do ids[#ids + 1] = string.format("%s=%s (game counts %s)", tostring(tr.name), tostring(tr.groupID), tostring(tr.spentByGame)) end
  f("%stree groups: %s; %d points in all|r", DIM, table.concat(ids, ", "), t.totalPoints or 0)
end

function Diag.Buffs()
  local p = profile()
  if p.buffs.restricted then return P("auras are hidden right now (combat?)") end
  for _, kind in ipairs({ "helpful", "harmful" }) do
    for _, a in ipairs(p.buffs[kind]) do
      f("%s %s (spell %s)%s%s", kind == "helpful" and "buff" or "debuff", tostring(a.name), tostring(a.spellId),
        (a.applications or 0) > 1 and (" x" .. a.applications) or "", a.isFromPlayerOrPlayerPet and " - yours" or "")
    end
  end
end

function Diag.Spells(filter)
  local p = profile()
  local list = {}
  for id, name in pairs(p.spells.known) do
    if not filter or name:lower():find(filter, 1, true) then list[#list + 1] = name .. " [" .. id .. "]" end
  end
  table.sort(list)
  f("%d spells known%s", p.spells.count or 0, filter and (", matching: " .. #list) or "")
  if filter then for i = 1, math.min(#list, 40) do P("  " .. list[i]) end end
end

function Diag.Api()
  local rows = {}
  for path, src in pairs(Compat.KNOWN) do
    local s = Compat.status[path]
    local runtime
    if not Compat.Has(path) then runtime = BAD .. "MISSING|r"
    elseif not s then runtime = DIM .. "present, not called yet|r"
    elseif s.error > 0 then runtime = BAD .. "errors " .. s.error .. "|r (" .. tostring(s.last) .. ")"
    elseif s.secret > 0 and s.ok == 0 then runtime = NOTE .. "hidden every time|r"
    else runtime = GOOD .. "ok " .. s.ok .. "|r" .. (s.secret > 0 and (", hidden " .. s.secret) or "") end
    rows[#rows + 1] = string.format("%s [%s]: %s", path, src, runtime)
  end
  table.sort(rows)
  local bad = 0
  for _, r in ipairs(rows) do if r:find("MISSING") or r:find("errors") then bad = bad + 1; P(r) end end
  f("%d APIs checked, %d missing or erroring (shown above). /eqn api all lists every one.", #rows, bad)
  return rows
end

function Diag.Dump()
  local p = profile(true)
  local realm = p.identity.realm
  local key = tostring(p.identity.name) .. ((realm and realm ~= "") and ("-" .. realm) or "")
  local api = {}
  for path, src in pairs(Compat.KNOWN) do
    local s = Compat.status[path]
    api[path] = { source = src, present = Compat.Has(path), ok = s and s.ok or 0, secret = s and s.secret or 0,
      error = s and s.error or 0, missing = s and s.missing or 0, last = s and s.last }
  end
  ns.db.snapshots[key] = { taken = time and time() or 0, version = ns.version, profile = ns.Database.Copy(p), api = api,
    events = { failed = ns.Database.Copy(ns.Events.failed), seen = ns.Database.Copy(ns.Events.seen) },
    errors = ns.Database.Copy(ns.errors) }
  f("saved a snapshot for %s. It's written to WTF/Account/<account>/SavedVariables/EquipThisNext.lua at /reload or logout.", key)
end


-- Milestone 2: the model, the sheet check, marginal values, comparisons
local function ctxOrSay()
  local ctx, why = ns.Context()
  if not ctx then P(BAD .. "can't evaluate yet:|r " .. tostring(why)) end
  return ctx
end
local function n1(x) return x and string.format("%.1f", x) or "-" end

function Diag.Model()
  local ctx = ctxOrSay(); if not ctx then return end
  local b, s = ctx.base, ctx.state
  f("target: %d level(s) above you (%s); spec: %s", ctx.offset, ns.db.targetOffset == "auto" and "auto" or "set",
    ctx.melee and "melee (DPS = auto attacks, weapon strikes, imbue, item procs)" or "caster/healer (DPS and healing: later in milestone 4)")
  if b.dps then
    local t = b.dpsInfo.table
    f("melee DPS %s: swing %s every %.2fs; miss %.1f%% dodge %.1f%% glancing %.1f%% (-%d%%) crit %.1f%% hit %.1f%%%s; speed x%.3f%s",
      n1(b.dps), n1(s.swing), s.speed, t.miss, t.dodge, t.glance, t.glancePenalty * 100 + 0.5, t.crit, t.hit,
      t.assumedGlancing and " (glancing assumed)" or "", b.dpsInfo.speedMult,
      b.dpsInfo.flurryUptime > 0 and string.format(" (Flurry up %d%%)", b.dpsInfo.flurryUptime * 100 + 0.5) or "")
  elseif b.why.dps then f("DPS: %s", b.why.dps) end
  if b.dps and b.dpsInfo.parts then
    local rows = {}
    for _, part in ipairs(b.dpsInfo.parts) do
      rows[#rows + 1] = string.format("%s %s (%d%%)%s", part.name, n1(part.dps), part.dps / b.dps * 100 + 0.5,
        part.procsPerMin and string.format(" [%.1f/min%s]", part.procsPerMin, part.rateSource == "assumed" and ", rate assumed" or "") or "")
    end
    P("  DPS parts: " .. table.concat(rows, ", "))
    if b.dpsInfo.procStats then
      local st = {}
      for k, v in pairs(b.dpsInfo.procStats) do st[#st + 1] = string.format("%s +%.1f", ns.StatDefs.NAMES[k] or k, v) end
      P("  procs and use effects, averaged: " .. table.concat(st, ", "))
    end
  end
  if b.ehp then
    local e = b.ehpInfo
    f("EHP %d: %d health, you take %.1f%% of the damage (melee %.1f%%: armor cuts %.1f%%%s; spells %.1f%%)",
      b.ehp + 0.5, s.health, e.taken * 100, e.melee * 100, e.armorReduction * 100, e.assumedK and " (armor formula assumed)" or "",
      e.spell * 100)
  end
  for _, note in ipairs(ctx.talents.notes) do P("talent: " .. note) end
end

-- Milestone 4: abilities and imbues as the model reads them
function Diag.Abilities()
  local ctx = ctxOrSay(); if not ctx then return end
  local A = ctx.profile.abilities or {}
  for id, sp in pairs(A.spells or {}) do
    f("%s (%d): %s%s", ns.SpellAPI.Name(id) or "?", id, tostring(sp.desc), sp.cooldownText and (" [" .. sp.cooldownText .. "]") or "")
  end
  for slot, im in pairs(A.imbues or {}) do
    f("imbue on slot %d: enchant %s, your spell %s: %s", slot, tostring(im.enchantID), tostring(im.castSpell), tostring(im.desc or im.procDesc))
  end
  for _, n in ipairs(ctx.abilities.notes) do P("model: " .. n) end
  if #ctx.abilities.notes == 0 then P("no damage abilities or imbues modelled for you yet") end
  local fx = {}
  for _, e in ipairs(ctx.state.effects or {}) do fx[#fx + 1] = string.format("%s: %s", tostring(e.item), e.kind) end
  f("item effects counted: %s", #fx > 0 and table.concat(fx, "; ") or "none")
end

-- Milestone 4: the model against the game's own damage meter, for your last fight. Compared as
-- shares of the damage the model covers (so downtime and spells it doesn't model don't skew it).
local MATCH = { ["auto attack"] = { "auto attack", "melee" }, ["off-hand"] = { "off%-hand", "offhand" } }
local function matches(partName, spellName)
  local s, key = spellName:lower(), partName:lower()
  for _, w in ipairs(MATCH[key] or { (key:gsub(" %d+$", "")) }) do if s:find(w) then return true end end
  return false
end
-- /eqn measure [last|reset]: all fights since the meter's reset (default), or the last one
function Diag.Measure(arg)
  local Meter = ns.MeterAPI
  local ok, why = Meter.Available()
  if not ok then return P("the game's damage meter isn't available: " .. tostring(why)) end
  if ns.Compat.InCombat() then return P("after the fight: the damage meter is hidden in combat") end
  if arg == "reset" then
    Meter.Reset()
    return P("damage meter cleared (the game's own meter too). Fight 15-20 mobs as you normally do, then /eqn measure.")
  end
  local sessions = Meter.Sessions()
  if #sessions == 0 then return P("no finished fight yet: fight 15-20 mobs as you normally do (/eqn measure reset first), then /eqn measure") end
  local guid = ns.Compat.Value("UnitGUID", "player")
  local m, why2, dur, label, fights
  if arg == "last" then
    local sess = Meter.LastSession()
    m, why2 = Meter.MySpells(sess.id, guid)
    dur, label, fights = sess.duration or 0, "last fight (" .. tostring(sess.name) .. ")", { sess }
  else
    m, why2 = Meter.MySpells("overall", guid)
    dur, label, fights = Meter.OverallDuration() or 0, #sessions .. " fight(s) since the meter's reset", sessions
  end
  if not m then return P(tostring(why2)) end
  local ctx = ctxOrSay(); if not ctx then return end
  local b = ctx.base
  if not (b.dps and b.dpsInfo.parts) then return P("no DPS model for you yet") end
  f("%s: %ds in combat, %d damage%s", label, dur + 0.5, m.total, dur > 0 and string.format(", %.1f DPS", m.total / dur) or "")
  -- short fights: an ability used on cooldown is also used at each pull (floor(fight / cooldown) + 1
  -- times, not fight / cooldown): the model's share is adjusted to the fights' lengths
  local strikeFactor = {}
  for _, st in ipairs(ctx.abilities.strikes or {}) do
    local real, steady = 0, 0
    for _, fgt in ipairs(fights) do
      if fgt.duration and fgt.duration > 0 then
        real = real + math.floor(fgt.duration / st.cooldown) + 1
        steady = steady + fgt.duration / st.cooldown
      end
    end
    if steady > 0 then strikeFactor[st.name] = real / steady end
  end
  -- which measured spells each model part is
  local measured, covered, modelTotal = {}, 0, 0
  local used = {}
  for _, part in ipairs(b.dpsInfo.parts) do
    local amt = 0
    for id, a in pairs(m.spells) do
      local name = ns.SpellAPI.Name(id) or tostring(id)
      if not used[id] and matches(part.name, name) then amt = amt + a; used[id] = true end
    end
    measured[part.name] = amt
    covered = covered + amt
    modelTotal = modelTotal + part.dps * (strikeFactor[part.name] or 1)
  end
  local rec = { time = time and time() or 0, duration = dur, total = m.total, level = ctx.state.level, offset = ctx.offset, fights = #fights, parts = {}, other = {} }
  P("share of the damage the model covers (model vs measured):")
  for _, part in ipairs(b.dpsInfo.parts) do
    local ms = covered > 0 and measured[part.name] / covered or 0
    local mo = part.dps * (strikeFactor[part.name] or 1) / modelTotal
    local ratio = mo > 0 and ms / mo or 0
    local agree = covered > 0 and ms >= 0.05 and ratio > 0.85 and ratio < 1.15
    f("  %s: model %d%%, measured %d%%%s", part.name, mo * 100 + 0.5, ms * 100 + 0.5,
      covered > 0 and (agree and " - agrees" or (ms < 0.05 and mo >= 0.05 and " - not seen in the fight" or "")) or "")
    rec.parts[#rec.parts + 1] = { name = part.name, model = part.dps, measured = measured[part.name] }
    if agree and part.name ~= "auto attack" then ns.db.confirmed[part.name] = true end
  end
  local other = {}
  for id, a in pairs(m.spells) do
    if not used[id] then
      local name = ns.SpellAPI.Name(id) or tostring(id)
      other[#other + 1] = string.format("%s %d%%", name, a / m.total * 100 + 0.5)
      rec.other[#rec.other + 1] = { id = id, name = name, amount = a }
    end
  end
  if #other > 0 then f("  not modelled yet (spells): %s", table.concat(other, ", ")) end
  if dur > 0 then
    f("model DPS %s (always attacking) vs measured %s for the same parts over the fight (lower with downtime)",
      n1(b.dps), n1(covered / dur))
  end
  ns.db.measurements = ns.db.measurements or {}
  table.insert(ns.db.measurements, 1, rec)
  while #ns.db.measurements > 5 do table.remove(ns.db.measurements) end
  ns.evalContext = nil; ns.Cache.Invalidate("evaluation")
end

function Diag.Sheet()
  local ctx = ctxOrSay(); if not ctx then return end
  P("gear vs the character sheet (what the sheet has beyond your gear is buffs, talents and base):")
  local parts = {}
  for _, k in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do
    local b = ctx.beyondGear[k]
    parts[#parts + 1] = string.format("%s gear %d, sheet +%s", k, ctx.gear[k] or 0, b and tostring(b + (ctx.gear[k] or 0)) or "?")
  end
  P(table.concat(parts, "; "))
  local v = ctx.profile.stats.values
  f("attack power from gear %d, sheet bonus %s; armor from gear %d, sheet bonus %s", ctx.gear.AP or 0, tostring(v["ap.pos"]),
    ctx.gear.ARMOR or 0, tostring(v["armor.bonus"]))
  local buffs = {}
  for _, a in ipairs(ctx.profile.buffs.helpful) do buffs[#buffs + 1] = tostring(a.name) end
  f("buffs on you now: %s", #buffs > 0 and table.concat(buffs, ", ") or "none")
  local calc = ctx.profile.calc or {}
  local r = {}
  for cr, x in pairs(calc.ratingPct or {}) do if cr:find("CRIT_MELEE") or cr:find("HIT_MELEE") or cr:find("HASTE_MELEE") or cr:find("DEFENSE") or cr:find("DODGE") then r[#r + 1] = cr == "CR_DEFENSE_SKILL" and string.format("DEFENSE %.3f skill/pt", x) or string.format("%s %.3f%%/pt", (cr:gsub("CR_", "")), x) end end
  table.sort(r)
  f("rating conversions (game): %s", #r > 0 and table.concat(r, ", ") or "none read")
  local g = calc.glancing and calc.glancing[ctx.offset]
  f("glancing vs this target (game): %s", g and string.format("%.1f%% chance, %.1f%% less damage", g.chance * 100, (g.penalty or 0) * 100) or "not read")
  local e = calc.armorEffect and calc.armorEffect[ctx.state.level + ctx.offset]
  f("armor reduction vs this target (game): %s", e and string.format("%.1f%%", e * 100) or "not read")
end

function Diag.Weights()
  local ctx = ctxOrSay(); if not ctx then return end
  local w = ns.Evaluator.Weights(ctx)
  P("value of 10 points of each stat (% change):")
  local rows = {}
  for _, k in ipairs(ns.Evaluator.WEIGHT_STATS) do
    local x = w[k]
    local d = x.dps and string.format("DPS %+.2f%%", x.dps * 10) or nil
    local e = x.ehp and string.format("EHP %+.2f%%", x.ehp * 10) or nil
    if (x.dps and math.abs(x.dps) > 1e-6) or (x.ehp and math.abs(x.ehp) > 1e-6) then
      rows[#rows + 1] = string.format("%s: %s", ns.StatDefs.NAMES[k] or k, table.concat({ d or "", e or "" }, " "))
    end
  end
  for _, r in ipairs(rows) do P("  " .. r) end
end

function Diag.Compare(arg)
  if not arg or arg == "" then return P("usage: /eqn compare <shift-click an item> (or an item ID)") end
  local link = arg:match("|Hitem:[^|]+|h") and arg or (tonumber(arg) and ("item:" .. arg)) or nil
  if not link then return P("give an item link or ID") end
  ns.Cache.Invalidate("evaluation", link)
  local res = ns.Tooltip.Evaluate(link)
  for _, l in ipairs(ns.Tooltip.Lines(res)) do P(l) end
  for _, o in ipairs(res.options or {}) do
    if o.status == "ok" then
      f("%s%s|r: DPS %s, EHP %s", o == res.best and NOTE or DIM, o.slotName, ns.Tooltip.Pct(o.dps) or "-", ns.Tooltip.Pct(o.ehp) or "-")
      for _, n in ipairs(o.notes or {}) do f("   %s", n) end
      for i, part in ipairs(o.parts) do
        if i > 8 then break end
        local name = part.stat == "WEAPON" and "the weapon itself (damage, speed, skill)"
          or part.stat == "EFFECTS" and "item effects (procs, use effects, ability bonuses)"
          or string.format("%+g %s", part.amount, ns.StatDefs.NAMES[part.stat] or part.stat)
        f("   %s: DPS %s, EHP %s", name, ns.Tooltip.Pct(part.dps) or "-", ns.Tooltip.Pct(part.ehp) or "-")
      end
      if o.carry and #o.carry > 0 then f("   enchant carried over: %s", table.concat(o.carry, "; ")) end
      for _, t in ipairs(o.setGained or {}) do f("   set bonus gained: %s", t) end
      for _, t in ipairs(o.setLost or {}) do f("   set bonus lost: %s", t) end
      if o.lost and #o.lost > 0 then f("   %sthe replaced item's effects (not counted): %s|r", NOTE, table.concat(o.lost, " | ")) end
    else
      f("%s%s: %s%s|r", DIM, tostring(o.slotName), o.status, o.why and (" - " .. o.why) or "")
    end
  end
  local item = ns.EquipmentScanner.ReadItem(link)
  if item.effects and #item.effects > 0 then f("%snot counted on this item:|r %s", NOTE, table.concat(item.effects, " | ")) end
  if res.reasons and #res.reasons > 0 then f("%sconfidence %s:|r %s", DIM, tostring(res.confidence), table.concat(res.reasons, "; ")) end
end

function Diag.Target(arg)
  if arg == "auto" then ns.db.targetOffset = "auto"
  elseif tonumber(arg) and tonumber(arg) >= 0 and tonumber(arg) <= 3 then ns.db.targetOffset = tonumber(arg)
  elseif arg then return P("usage: /eqn target auto|0|1|2|3 (levels above yours; auto: +3 at the level cap, +0 below)") end
  ns.evalContext = nil; ns.Cache.Invalidate("evaluation")
  f("target: %s", ns.db.targetOffset == "auto" and "auto" or ("+" .. ns.db.targetOffset .. " levels"))
end

local HELP = {
  "/eqn status - addon, client, scans, slot check, events, errors, issues",
  "/eqn char - who you are, talent points per tree, counts",
  "/eqn stats [text] - every character sheet value read (filter by text, e.g. /eqn stats crit)",
  "/eqn gear - each slot: item, item level, enchant, gems, set, loaded or loading",
  "/eqn item <slot> - one slot's item stats",
  "/eqn talents [all] - talents with ranks per tree (all: also the ones at 0)",
  "/eqn buffs - your buffs and debuffs (out of combat)",
  "/eqn spells [text] - spells known (with text: list the matches)",
  "/eqn api [all] - which game functions exist and how calls went",
  "/eqn model - current DPS and EHP with the attack table and talents used",
  "/eqn sheet - your gear vs the character sheet (buffs), and the game's conversions",
  "/eqn weights - what 10 points of each stat change, right now",
  "/eqn compare <item link or ID> - full comparison: each slot, each stat's part, effects not counted",
  "/eqn target auto|0|1|2|3 - target level above yours",
  "/eqn abilities - your abilities, imbue and item effects as the model counts them",
  "/eqn measure [last|reset] - the model's DPS parts vs the game's damage meter (all fights since reset, or the last)",
  "/eqn tooltip - comparison on item tooltips on/off",
  "/eqn scan - read everything again now",
  "/eqn dump - save everything to the SavedVariables file (for bug reports and tests)",
  "/eqn debug - print caught errors as they happen",
}

SLASH_EQUIPTHISNEXT1 = "/eqn"
SlashCmdList.EQUIPTHISNEXT = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  local rawRest = rest
  rest = rest ~= "" and rest:lower() or nil
  local run = {
    status = Diag.Status, char = Diag.Char, stats = function() Diag.Stats(rest) end, gear = Diag.Gear,
    item = function() Diag.Item(rest) end, talents = function() Diag.Talents(rest == "all") end, buffs = Diag.Buffs,
    spells = function() Diag.Spells(rest) end,
    api = function() local rows = Diag.Api(); if rest == "all" then for _, r in ipairs(rows) do P(r) end end end,
    scan = function() profile(true); P("scanned.") ; Diag.Char() end,
    model = Diag.Model, sheet = Diag.Sheet, weights = Diag.Weights, abilities = Diag.Abilities, measure = function() Diag.Measure(rest) end,
    compare = function() Diag.Compare(rawRest) end, target = function() Diag.Target(rest) end,
    tooltip = function() ns.db.tooltip = not ns.db.tooltip; P("tooltip " .. (ns.db.tooltip and "on" or "off")) end,
    dump = Diag.Dump,
    debug = function() ns.db.debug = not ns.db.debug; P("debug " .. (ns.db.debug and "on" or "off")) end,
  }
  local fn = run[cmd]
  if not fn then for _, h in ipairs(HELP) do P(h) end return end
  local ok, err = ns.Safe("/eqn " .. cmd, fn)
  if ok == false then P(BAD .. "error:|r " .. tostring(err)) end
end

ns.Events.On("PLAYER_LOGIN", "hello", function()
  ns.Print("loaded (test build " .. ns.version .. ": compares gear by modelled melee DPS - abilities, imbues, procs - and EHP). /eqn for commands.")
end)
