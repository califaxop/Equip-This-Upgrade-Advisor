-- FightRecorder (Equip This! 5.0): after each fight, what the game's damage meter says you did.
--   learn (on by default; stays on your computer): your damage and healing per spell are added up
--     per class and spec, and every few fights the rotation is learned from them again (the same
--     way /eqn measure does), so comparisons follow how you really play. Older fights count less
--     (the totals halve past 60 fights).
--   share (opt in, off by default): each fight is also kept as an anonymous record (no name, realm
--     or IDs: class, spec, level, fight length, damage and healing per spell, the model's split) for
--     /eqt report, to paste to the author. Nothing leaves the game on its own: addons can't send
--     anything.
local _, ns = ...
local FR = ns.Module("FightRecorder")
local Events, Compat = ns.Events, ns.Compat
FR.MIN_FIGHT = 6        -- seconds: shorter fights are left out
FR.SLACK = 5            -- seconds the meter's session may run past your own combat timer
FR.MAX_FIGHT = 3600     -- seconds: no single fight is longer (anything above is a meter glitch)
FR.LEARN_AFTER = 8      -- fights before the first learning
FR.RELEARN_EVERY = 3    -- fights between learnings
FR.HALVE_AFTER = 60     -- fights: then the totals halve
FR.SHARE_MAX = 200
FR.REMIND_AT = 25       -- new records before the "time to share" reminder
-- ...and at most once per reminder window, twice a week: after the weekly maintenance (Wednesday,
-- Equip This!'s release time: 12:00 UTC) and on Sunday (midnight, your own time)
FR.MAINTENANCE = { wday = 3, hour = 12 }   -- (UTC; weekday 0 = Sunday ... 3 = Wednesday)

local function byName(spells)
  local out = {}
  for id, a in pairs(spells or {}) do
    local n = ns.SpellAPI.Name(id) or tostring(id)
    out[n] = (out[n] or 0) + a
  end
  return out
end

-- add one fight to the totals; learn again when it's time. Pure apart from ns.db.
function FR.Add(ctx, key, dmg, heal, duration)
  local db = ns.db
  db.fightLog = db.fightLog or {}
  local log = db.fightLog[key] or { duration = 0, fights = 0, spells = {}, healing = {}, learnedAt = 0 }
  db.fightLog[key] = log
  log.duration, log.fights = log.duration + duration, log.fights + 1
  for n, a in pairs(dmg) do log.spells[n] = (log.spells[n] or 0) + a end
  for n, a in pairs(heal) do log.healing[n] = (log.healing[n] or 0) + a end
  if log.fights > FR.HALVE_AFTER then
    log.duration, log.fights, log.learnedAt = log.duration / 2, log.fights / 2, (log.learnedAt or 0) / 2
    for n, a in pairs(log.spells) do log.spells[n] = a / 2 end
    for n, a in pairs(log.healing) do log.healing[n] = a / 2 end
  end
  if log.fights >= FR.LEARN_AFTER and log.fights - (log.learnedAt or 0) >= FR.RELEARN_EVERY then
    local rec = ns.Evaluator.RecordFrom(ctx, log.spells, log.healing, log.duration, log.fights)
    local rot = ns.Evaluator.LearnRotation(ctx, rec)
    if rot.source == "measured" then
      rot.auto = true
      db.rotation = db.rotation or {}
      db.rotation[key] = rot
      log.learnedAt = log.fights
      ns.evalContext = nil
      ns.Cache.Invalidate("evaluation")
      return rot
    end
  end
end

-- an anonymous record for sharing
function FR.Share(ctx, dmg, heal, duration)
  local db = ns.db
  db.shared = db.shared or {}
  local class = ctx.profile.identity and ctx.profile.identity.class
  local rec = { v = ns.version, c = class, t = ctx.profile.talents and ctx.profile.talents.primaryTree,
    l = ctx.state.level, d = math.floor(duration * 10 + 0.5) / 10, dmg = {}, heal = {}, mdl = {} }
  for n, a in pairs(dmg) do rec.dmg[n] = math.floor(a + 0.5) end
  for n, a in pairs(heal) do rec.heal[n] = math.floor(a + 0.5) end
  local tot = ctx.base.dps or 0
  for _, p in ipairs(ctx.base.dpsInfo and ctx.base.dpsInfo.parts or {}) do
    if tot > 0 then rec.mdl[p.name] = math.floor(p.dps / tot * 1000 + 0.5) / 10 end
  end
  table.insert(db.shared, rec)
  while #db.shared > FR.SHARE_MAX do table.remove(db.shared, 1) end
  FR.MaybeRemind()
  return rec
end

function FR.OnCombatEnd()
  local db = ns.db
  if not db or not (db.learn or db.share) then return end
  local Meter = ns.MeterAPI
  if not Meter.Available() or Compat.InCombat() then return end
  local sess = Meter.LastSession()
  local own = FR.combatLength -- (this combat, by Equip This!'s own timer; nil after a /reload in combat)
  FR.combatLength = nil
  if not sess or type(sess.duration) ~= "number" or sess.duration < FR.MIN_FIGHT then return end
  if sess.id == FR.lastID or sess.id == db.lastSession then return end -- (recorded already, also before a /reload)
  -- The meter can hand back a session that isn't this fight (seen on Forever: one 4,277,495 s
  -- long, which then wrecked the learned rotation): it must fit inside the combat that just ended.
  if not own or sess.duration > own + FR.SLACK or sess.duration > FR.MAX_FIGHT then
    FR.rejected = (FR.rejected or 0) + 1
    return
  end
  FR.lastID, db.lastSession = sess.id, sess.id
  local guid = Compat.Value("UnitGUID", "player")
  local m = Meter.MySpells(sess.id, guid)
  if not m or m.total <= 0 then return end
  local h = Meter.MySpells(sess.id, guid, Meter.HEALING_DONE)
  local ctx = ns.Context and ns.Context()
  if not ctx then return end
  local dmg, heal = byName(m.spells), byName(h and h.spells)
  local key = ns.Evaluator.RotationKey(ctx.profile)
  FR.fights = (FR.fights or 0) + 1
  if db.learn then FR.Add(ctx, key, dmg, heal, sess.duration) end
  if db.share then FR.Share(ctx, dmg, heal, sess.duration) end
end

-- The opt-in records as text to copy: one line a fight.
--   EQT5|<version>|<CLASS>|<Tree>|<level>|<seconds>|dmg:<spell>=<amount>;...|heal:...|model:<part>=<%>;...
function FR.ReportText()
  local out = { "Equip This! fight records (anonymous: class, spec, level, damage and healing per spell). Thank you!" }
  local function list(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k):gsub("[|;=]", " ") .. "=" .. tostring(t[k]) end
    return table.concat(parts, ";")
  end
  for _, r in ipairs(ns.db and ns.db.shared or {}) do
    out[#out + 1] = table.concat({ "EQT5", tostring(r.v), tostring(r.c), tostring(r.t), tostring(r.l), tostring(r.d),
      "dmg:" .. list(r.dmg), "heal:" .. list(r.heal), "model:" .. list(r.mdl) }, "|")
  end
  return table.concat(out, "\n"), #out - 1
end

-- your own combat timer: a meter session longer than the combat that just ended isn't that fight
local combatStart
Events.On("PLAYER_REGEN_DISABLED", "fights", function() combatStart = GetTime() end)
Events.On("PLAYER_REGEN_ENABLED", "fights", function()
  FR.combatLength = combatStart and (GetTime() - combatStart) or nil
  combatStart = nil
  -- (the meter's session closes a moment after combat ends)
  Events.Debounce("fightRecord", 2, function() ns.Safe("fight recorder", FR.OnCombatEnd) end)
end)

-- Saved records and learned totals from before 5.0.3 may hold a fight with an impossible length
-- (the meter glitch above): those records are dropped, and a learned rotation built on them is
-- forgotten, to be learned again from new fights. Returns how many records and rotations went.
function FR.Repair()
  local db = ns.db
  if not db then return 0, 0 end
  local recs, rots = 0, 0
  local kept = {}
  for _, r in ipairs(db.shared or {}) do
    if type(r.d) == "number" and r.d > 0 and r.d <= FR.MAX_FIGHT then kept[#kept + 1] = r else recs = recs + 1 end
  end
  db.shared = kept
  for key, log in pairs(db.fightLog or {}) do
    if type(log.duration) ~= "number" or (log.fights or 0) <= 0 or log.duration / log.fights > FR.MAX_FIGHT then
      db.fightLog[key] = nil
      if db.rotation and db.rotation[key] and db.rotation[key].auto then db.rotation[key] = nil end
      rots = rots + 1
    end
  end
  if recs + rots > 0 then
    ns.evalContext = nil
    ns.Cache.Invalidate("evaluation")
  end
  return recs, rots
end
Events.On("PLAYER_LOGIN", "fightRepair", function()
  local recs, rots = FR.Repair()
  if recs + rots > 0 then
    ns.Print(string.format("fixed %d fight record(s) with an impossible length (a damage meter glitch)%s.", recs,
      rots > 0 and "; your rotation will be learned again from your next fights" or ""))
  end
end)

---------------------------------------------------------------------------
-- Sharing (5.0, like Questie's trace export): what's waiting, one line to copy, and a reminder.
---------------------------------------------------------------------------
-- what the records hold, for the export window: { fights, seconds, specs = { "Enhancement Shaman" },
-- spells (distinct), levels = { min, max }, sentBefore }
function FR.Summary()
  local db = ns.db or {}
  local out = { fights = 0, seconds = 0, specs = {}, spells = 0, sentBefore = db.reported or 0 }
  local specSeen, spellSeen = {}, {}
  for _, r in ipairs(db.shared or {}) do
    out.fights = out.fights + 1
    out.seconds = out.seconds + (r.d or 0)
    local spec = tostring(r.t) .. " " .. tostring(r.c):sub(1, 1) .. tostring(r.c):sub(2):lower()
    if not specSeen[spec] then specSeen[spec] = true; out.specs[#out.specs + 1] = spec end
    for n in pairs(r.dmg or {}) do spellSeen[n] = true end
    for n in pairs(r.heal or {}) do spellSeen[n] = true end
    if r.l then
      out.levels = out.levels or { r.l, r.l }
      out.levels[1], out.levels[2] = math.min(out.levels[1], r.l), math.max(out.levels[2], r.l)
    end
  end
  for _ in pairs(spellSeen) do out.spells = out.spells + 1 end
  return out
end

-- everything waiting, as one line to copy (readable on purpose: what you send is what you see):
--   EquipThis:Fights:1!v=5.0.0,c=SHAMAN,t=Enhancement,l=42,d=34.2,dmg=Attack:1234;Stormstrike:2000,heal=,mdl=auto attack:24.3!...!End:EquipThis:Fights:1
local function clean(x) return (tostring(x):gsub("[!,;:=|]", " ")) end
local function pairsText(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = clean(k) .. ":" .. tostring(t[k]) end
  return table.concat(out, ";")
end
function FR.ExportString()
  local parts = { "EquipThis:Fights:1" }
  for _, r in ipairs(ns.db and ns.db.shared or {}) do
    parts[#parts + 1] = string.format("v=%s,c=%s,t=%s,l=%s,d=%s,dmg=%s,heal=%s,mdl=%s", clean(r.v), clean(r.c), clean(r.t),
      clean(r.l), clean(r.d), pairsText(r.dmg), pairsText(r.heal), pairsText(r.mdl))
  end
  parts[#parts + 1] = "End:EquipThis:Fights:1"
  return table.concat(parts, "!"), #parts - 2
end

-- you've sent them: they're cleared (the next export is only what's new)
function FR.MarkReported()
  local db = ns.db
  local n = #(db.shared or {})
  db.reported = (db.reported or 0) + n
  db.shared = {}
  db.lastReported = time and time() or 0
  FR.reminded = nil
  return n
end

-- the start of the latest reminder window at or before `now` (seconds since 1970, UTC)
function FR.WindowStart(now)
  -- after maintenance: the latest Wednesday 12:00 UTC (1 Jan 1970 was a Thursday: weekday 4)
  local day = math.floor(now / 86400)
  local back = ((day + 4) % 7 - FR.MAINTENANCE.wday) % 7
  local maint = (day - back) * 86400 + FR.MAINTENANCE.hour * 3600
  if maint > now then maint = maint - 7 * 86400 end
  -- Sunday: the latest Sunday midnight, your own time
  local sun = 0
  if date then
    local t = date("*t", now)
    sun = time({ year = t.year, month = t.month, day = t.day - (t.wday - 1), hour = 0, min = 0, sec = 0 })
  end
  return math.max(maint, sun)
end

-- once per reminder window (twice a week) and once a session, with enough new records, out of combat
function FR.MaybeRemind()
  local db = ns.db
  if not (db and db.share) or FR.reminded or Compat.InCombat() then return end
  if #(db.shared or {}) < FR.REMIND_AT then return end
  local now = time and time() or 0
  if db.lastReminded and db.lastReminded >= FR.WindowStart(now) then return end
  FR.reminded = true
  db.lastReminded = now
  if FR.OnRemind then FR.OnRemind(#db.shared)
  else ns.Print(string.format("%d fight records are waiting to be shared (optional): /eqn report", #db.shared)) end
end
