-- Equip This!: which gear is better for you. Shared namespace, settings, class and spec.
local ADDON, ns = ...
ns.name = ADDON

ns.isSecret = issecretvalue or function() return false end
function ns.Readable(v) return v ~= nil and not ns.isSecret(v) end
function ns.Print(...) print("|cff7fd6ffEquip This!:|r", ...) end
-- a spell's name from its ID (for a spell dragged onto a skill slot)
function ns.SpellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and ns.Readable(n) and n ~= "" then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" and ns.Readable(info.name) then return info.name end
  end
end

ns.DEFAULTS = {
  spec = "auto",          -- "auto" (from your talents) or a spec key like "SHAMAN:2"
  tooltip = true,         -- the "Equip This!: Upgrade +12%" line on item tooltips
  rewards = true,         -- glow the best quest reward
  sellFallback = true,    -- no upgrade among the rewards: mark the one that sells for most
  weights = {},           -- your edits: [specKey] = { STAT = weight, ... } (unset = preset)
  scales = {},            -- your own scales: [name] = { STAT = weight, ... }
  scale = nil,            -- the custom scale in use (nil = the spec preset)
  skills = {},            -- your skill list per spec: [specKey] = { { name, weight }, ... } (unset = the preset's)
  scaleSkills = {},       -- each custom scale's skill list: [scale name] = { { name, weight }, ... }
  flareStyle = true,
}

local function Copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = Copy(x) end
  return t
end
ns.Copy = Copy

function ns.LoadDB()
  EquipThisDB = EquipThisDB or {}
  for k, v in pairs(ns.DEFAULTS) do
    if EquipThisDB[k] == nil then EquipThisDB[k] = Copy(v) end
  end
  ns.db = EquipThisDB
  if not ns.db.importanceV then
    -- 2.1.0: weights became importance 0-5. Your preset edits use that spec preset's scaling;
    -- your own scales are rescaled so their top stat is 5. Scores come out the same.
    for key, edits in pairs(ns.db.weights or {}) do
      local _, f = ns.PresetImportance(key)
      for k, v in pairs(edits) do
        edits[k] = ns.NORM[k] and math.floor(v / ns.NORM[k] * f * 100 + 0.5) / 100 or nil
      end
    end
    for name, w in pairs(ns.db.scales or {}) do ns.db.scales[name] = (ns.ToImportance(w)) end
    ns.db.importanceV = 1
  end
end

---------------------------------------------------------------------------
-- Class and spec
---------------------------------------------------------------------------
function ns.Class()
  local _, token = UnitClass("player")
  return token
end

-- Points spent in each talent tab, as { [tree 1-3] = points }, or nil if the client won't say.
-- Forever has no GetTalentTabInfo: its talents are Retail's trait system, with the three tabs as
-- trait groups of one tree. (Found and checked in game by the Forever++ authors, docs/forever-api.md.)
local function PointsFromTraits(class)
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
    and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then return nil end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  if not (ok and type(configID) == "number" and not ns.isSecret(configID)) then return nil end
  local ok2, info = pcall(C_Traits.GetConfigInfo, configID)
  local treeID = ok2 and type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
  if type(treeID) ~= "number" then return nil end
  local ok3, groups = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
  if not (ok3 and type(groups) == "table" and #groups > 0) then return nil end
  local tabs = {}
  for _, g in ipairs(groups) do if type(g) == "table" and g.groupID then tabs[#tabs + 1] = g end end
  table.sort(tabs, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
  local ids = {}
  for i, g in ipairs(tabs) do ids[i] = g.groupID end
  local ok4, cur = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
  if not (ok4 and type(cur) == "table") then return nil end
  local spent = {}
  for _, c in ipairs(cur) do -- a tab with nothing spent is left out: it counts as 0
    local n = 0
    for _, ci in ipairs(c.currencyInfos or {}) do
      if type(ci.spent) == "number" and not ns.isSecret(ci.spent) then n = n + ci.spent end
    end
    if c.traitNodeGroupID then spent[c.traitNodeGroupID] = n end
  end
  -- each tab is the tree of ours with its name, else the one in its place (the game's order)
  local presets = ns.PRESETS and ns.PRESETS[class] or {}
  local points = {}
  for pos, g in ipairs(tabs) do
    local tree = pos
    for i, p in ipairs(presets) do if p[1] == g.displayName then tree = i end end
    points[tree] = (points[tree] or 0) + (spent[g.groupID] or 0)
  end
  return points
end

-- older clients: GetTalentTabInfo per tab
local function PointsFromTabs()
  if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
  local points = {}
  for i = 1, (GetNumTalentTabs() or 0) do
    local r = { pcall(GetTalentTabInfo, i) }
    if r[1] then
      -- older clients: name, icon, pointsSpent...; newer: id, name, description, icon, pointsSpent...
      local pts = (type(r[2]) == "number") and r[6] or r[4]
      if type(pts) == "number" then points[i] = pts end
    end
  end
  return points
end

function ns.TalentPoints()
  return PointsFromTraits(ns.Class()) or PointsFromTabs()
end

-- the talent tree with the most points (1-3), or nil before any talents
function ns.TalentTree()
  local best, bestPts
  for i, pts in pairs(ns.TalentPoints() or {}) do
    if not bestPts or pts > bestPts then best, bestPts = i, pts end
  end
  if bestPts and bestPts > 0 then return best end
  return nil
end

-- the spec in use: "CLASS:tree", from your setting or your talents (first tree before any)
function ns.SpecKey()
  local class = ns.Class()
  if ns.db.spec and ns.db.spec ~= "auto" and ns.db.spec:match("^" .. class .. ":") then return ns.db.spec end
  return class .. ":" .. (ns.TalentTree() or ns.DefaultTree(class))
end
