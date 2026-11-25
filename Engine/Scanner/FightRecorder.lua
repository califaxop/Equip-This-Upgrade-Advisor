-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- FightRecorder (Equip This! 5.0): after each fight, what the game's damage meter says you did.
--   learn (on by default; stays on your computer): your damage and healing per spell are added up
--     per class and spec, and every few fights the rotation is learned from them again (the same
--     way /eqn measure does), so comparisons follow how you really play. Older fights count less
--     (the totals halve past 60 fights).
--   share (opt in, off by default): each fight is also kept as an anonymous record (no name, realm
--     or IDs: class, spec, level, fight length, damage and healing per spell, the model's split) for
--     /eqt report, to paste to the author. Nothing leaves the game on its own: addons can't send
--     anything.
local _, ns = ...; ns = ns.Engine
local FR = ns.Module("FightRecorder")
local Events, Compat = ns.Events, ns.Compat
FR.MIN_FIGHT = 6        -- seconds: shorter fights are left out
FR.LEARN_AFTER = 8      -- fights before the first learning
FR.RELEARN_EVERY = 3    -- fights between learnings
FR.HALVE_AFTER = 60     -- fights: then the totals halve
FR.SHARE_MAX = 100

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
  return rec
end

function FR.OnCombatEnd()
  local db = ns.db
  if not db or not (db.learn or db.share) then return end
  local Meter = ns.MeterAPI
  if not Meter.Available() or Compat.InCombat() then return end
  local sess = Meter.LastSession()
  if not sess or not sess.duration or sess.duration < FR.MIN_FIGHT or sess.id == FR.lastID then return end
  FR.lastID = sess.id
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

Events.On("PLAYER_REGEN_ENABLED", "fights", function()
  -- (the meter's session closes a moment after combat ends)
  Events.Debounce("fightRecord", 2, function() ns.Safe("fight recorder", FR.OnCombatEnd) end)
end)
