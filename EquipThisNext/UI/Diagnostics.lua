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
  f("scans: %d; profile %s; pending items %d; in combat %s", ns.CharacterScanner.scans,
    p.meta.complete and (GOOD .. "complete|r") or (NOTE .. "incomplete|r"), p.meta.pendingItems or 0, tostring(p.meta.inCombat))
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
  f("%s-%s: level %s %s %s (race %s, class %s/%s), spec index %s", tostring(id.name), tostring(id.realm), tostring(id.level),
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
  local loose = 0
  for _, n in ipairs(t.nodes) do if not n.groupID then loose = loose + 1 end end
  if loose > 0 then f("%d node(s) without a tree group", loose) end
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
  local key = string.format("%s-%s", tostring(p.identity.name), tostring(p.identity.realm))
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
  "/eqn scan - read everything again now",
  "/eqn dump - save everything to the SavedVariables file (for bug reports and tests)",
  "/eqn debug - print caught errors as they happen",
}

SLASH_EQUIPTHISNEXT1 = "/eqn"
SlashCmdList.EQUIPTHISNEXT = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  rest = rest ~= "" and rest:lower() or nil
  local run = {
    status = Diag.Status, char = Diag.Char, stats = function() Diag.Stats(rest) end, gear = Diag.Gear,
    item = function() Diag.Item(rest) end, talents = function() Diag.Talents(rest == "all") end, buffs = Diag.Buffs,
    spells = function() Diag.Spells(rest) end,
    api = function() local rows = Diag.Api(); if rest == "all" then for _, r in ipairs(rows) do P(r) end end end,
    scan = function() profile(true); P("scanned.") ; Diag.Char() end,
    dump = Diag.Dump,
    debug = function() ns.db.debug = not ns.db.debug; P("debug " .. (ns.db.debug and "on" or "off")) end,
  }
  local fn = run[cmd]
  if not fn then for _, h in ipairs(HELP) do P(h) end return end
  local ok, err = ns.Safe("/eqn " .. cmd, fn)
  if ok == false then P(BAD .. "error:|r " .. tostring(err)) end
end

ns.Events.On("PLAYER_LOGIN", "hello", function()
  ns.Print("loaded (test build " .. ns.version .. ": reads your character, doesn't score items yet). Type /eqn for diagnostics.")
end)
