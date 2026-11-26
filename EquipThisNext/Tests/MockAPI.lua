-- MockAPI: a small stand-in for the game's API, shaped like Forever build 71091's documented API,
-- so the addon loads and scans outside the game. Knobs (MOCK.*) let tests switch on hidden stats,
-- hidden auras, late-loading items, missing functions and API errors.
MOCK = {
  inCombat = false, statsSecret = false, aurasSecret = false,
  cached = {},           -- itemID -> true when the client "has" the item's data
  requested = {},        -- itemID -> times requested
  now = 1000,
}
local SECRET_VALUE = setmetatable({}, { __tostring = function() return "<secret>" end })
MOCK.SECRET_VALUE = SECRET_VALUE
function issecretvalue(v) return v == SECRET_VALUE end
function issecrettable(v) return v == SECRET_VALUE end

local function s(v) if MOCK.statsSecret then return SECRET_VALUE end return v end

-- frames and events
local frames = {}
function CreateFrame()
  local f = { events = {}, scripts = {} }
  function f:RegisterEvent(e)
    if MOCK.unknownEvents and MOCK.unknownEvents[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
    self.events[e] = true
  end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  frames[#frames + 1] = f
  return f
end
function MOCK.Fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
MOCK.clock = 1000 -- (GetTime; MOCK.now is the clock time() reads)
GetTime = function() return MOCK.clock end
-- a fight: combat starts, lasts as long as the meter's session (or `length`), and ends
function MOCK.Fight(length)
  MOCK.Fire("PLAYER_REGEN_DISABLED")
  MOCK.clock = MOCK.clock + (length or (MOCK.meter and MOCK.meter.duration) or 10) + 1
  MOCK.Fire("PLAYER_REGEN_ENABLED")
end
-- a fresh start for the next LoadAddon(): no old frames, timers or prints
function MOCK.Reset()
  for i = #frames, 1, -1 do frames[i] = nil end
  timers = {}
  PRINTS = {}
  MOCK.cached, MOCK.requested = {}, {}
  MOCK.inCombat, MOCK.statsSecret, MOCK.aurasSecret, MOCK.noTalents, MOCK.windfury = false, false, false, nil, nil
  MOCK.meter = nil
  EquipThisNextDB = nil
end
function MOCK.RunTimers()
  local list = timers
  timers = {}
  for _, fn in ipairs(list) do fn() end
end
function time(t) if t then return os.time(t) end return MOCK.now end
date = os.date   -- (WoW has date())
PRINTS = {}
function print(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  PRINTS[#PRINTS + 1] = table.concat(t, " ")
end
SlashCmdList = {}

-- identity
function UnitName() return "Thrall" end
function GetRealmName() return "Forever" end
function UnitGUID() return "Player-1-0001" end
function UnitClass() return "Shaman", "SHAMAN", 7 end
function UnitRace() return "Orc", "Orc", 2 end
function UnitLevel() return MOCK.level or 42 end
function UnitEffectiveLevel() return MOCK.level or 42 end
function UnitSex() return 2 end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.60.1", "71091", "Nov 24 2026", 16001, "", "" end
function UnitAffectingCombat() return MOCK.inCombat end
function InCombatLockdown() return MOCK.inCombat end
C_SpecializationInfo = { GetSpecialization = function() return 2 end }
C_Secrets = {
  ShouldUnitStatsBeSecret = function() return MOCK.statsSecret end,
  ShouldAurasBeSecret = function() return MOCK.aurasSecret end,
}

-- stats
local STATS = { { 80, 95 }, { 60, 72 }, { 70, 140 }, { 90, 110 }, { 85, 100 } }
function UnitStat(_, i) local t = STATS[i]; return s(t[1]), s(t[2]), s(t[2] - t[1]), s(0) end
function UnitArmor() return s(1800), s(2100), s(2100), s(300) end
function UnitAttackPower() return s(320), s(40), s(0) end
function UnitRangedAttackPower() return s(60), s(0), s(0) end
function UnitDamage() local avg = (38.47 + 360 / 14) * 3.6 + 5; return s(avg - 20), s(avg + 20), s(0), s(0), s(0), s(0), s(1) end
function UnitRangedDamage() return s(0), s(0), s(0), s(0), s(0), s(1) end
function UnitAttackSpeed() return s(3.6), nil, nil end
function UnitHealthMax() return s(2400) end
function UnitPowerType() return 0, "MANA" end
function UnitDefenseSkill() return s(210), s(0) end
function UnitResistance(_, i) return s(0), s(i == 3 and 15 or 0), s(i == 3 and 15 or 0), s(i == 3 and 15 or 0) end
function UnitSpellHaste() return s(0) end
function UnitHPPerStamina() return s(10) end
function GetCritChance() return s(6.2) end
function GetRangedCritChance() return s(4.1) end
function GetSpellCritChance() return s(5.5) end
function GetHitModifier() return s(1) end
function GetRangedHitModifier() return s(0) end
function GetOffhandHitModifier() return s(1) end
function GetSpellHitModifier() return s(0) end
function GetCombatRating(i) return s(0) end
function GetCombatRatingBonus(i) return s(i == CR_HIT_MELEE and 2 or 0) end
function GetExpertise() return s(0), s(0), s(0) end
function GetHaste() return s(0) end
function GetMeleeHaste() return s(0) end
function GetRangedHaste() return s(0) end
function GetSpellBonusDamage(school) return s(school == 4 and 25 or 10) end
function GetSpellBonusHealing() return s(30) end
function GetManaRegen() return s(4.5), s(0) end
function GetSpellPenetration() return s(0) end
function GetArmorPenetration() return s(0) end
function GetDodgeChance() return s(4.8) end
function GetParryChance() return s(5) end
function GetBlockChance() return s(0) end
function GetShieldBlock() return s(0) end
function GetGlancingBlowChance() return s(10) end
function GetCritChanceFromStat(i, v) return s(i == 2 and v / 20 / 100 or 0) end
function GetSpellCritChanceFromStat(i, v) return s(i == 4 and v / 59.5 / 100 or 0) end
function GetAttackPowerForStat(i, v) return s(i == 1 and v * 2 or 0) end
function GetRangedAttackPowerForStat(i, v) return s(0) end
function GetDodgeChanceFromAttribute() return s(0.036) end
function GetManaRegenFromSpirit() return s(2.1) end
function GetHealthRegenFromSpirit() return s(1.4) end
CR_WEAPON_SKILL, CR_DEFENSE_SKILL, CR_DODGE, CR_PARRY, CR_BLOCK, CR_HIT_MELEE, CR_HIT_RANGED, CR_HIT_SPELL = 1, 2, 3, 4, 5, 6, 7, 8
CR_CRIT_MELEE, CR_CRIT_RANGED, CR_CRIT_SPELL, CR_HASTE_MELEE, CR_HASTE_RANGED, CR_HASTE_SPELL, CR_EXPERTISE = 9, 10, 11, 18, 19, 20, 24
-- (CR_ARMOR_PENETRATION left undefined on purpose: the scanner must report it, not crash)
function CanDualWield() return false end
Enum = {
  ItemWeaponSubclass = { Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5, Polearm = 6, Sword1H = 7,
    Sword2H = 8, Staff = 10, Unarmed = 13, Generic = 14, Dagger = 15, Thrown = 16, Crossbow = 18, Wand = 19 },
  SpellBookSpellBank = { Player = 0, Pet = 1 },
}
C_SkillInfo = { GetSkillLineInfoByID = function(id)
  if id == 172 then return { name = "Two-Handed Axes", rank = 205, modifier = 0, maxRank = 210 } end
  if id == 43 then return { name = "Swords", rank = 190, modifier = 0, maxRank = 210 } end
end }

-- items: itemID -> { name, equipLoc, classID, subclassID, quality, ilvl, setID, stats }
MOCK.ITEMS = {
  [1001] = { "Helm of the Test", "INVTYPE_HEAD", 4, 3, 2, 40, nil, { ITEM_MOD_STAMINA_SHORT = 12, ITEM_MOD_INTELLECT_SHORT = 8, RESISTANCE0_NAME = 220 } },
  [1002] = { "Axe of Testing", "INVTYPE_2HWEAPON", 2, 1, 3, 42, nil, { ITEM_MOD_STRENGTH_SHORT = 15, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 38.47 } },
  [1003] = { "Ring of Sets", "INVTYPE_FINGER", 4, 0, 3, 45, 77, { ITEM_MOD_AGILITY_SHORT = 6 } },
  [1004] = { "Band of Sets", "INVTYPE_FINGER", 4, 0, 3, 45, 77, { ITEM_MOD_AGILITY_SHORT = 5 } },
  [1005] = { "Totem of Testing", "INVTYPE_RELIC", 4, 9, 2, 40, nil, {} },
  [1010] = { "Blade of Bags", "INVTYPE_WEAPON", 2, 7, 3, 42, nil, { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 26 } },
  [1011] = { "Shield of Bags", "INVTYPE_SHIELD", 4, 6, 3, 42, nil, { RESISTANCE0_NAME = 900, ITEM_MOD_STAMINA_SHORT = 6 } },
}
MOCK.WORN = {
  [1] = "|cff1eff00|Hitem:1001:0:0:0:0:0:0:0:42|h[Helm of the Test]|h|r",
  [16] = "|cff0070dd|Hitem:1002:1897:0:0:0:0:0:0:42|h[Axe of Testing]|h|r",
  [11] = "|cff0070dd|Hitem:1003::::::::42|h[Ring of Sets]|h|r",
  [12] = "|cff0070dd|Hitem:1004::::::::42|h[Band of Sets]|h|r",
  [18] = "|cff1eff00|Hitem:1005::::::::42|h[Totem of Testing]|h|r",
}
local function idOf(x)
  if type(x) == "number" then return x end
  return tonumber(tostring(x):match("item:(%d+)"))
end
local SLOT_KEYS = { HEADSLOT = 1, NECKSLOT = 2, SHOULDERSLOT = 3, BACKSLOT = 15, CHESTSLOT = 5, WRISTSLOT = 9, HANDSSLOT = 10,
  WAISTSLOT = 6, LEGSSLOT = 7, FEETSLOT = 8, FINGER0SLOT = 11, FINGER1SLOT = 12, TRINKET0SLOT = 13, TRINKET1SLOT = 14,
  MAINHANDSLOT = 16, SECONDARYHANDSLOT = 17, RANGEDSLOT = 18 }
function GetInventorySlotInfo(key) local id = SLOT_KEYS[key]; if not id then error("Invalid inventory slot") end return id end
function GetInventoryItemLink(_, slot) return MOCK.WORN[slot] end
function GetInventoryItemID(_, slot) return idOf(MOCK.WORN[slot]) end
C_Item = {
  GetItemInfoInstant = function(x)
    local id = idOf(x); local it = MOCK.ITEMS[id]
    if not it then return nil end
    return id, "Armor", "Misc", it[2], 134400, it[3], it[4]
  end,
  IsItemDataCachedByID = function(x) return MOCK.cached[idOf(x)] == true end,
  RequestLoadItemDataByID = function(x) local id = idOf(x); MOCK.requested[id] = (MOCK.requested[id] or 0) + 1 end,
  GetItemInfo = function(x)
    local id = idOf(x); local it = MOCK.ITEMS[id]
    if not it or not MOCK.cached[id] then return nil end
    return it[1], "link", it[5], it[6], 30, "Armor", "Misc", 1, it[2], 134400, 1234, it[3], it[4], 1, 0, it[7], false, ""
  end,
  GetItemStats = function(link)
    local id = idOf(link); local it = MOCK.ITEMS[id]
    if not it then return {} end
    local t = {} for k, v in pairs(it[8]) do t[k] = v end
    return t
  end,
  GetItemNumSockets = function() return 0 end,
  GetItemSetInfo = function(setID) if setID == 77 then return "The Testing Rings" end end,
  GetItemSpell = function() return nil end,
  GetWeaponEnchantInfo = function(ws) if ws == 0 and MOCK.windfury then return { { enchantID = 283, timeLeft = 1700000, charges = 0, enchantType = 1 } } end return {} end,
}
C_PlayerInfo = { CanUseItem = function() return true end }

-- talents: one config, one tree, three groups (Elemental, Enhancement, Restoration)
MOCK.TALENTS = {
  -- (as in game: some nodes list their tree's group, others only a row group; trees side by side in x)
  { node = 501, group = 11650, x = 1600, def = 9001, spell = 16039, name = "Convection", rank = 0, max = 5 },
  { node = 502, group = 11657, x = 6200, def = 9002, spell = 16262, name = "Ancestral Knowledge", rank = 5, max = 5 },
  { node = 503, group = 11657, groups = { 40001 }, x = 5600, def = 9003, spell = 16253, name = "Flurry", rank = 3, max = 5 },
  { node = 504, group = 11670, x = 10200, def = 9004, spell = 16173, name = "Tidal Focus", rank = 1, max = 5 },
}
C_ClassTalents = { GetActiveConfigID = function() if MOCK.noTalents then return nil end return 77 end }
C_Traits = {
  GetConfigInfo = function(id) if id == 77 then return { ID = 77, type = 1, name = "Talents", treeIDs = { 1117 } } end end,
  GetTreeNodes = function(tree) local t = {} for _, n in ipairs(MOCK.TALENTS) do t[#t + 1] = n.node end return t end,
  GetNodeInfo = function(_, nodeID)
    for _, n in ipairs(MOCK.TALENTS) do
      if n.node == nodeID then
        return { ID = nodeID, posX = n.x or 0, posY = 0, entryIDs = { nodeID * 10 }, activeEntry = n.rank > 0 and { entryID = nodeID * 10, rank = n.rank } or nil,
          currentRank = n.rank, ranksPurchased = n.rank, maxRanks = n.max, groupIDs = n.groups or { n.group } }
      end
    end
  end,
  GetEntryInfo = function(_, entryID) for _, n in ipairs(MOCK.TALENTS) do if n.node * 10 == entryID then return { definitionID = n.def, maxRanks = n.max } end end end,
  GetDefinitionInfo = function(def) for _, n in ipairs(MOCK.TALENTS) do if n.def == def then return { spellID = n.spell } end end end,
  GetGroupCurrencyInfo = function(_, ids)
    local out = {}
    for _, gid in ipairs(ids) do
      local n = 0
      for _, t in ipairs(MOCK.TALENTS) do if t.group == gid then n = n + t.rank end end
      if n > 0 then out[#out + 1] = { traitNodeGroupID = gid, currencyInfos = { { traitCurrencyID = 3820, spent = n } } } end
    end
    return out
  end,
  GetGroupDisplayInfoByTreeID = function() return {
    { groupID = 11657, displayName = "Enhancement", orderIndex = 1 }, { groupID = 11650, displayName = "Elemental", orderIndex = 0 },
    { groupID = 11670, displayName = "Restoration", orderIndex = 2 } } end,
}
local SPELLS = { [6603] = "Auto Attack", [8232] = "Windfury Weapon", [439440] = "Windfury Attack", [8134] = "Lightning Shield", [16039] = "Convection", [16262] = "Ancestral Knowledge", [16253] = "Flurry", [16173] = "Tidal Focus", [403] = "Lightning Bolt", [17364] = "Stormstrike" }
C_Spell = { GetSpellName = function(id) return SPELLS[id] end }
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 2 end,
  GetSpellBookSkillLineInfo = function(i)
    if i == 1 then return { name = "General", itemIndexOffset = 0, numSpellBookItems = 1 } end
    return { name = "Enhancement", itemIndexOffset = 1, numSpellBookItems = 3 }
  end,
  GetSpellBookItemInfo = function(i)
    local list = { { 6603, "Attack" }, { 403, "Lightning Bolt", "Rank 4" }, { 17364, "Stormstrike" }, { 8232, "Windfury Weapon", "Rank 1" } }
    local e = list[i]
    if e then return { spellID = e[1], name = e[2], subName = e[3] or "", isPassive = false } end
  end,
}
-- auras
MOCK.BUFFS = { { name = "Lightning Shield", spellId = 8134, applications = 3, isFromPlayerOrPlayerPet = true } }
C_UnitAuras = {
  GetAuraDataByIndex = function(unit, i, filter)
    if MOCK.aurasSecret then error("Auras cannot be accessed when secret") end
    if filter == "HELPFUL" then return MOCK.BUFFS[i] end
    return nil
  end,
}

-- milestone 2: the game's calculators, tooltip text, the tooltip pipeline
MOCK.RATING_PER_PCT = { [CR_CRIT_MELEE] = 14, [CR_CRIT_RANGED] = 14, [CR_CRIT_SPELL] = 14, [CR_HIT_MELEE] = 10, [CR_HIT_SPELL] = 10,
  [CR_HIT_RANGED] = 10, [CR_HASTE_MELEE] = 10, [CR_HASTE_SPELL] = 10, [CR_HASTE_RANGED] = 10, [CR_DODGE] = 12, [CR_PARRY] = 15,
  [CR_BLOCK] = 5, [CR_EXPERTISE] = 10, [CR_DEFENSE_SKILL] = 1.5 }
function GetCombatRatingBonusForCombatRatingValue(idx, value)
  if MOCK.statsSecret then return SECRET_VALUE end
  local per = MOCK.RATING_PER_PCT[idx]
  return per and value / per or 0
end
C_PaperDollInfo = { GetArmorEffectiveness = function(armor, level) return s(armor / (armor + 400 + 85 * level)) end }
function GetGlancingBlowChance(skill, def) if skill == nil then error("Usage: GetGlancingBlowChance([playerWeaponSkill], targetDefenseSkill)") end return s(0.10 + math.max(0, def - skill) * 0.02) end
function GetGlancingBlowPenalty(skill, def) return s(0.05) end
C_Spell.GetSpellDescription = function(id)
  if id == 16253 then return "Increases your attack speed by 20% for your next 3 swing attacks after dealing a critical strike." end
  if id == 17364 then return "Instantly strike for 100% weapon damage and increase the damage you deal to the target with your next Lightning Bolt, Chain Lightning, or Earth Shock spell by 20% for 12 sec." end
  if id == 8232 then return "Imbue the Shaman's weapon with wind.  Each hit has a 20% chance of granting you 1 extra attack with 104 extra melee attack power. Lasts for 60 minutes." end
end
MOCK.SPELL_TOOLTIP = { [17364] = { { "Stormstrike" }, { "Instant", "8 sec cooldown" } } }
-- the game's damage meter (milestone 4): MOCK.meter = { duration, spells = { [id] = amount } }
C_DamageMeter = {
  IsDamageMeterAvailable = function() return true, "" end,
  GetAvailableCombatSessions = function() return MOCK.meter and { { sessionID = MOCK.meter.id or 7, name = "Target Dummy", durationSeconds = MOCK.meter.duration } } or {} end,
  GetSessionDurationSeconds = function(t) return MOCK.meter and MOCK.meter.duration end,
  ResetAllCombatSessions = function() MOCK.meter = nil end,
  GetCombatSessionSourceFromType = function(t, kind, guid) return C_DamageMeter.GetCombatSessionSourceFromID(t, kind, guid) end,
  GetCombatSessionSourceFromID = function(id, kind, guid)
    if MOCK.inCombat then return { combatSpells = { { spellID = 1, totalAmount = SECRET_VALUE } } } end
    local list = {}
    local src = kind == 2 and (MOCK.meter and MOCK.meter.heal) or (kind ~= 2 and MOCK.meter and MOCK.meter.spells) or {}
    for sid, a in pairs(src) do list[#list + 1] = { spellID = sid, totalAmount = a } end
    return { combatSpells = list, totalAmount = 0 }
  end,
}
MOCK.TOOLTIP_LINES = {
  -- a line is text, or { left, right }
  [1002] = { "Axe of Testing", { "Two-Hand", "Axe" }, { "120 - 157 Damage", "Speed 3.60" }, "+15 Strength" },
  [1010] = { "Blade of Bags", { "One-Hand", "Sword" }, { "50 - 80 Damage", "Speed 2.50" }, "+5 Strength" },
  [1011] = { "Shield of Bags", { "Off Hand", "Shield" }, "900 Armor", "18 Block", "+6 Stamina" },
  [1003] = { "Ring of Sets", "Equip: +6 Agility", "(2) Set: +10 Attack Power.", "(3) Set: Chance on hit: zaps the target." },
  [1004] = { "Band of Sets", "(2) Set: +10 Attack Power.", "(3) Set: Chance on hit: zaps the target." },
  [1008] = { "Ring of Procs", "Chance on hit: Wounds the target for 50 damage.", "Equip: Improves your chance to get a critical strike by 1%." },
}
C_TooltipInfo = { GetSpellByID = function(id)
  local lines = {}
  for _, t in ipairs(MOCK.SPELL_TOOLTIP[id] or {}) do lines[#lines + 1] = { leftText = t[1], rightText = t[2] } end
  return { lines = lines }
end, GetHyperlink = function(link)
  local id, ench = tostring(link):match("item:(%d+):(%d*)")
  id = tonumber(id)
  local lines = {}
  for _, t in ipairs(MOCK.TOOLTIP_LINES[id] or {}) do
    if type(t) == "table" then lines[#lines + 1] = { leftText = t[1], rightText = t[2] } else lines[#lines + 1] = { leftText = t } end
  end
  if tonumber(ench) and tonumber(ench) > 0 then lines[#lines + 1] = { leftText = "Enchanted: +5 Weapon Damage" } end
  return { lines = lines }
end }
C_Item.GetItemUniquenessByID = function() return false end
MOCK.BAGS = {}
C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
  GetContainerItemLink = function(bag, slot) return bag == 0 and MOCK.BAGS[slot] or nil end,
}
Enum.TooltipDataType = { Item = 0 }
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) MOCK.tooltipHook = fn end }
function MOCK.MakeTooltip(link)
  local tt = { lines = {} }
  function tt:GetItem() return "name", link end
  function tt:AddLine(t) self.lines[#self.lines + 1] = t end
  return tt
end

-- milestone 6: profiling and memory
local profileClock = 0
function debugprofilestop() profileClock = profileClock + 0.25; return profileClock end
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage(name) return 512 end
