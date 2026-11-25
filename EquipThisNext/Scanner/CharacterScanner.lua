-- CharacterScanner: builds and keeps the current CharacterProfile (ns.profile), and decides when
-- parts of it are read again. Event-driven: gear changes reread the equipment, talent changes the
-- talents, stat changes the stats; bursts of events are merged (debounced). Nothing is scanned in
-- combat: changes wait until combat ends.
local _, ns = ...
local CharacterScanner = ns.Module("CharacterScanner")
local Events, Cache, P, Compat = ns.Events, ns.Cache, ns.CharacterProfile, ns.Compat

local PARTS = { "identity", "stats", "equipment", "talents", "buffs", "spells", "abilities", "calc", "bags" }
local dirty = {}
for _, p in ipairs(PARTS) do dirty[p] = true end
CharacterScanner.scans = 0

local function scanPart(profile, part)
  if part == "identity" then profile.identity = ns.CharacterAPI.Identity()
  elseif part == "stats" then ns.StatScanner.Scan(profile)
  elseif part == "equipment" then ns.EquipmentScanner.Scan(profile)
  elseif part == "talents" then ns.TalentScanner.Scan(profile)
  elseif part == "buffs" then ns.BuffScanner.Scan(profile)
  elseif part == "spells" then ns.SpellScanner.Scan(profile)
  elseif part == "abilities" then ns.AbilityScanner.Scan(profile)
  elseif part == "calc" then ns.CalcScanner.Scan(profile)
  elseif part == "bags" then ns.BagScanner.Scan(profile) end
end

-- Rescan the parts marked dirty (or all, with force). Returns the profile.
function CharacterScanner.Refresh(force)
  local old = ns.profile
  if Compat.InCombat() and old and not force then
    CharacterScanner.waitingForCombat = true
    return old
  end
  local profile = P.New()
  for _, part in ipairs(PARTS) do
    if force or dirty[part] or not old then
      local before = #profile.issues
      scanPart(profile, part)
      for i = before + 1, #profile.issues do profile.issues[i].part = part end   -- (which part raised it)
      dirty[part] = false
    else
      profile[part] = old[part]
      if part == "equipment" then profile.sets, profile.meta.pendingItems = old.sets, old.meta.pendingItems end
      -- a part not read again keeps its issues until it is
      for _, i in ipairs(old.issues) do
        if i.part == part then profile.issues[#profile.issues + 1] = i end
      end
    end
  end
  -- parts the game hid this time are read again as soon as it allows (at the end of combat)
  if profile.stats.restricted then dirty.stats = true end
  if profile.buffs.restricted then dirty.buffs = true end
  if profile.stats.restricted then dirty.calc = true end
  -- evaluations were built on the old profile
  Cache.Invalidate("evaluation")
  ns.evalContext = nil
  profile.meta.addonVersion = ns.version
  profile.meta.time = time and time() or 0
  profile.meta.inCombat = Compat.InCombat()
  profile.meta.fingerprint = P.Fingerprint(profile)
  profile.meta.complete = P.IsComplete(profile)
  for _, problem in ipairs(P.Validate(profile)) do P.AddIssue(profile, "warn", "invalid", problem) end
  ns.profile = profile
  CharacterScanner.scans = CharacterScanner.scans + 1
  CharacterScanner.waitingForCombat = (dirty.stats or dirty.buffs) and true or false
  Cache.Set("character", "current", profile, profile.meta.fingerprint)
  return profile
end

local function mark(...)
  for i = 1, select("#", ...) do
    local part = select(i, ...)
    dirty[part] = true
    if part == "stats" or part == "talents" or part == "equipment" then dirty.calc = true end
    if part == "equipment" or part == "spells" then dirty.abilities = true end
  end
  Events.Debounce("rescan", 0.5, CharacterScanner.Refresh)
end
CharacterScanner.Mark = mark

local function playerOnly(fn) return function(_, unit) if unit == "player" then fn() end end end

Events.On("ADDON_LOADED", "db", function(_, name)
  if name == ns.name then ns.Database.Load() end
end)
Events.On("PLAYER_ENTERING_WORLD", "scan", function() mark(unpack(PARTS)) end)
Events.On("PLAYER_EQUIPMENT_CHANGED", "scan", function() mark("equipment", "stats", "bags") end)
Events.On("BAG_UPDATE_DELAYED", "bags", function() mark("bags") end)
Events.On("PLAYER_LEVEL_UP", "scan", function() mark("identity", "stats", "spells") end)
-- item data arriving: rescan when it's one we're waiting for
local function itemArrived(_, itemID, success)
  local p = ns.profile
  if p and p.equipment.pending[itemID] then mark("equipment") end
end
Events.On("ITEM_DATA_LOAD_RESULT", "items", itemArrived)
Events.On("GET_ITEM_INFO_RECEIVED", "items", itemArrived)
-- talents
local function talentsChanged()
  Cache.Invalidate("talents")
  mark("talents", "stats")
end
for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do
  Events.On(e, "talents", talentsChanged)
end
Events.On("SPELLS_CHANGED", "spells", function() mark("spells") end)
-- a weapon imbue put on or worn off (Windfury...): the equipment's temporary enchants and abilities
Events.On("WEAPON_ENCHANT_CHANGED", "imbue", function() mark("equipment", "stats") end)
Events.On("UNIT_INVENTORY_CHANGED", "imbue", playerOnly(function() mark("equipment") end))
-- the character sheet
for _, e in ipairs({ "UNIT_STATS", "UNIT_RESISTANCES", "UNIT_ATTACK_POWER", "UNIT_MAXHEALTH" }) do
  Events.On(e, "stats", playerOnly(function() mark("stats") end))
end
for _, e in ipairs({ "COMBAT_RATING_UPDATE", "PLAYER_DAMAGE_DONE_MODS" }) do
  Events.On(e, "stats", function() mark("stats") end)
end
Events.On("UNIT_AURA", "buffs", playerOnly(function() mark("buffs", "stats") end))
-- combat ended: catch up on whatever changed during it
Events.On("PLAYER_REGEN_ENABLED", "scan", function()
  if CharacterScanner.waitingForCombat then mark("stats", "buffs") end
end)
