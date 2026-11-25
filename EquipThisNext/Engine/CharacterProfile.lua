-- CharacterProfile: the normalized description of a character that every evaluation module will
-- read. Pure Lua: nothing here touches the game, so it's built and checked the same way in the game
-- and in the offline tests (Tests/).
--
-- Shape (schema 1):
--   meta      = { schema, addonVersion, time, inCombat, complete, pendingItems = n }
--   identity  = { name, realm, class, race, level, ..., client = { version, build, interface } }
--   stats     = { values = { ["crit.melee"] = 5.2, ... }, hidden = { key = true }, missing = { key = why },
--                 restricted = bool, takenAt = time, weaponSkills = { [slot] = { skillLineID, name, rank, modifier, maxRank } } }
--   equipment = { slots = { [slotID] = Item }, pending = { [itemID] = slotID } }
--      Item   = { slot, slotName, empty = true }  or
--               { slot, slotName, link, itemID, enchantID, gemIDs, suffixID, loaded = bool,
--                 name, quality, itemLevel, equipLoc, classID, subclassID, setID, sockets,
--                 stats = { ITEM_MOD_... = n } (nil while not loaded: never empty stats), tempEnchants }
--   sets      = { [setID] = { name, count, slots = { slotID... } } }
--   talents   = { configID, readable = bool, trees = { { treeID, groupID, name, order, points } },
--                 nodes = { { nodeID, groupID, entryID, definitionID, spellID, name, rank, maxRank } },
--                 primaryTree, totalPoints }
--   buffs     = { restricted = bool, helpful = { Aura }, harmful = { Aura } }
--   spells    = { known = { [spellID] = name }, count }
--   issues    = { { level = "warn"|"info", code, text } }
local _, ns = ...
local P = ns and ns.Module and ns.Module("CharacterProfile") or {}

P.SCHEMA = 1

function P.New()
  return {
    meta = { schema = P.SCHEMA },
    identity = {},
    stats = { values = {}, text = {}, hidden = {}, missing = {}, weaponSkills = {} },
    equipment = { slots = {}, pending = {} },
    sets = {},
    talents = { trees = {}, nodes = {} },
    buffs = { helpful = {}, harmful = {} },
    spells = { known = {}, count = 0 },
    issues = {},
  }
end

function P.AddIssue(p, level, code, text)
  p.issues[#p.issues + 1] = { level = level, code = code, text = text }
end

-- Item set pieces worn: { [setID] = { count, slots } } (names are filled in by the scanner).
function P.CountSets(equipment)
  local sets = {}
  for slot, it in pairs(equipment.slots or {}) do
    if it.setID and it.setID > 0 then
      local s = sets[it.setID] or { count = 0, slots = {} }
      s.count = s.count + 1
      s.slots[#s.slots + 1] = slot
      sets[it.setID] = s
    end
  end
  for _, s in pairs(sets) do table.sort(s.slots) end
  return sets
end

-- Talent points per tree from the nodes' ranks (nodes carry the group = tree they belong to).
function P.SumTreePoints(talents)
  local byGroup, total = {}, 0
  for _, n in ipairs(talents.nodes or {}) do
    local r = n.rank or 0
    if r > 0 then
      total = total + r
      if n.groupID then byGroup[n.groupID] = (byGroup[n.groupID] or 0) + r end
    end
  end
  local best
  for _, t in ipairs(talents.trees or {}) do
    t.points = byGroup[t.groupID] or 0
    if t.points > 0 and (not best or t.points > best.points) then best = t end
  end
  talents.totalPoints = total
  talents.primaryTree = best and best.name or nil
  return talents
end

-- What decides whether a cached evaluation still applies: gear, talents and level.
function P.Fingerprint(p)
  local parts = { tostring(p.identity.level), tostring(p.identity.class) }
  local slots = {}
  for slot in pairs(p.equipment.slots) do slots[#slots + 1] = slot end
  table.sort(slots)
  for _, slot in ipairs(slots) do
    local it = p.equipment.slots[slot]
    parts[#parts + 1] = slot .. "=" .. (it.empty and "-" or (tostring(it.itemID) .. ":" .. tostring(it.enchantID or 0)
      .. ":" .. table.concat(it.gemIDs or {}, ",") .. (it.loaded and "" or "?")))
  end
  local ranks = {}
  for _, n in ipairs(p.talents.nodes or {}) do
    if (n.rank or 0) > 0 then ranks[#ranks + 1] = tostring(n.nodeID) .. "x" .. n.rank end
  end
  table.sort(ranks)
  parts[#parts + 1] = "t:" .. table.concat(ranks, ",")
  return table.concat(parts, "|")
end

-- Problems in a profile that later modules must not paper over. Returns a list of texts (empty = fine).
function P.Validate(p)
  local bad = {}
  if p.meta.schema ~= P.SCHEMA then bad[#bad + 1] = "schema " .. tostring(p.meta.schema) end
  if not p.identity.class then bad[#bad + 1] = "no class" end
  if type(p.identity.level) ~= "number" or p.identity.level < 1 then bad[#bad + 1] = "no level" end
  local pendingCount = 0
  for slot, it in pairs(p.equipment.slots) do
    if not it.empty then
      if not it.itemID then bad[#bad + 1] = "slot " .. slot .. ": item without an ID" end
      if it.loaded and type(it.stats) ~= "table" then bad[#bad + 1] = "slot " .. slot .. ": loaded but no stat table" end
      if not it.loaded then
        pendingCount = pendingCount + 1
        if it.stats ~= nil then bad[#bad + 1] = "slot " .. slot .. ": not loaded but has stats" end
        if p.equipment.pending[it.itemID] == nil then bad[#bad + 1] = "slot " .. slot .. ": not loaded and not requested" end
      end
    end
  end
  if (p.meta.pendingItems or 0) ~= pendingCount then
    bad[#bad + 1] = string.format("pending count %s, slots waiting %d", tostring(p.meta.pendingItems), pendingCount)
  end
  for key, v in pairs(p.stats.values) do
    if type(v) ~= "number" then bad[#bad + 1] = "stat " .. key .. " is not a number" end
    if p.stats.hidden[key] then bad[#bad + 1] = "stat " .. key .. " is both read and hidden" end
  end
  local sum = 0
  for _, n in ipairs(p.talents.nodes) do
    if (n.rank or 0) > (n.maxRank or math.huge) then bad[#bad + 1] = "talent " .. tostring(n.name) .. " above its max rank" end
    sum = sum + (n.rank or 0)
  end
  if p.talents.totalPoints and p.talents.totalPoints ~= sum then bad[#bad + 1] = "talent points don't add up" end
  return bad
end

-- true when every item is loaded and stats were readable (an evaluation would be complete)
function P.IsComplete(p)
  return (p.meta.pendingItems or 0) == 0 and not p.stats.restricted and p.talents.readable == true
end
