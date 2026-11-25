-- Bridge (5.0): Equip This!'s settings, tooltip and quest rewards on top of the engine (ns.Engine).
-- The engine evaluates each item as complete setups (both ring slots, weapon pairs, set bonuses,
-- enchants, procs) and gives each metric apart: damage (DPS), healing (HPS), threat (tanks),
-- effective health (EHP), and PvP. The verdict on the tooltip ("Upgrade +4.4%") mixes them the way
-- your build says (the slider: damage or healing <-> survivability); the numbers stay apart under it.
local _, ns = ...
local B = {}
ns.Bridge = B
local function E() return ns.Engine end

-- talent trees per class (as Forever names them)
B.TREES = {
  WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
  HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
  PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
  MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
  DRUID = { "Balance", "Feral Combat", "Restoration" },
}

---------------------------------------------------------------------------
-- Your spec and build
---------------------------------------------------------------------------
-- the tree in use: your setting, or the one your talents have most points in
function B.Tree()
  if ns.db.spec and ns.db.spec ~= "auto" then return ns.db.spec end
  local p = E() and E().profile
  return p and p.talents and p.talents.primaryTree or nil
end
function B.SpecKey() return tostring(ns.Class()) .. ":" .. tostring(B.Tree()) end

function B.MaxLevel()
  local cap = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or (GetMaxPlayerLevel and GetMaxPlayerLevel())
  return (type(cap) == "number" and cap > 0) and cap or 60
end
local function level() return (UnitLevel and UnitLevel("player")) or 1 end

-- { id, name, survival share (non-tanks), survival share (tanks), description }
B.BUILDS = {
  { "auto", "Auto", nil, nil, "Leveling until the level cap, then Damage (tanks: Tanking). Switches by itself." },
  { "damage", "Damage", 0, 0, "All damage (or healing; tanks: threat)." },
  { "leveling", "Leveling", 0.25, 0.5, "Mostly damage, a quarter survivability: easier fights while you level. Tanks: half and half." },
  { "balanced", "Balanced", 0.5, 0.75, "Half damage, half survivability." },
  { "survival", "Survival", 1, 1, "All survivability (effective health). Tanks: Tanking." },
  { "custom", "Your mix", nil, nil, "Your own mix (the slider)." },
}
local BUILD = {}
for _, b in ipairs(B.BUILDS) do BUILD[b[1]] = b end

local function choice(key)
  ns.db.builds = ns.db.builds or {}
  return ns.db.builds[key or B.SpecKey()] or {}
end
local function save(c, key) ns.db.builds = ns.db.builds or {}; ns.db.builds[key or B.SpecKey()] = c end

function B.IsTankSpec() return B.Tree() == "Protection" end
function B.IsTank() return B.IsTankSpec() or choice().tank and true or false end
function B.SetTank(on) local c = ns.Copy(choice()); c.tank = on and true or nil; save(c) end
function B.BuildName(id)
  if id == "survival" and B.IsTank() then return "Tanking" end
  return BUILD[id] and BUILD[id][2] or id
end
-- the build in effect (Auto as Leveling / Damage / Tanking)
function B.Build()
  local b = choice().build or "auto"
  if b == "auto" then
    if level() < B.MaxLevel() then return "leveling", true end
    return B.IsTank() and "survival" or "damage", true
  end
  return b, false
end
function B.SetBuild(id)
  local c = ns.Copy(choice())
  if id == "custom" and c.survival == nil then c.survival = B.Mix() end
  c.build = id
  save(c)
end
-- how much of your build is survivability, 0-1
function B.Mix()
  local b = B.Build()
  if b == "custom" then return math.max(0, math.min(1, choice().survival or 0)) end
  local e = BUILD[b]
  return e and ((B.IsTank() and e[4]) or e[3]) or 0
end
function B.SetMix(x) local c = ns.Copy(choice()); c.build = "custom"; c.survival = x; save(c) end
function B.ResetBuild() save(nil) end

function B.ScoringLabel()
  local b = B.Build()
  local label = tostring(B.Tree() or "your spec") .. ", " .. B.BuildName(b)
  if b == "custom" then label = label .. format(" (%d%% survival)", B.Mix() * 100 + 0.5) end
  if B.IsTank() and not B.IsTankSpec() then label = label .. " (tanking)" end
  return label
end
-- what the damage side of the mix is: "DPS", "HPS" or "Threat"
function B.MainMetric()
  local ctx = E() and E().Context and E().Context()
  if ctx and ctx.tank then return "tps", "Threat" end
  if ctx and ctx.healer then return "hps", "HPS" end
  return "dps", "DPS"
end

---------------------------------------------------------------------------
-- Raid at 60: how much of what hits you is magic (Warcraft Logs, 40-player Classic raids, recent
-- public kills of each boss; 4.3.0). While leveling the engine's 20% is used.
---------------------------------------------------------------------------
B.RAIDS = {
  mc = { name = "Molten Core", tank = 0.32, other = 0.76 },
  bwl = { name = "Blackwing Lair", tank = 0.32, other = 0.85 },
  aq40 = { name = "Temple of Ahn'Qiraj", tank = 0.17, other = 0.63 },
  naxx = { name = "Naxxramas", tank = 0.12, other = 0.69 },
}
B.RAID_ORDER = { "mc", "bwl", "aq40", "naxx" }
function B.Raid()
  local r = ns.db and ns.db.raids and ns.db.raids[ns.CharKey()]
  if r and B.RAIDS[r] then return r end
  return "naxx"
end
function B.SetRaid(r) ns.db.raids = ns.db.raids or {}; ns.db.raids[ns.CharKey()] = (r ~= "naxx") and r or nil end
function B.MagicShare()
  if level() < B.MaxLevel() then return nil end
  local r = B.RAIDS[B.Raid()]
  return B.IsTank() and r.tank or r.other
end

-- Equip This!'s settings into the engine's, and start over (call after any change)
function B.Sync()
  local Eng = E()
  if not (Eng and Eng.db) then return end
  local db = Eng.db
  db.tree = ns.db.spec or "auto"
  db.pvp = ns.db.pvp and true or false
  db.fightLength = ns.db.fightLength or 180
  db.role = B.IsTank() and "tank" or "auto"
  db.magicShare = B.MagicShare()
  Eng.evalContext = nil
  if Eng.Cache then Eng.Cache.Invalidate("evaluation") end
end

---------------------------------------------------------------------------
-- An item: the engine's comparison, as the tooltip and the quest rewards use it
--   { kind = "upgrade" | "downgrade" | "same" | "new" | "equipped" | "unusable" | "unique" | "twohand" | "armortype",
--     pct (the mix), metrics = { dps, hps, tps, ehp }, vs (link), partner (link), hand, enchant, parts,
--     unread (effects not counted), notes, pvp, confidence, reasons }
---------------------------------------------------------------------------
local BEST_ARMOR = { SHAMAN = 3, HUNTER = 3, WARRIOR = 4, PALADIN = 4 }   -- (armor subclass: 1 cloth ... 4 plate)
local ARMOR_NAME = { [3] = "mail", [4] = "plate" }

function B.StatName(k)
  if k == "WEAPON" then return "Weapon" elseif k == "EFFECTS" then return "Effects" end
  local n = E() and E().StatDefs and E().StatDefs.NAMES[k]
  return n or k
end

function B.Item(link)
  local Eng = E()
  if not (Eng and Eng.EquipmentScanner) then return nil end
  local ok, it = pcall(Eng.EquipmentScanner.ReadItem, link)
  return ok and it or nil
end

function B.Facts(link)
  local it = B.Item(link)
  if not (it and it.loaded) then return nil end
  return { sell = it.sellPrice or 0, usable = it.canUse ~= false, equipLoc = it.equipLoc }
end

function B.Compare(link)
  local Eng = E()
  if not (Eng and Eng.Tooltip and Eng.Context and Eng.Context()) then return nil end
  local ok, res = pcall(Eng.Tooltip.Evaluate, link)
  if not ok or type(res) ~= "table" then return nil end
  local st = res.status
  local item = B.Item(link)
  if st == "loading" or st == "unknown" then return nil end
  if st == "cantuse" then return { kind = "unusable" } end
  if st == "equipped" then return { kind = "equipped", equipLoc = item and item.equipLoc } end
  if st == "unique" then return { kind = "unique" } end
  if st == "none" then return { kind = "twohand", why = res.why } end
  local b = res.best
  if not b then return nil end
  -- your best armor type only (setting, from level 40)
  local class = ns.Class()
  if ns.db.bestArmorOnly and level() >= 40 and item and item.classID == 4 and BEST_ARMOR[class]
    and item.subclassID and item.subclassID >= 1 and item.subclassID < BEST_ARMOR[class] and item.equipLoc ~= "INVTYPE_CLOAK" then
    return { kind = "armortype", best = ARMOR_NAME[BEST_ARMOR[class]] }
  end
  local t = B.Mix()
  local key = B.MainMetric()
  local function mix(x)
    local main, ehp = x[key], x.ehp
    if main and ehp then return (1 - t) * main + t * ehp end
    return main or ehp
  end
  local c = { pct = mix(b) or 0, metrics = { dps = b.dps, hps = b.hps, tps = b.tps, ehp = b.ehp }, pvp = b.pvp,
    notes = b.notes, confidence = res.confidence, reasons = res.reasons, equipLoc = item and item.equipLoc,
    hand = b.slot == 17 and "oh" or nil, parts = {} }
  for _, p in ipairs(b.parts or {}) do
    local v = mix(p)
    if v then c.parts[p.stat] = (c.parts[p.stat] or 0) + v end
  end
  if #(b.removed or {}) == 0 then c.kind = "new"
  elseif math.abs(c.pct) < 0.1 then c.kind = "same"
  else c.kind = c.pct > 0 and "upgrade" or "downgrade" end
  c.vs = b.removed and b.removed[1] and b.removed[1].link
  for _, a in ipairs(b.added or {}) do
    if a.link and a.link ~= link and a ~= item then c.partner = a.link end
  end
  if b.carry and b.carry[1] then c.enchant = tostring(b.carry[1]):gsub("^Enchanted: ", "") end
  if item and item.effects and #item.effects > 0 then c.unread = table.concat(item.effects, " | ") end
  return c
end
