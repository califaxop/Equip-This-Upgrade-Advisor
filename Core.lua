-- Gearwise: which gear is better for you. Shared namespace, settings, class and spec.
local ADDON, ns = ...
ns.name = ADDON

ns.isSecret = issecretvalue or function() return false end
function ns.Readable(v) return v ~= nil and not ns.isSecret(v) end
function ns.Print(...) print("|cff7fd6ffGearwise:|r", ...) end

ns.DEFAULTS = {
  spec = "auto",          -- "auto" (from your talents) or a spec key like "SHAMAN:2"
  tooltip = true,         -- the "Gearwise: Upgrade +12%" line on item tooltips
  rewards = true,         -- glow the best quest reward
  sellFallback = true,    -- no upgrade among the rewards: mark the one that sells for most
  weights = {},           -- your edits: [specKey] = { STAT = weight, ... } (unset = preset)
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
  GearwiseDB = GearwiseDB or {}
  for k, v in pairs(ns.DEFAULTS) do
    if GearwiseDB[k] == nil then GearwiseDB[k] = Copy(v) end
  end
  ns.db = GearwiseDB
end

---------------------------------------------------------------------------
-- Class and spec
---------------------------------------------------------------------------
function ns.Class()
  local _, token = UnitClass("player")
  return token
end

-- the talent tree with the most points (1-3), or nil before any talents
function ns.TalentTree()
  local best, bestPts
  if GetNumTalentTabs and GetTalentTabInfo then
    for i = 1, (GetNumTalentTabs() or 0) do
      local r = { pcall(GetTalentTabInfo, i) }
      if r[1] then
        -- older clients: name, icon, pointsSpent...; newer: id, name, description, icon, pointsSpent...
        local pts = (type(r[2]) == "number") and r[6] or r[4]
        if type(pts) == "number" and (not bestPts or pts > bestPts) then best, bestPts = i, pts end
      end
    end
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
