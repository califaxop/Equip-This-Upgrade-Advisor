-- Equip This!: which gear is better for you. Shared namespace, settings, helpers.
-- (5.0: the evaluation is the engine in Engine/ (ns.Engine); Bridge.lua connects it to the tooltip,
-- quest rewards and settings.)
local ADDON, ns = ...
ns.name = ADDON

ns.isSecret = issecretvalue or function() return false end
function ns.Readable(v) return v ~= nil and not ns.isSecret(v) end
function ns.Print(...) print("|cff7fd6ffEquip This!:|r", ...) end

ns.DEFAULTS = {
  spec = "auto",          -- "auto" (from your talents) or a talent tree's name ("Enhancement")
  tooltip = true,         -- the "Equip This!: Upgrade +12%" line on item tooltips
  rewards = true,         -- glow the best quest reward
  sellFallback = true,    -- no upgrade among the rewards: mark the one that sells for most
  bestArmorOnly = false,  -- from level 40, only mail (shamans, hunters) or plate (warriors, paladins) can be upgrades
  pvp = false,            -- a PvP line on tooltips too (burst, sustained, survival vs players)
  fightLength = 180,      -- seconds a fight lasts, for mana
  raids = {},             -- per character: the raid its level-cap EHP is for ("mc", "bwl", "aq40"; none: Naxxramas)
  builds = {},            -- per spec ("CLASS:Tree"): { build = "auto" | "damage" | ..., survival = 0-1, tank = true }
}

local function Copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = Copy(x) end
  return t
end
ns.Copy = Copy

-- this character, for settings kept per character ("Name-Realm")
function ns.CharKey()
  local name = UnitName and UnitName("player") or "?"
  local realm = GetRealmName and GetRealmName() or ""
  return format("%s-%s", tostring(name), tostring(realm))
end

function ns.LoadDB()
  EquipThisDB = EquipThisDB or {}
  for k, v in pairs(ns.DEFAULTS) do
    if EquipThisDB[k] == nil then EquipThisDB[k] = Copy(v) end
  end
  ns.db = EquipThisDB
  -- (5.0: the old scoring's settings are gone: Forever Upgrades' values, stat priorities)
  for _, k in ipairs({ "priorities", "skills", "scaleSkills", "model", "learn", "learned", "learnSeen", "split",
    "weights", "scales", "scale", "importanceV", "form" }) do ns.db[k] = nil end
  -- (4.x spec keys were "SHAMAN:2": back to Auto)
  if type(ns.db.spec) == "string" and ns.db.spec:find(":%d$") then ns.db.spec = "auto" end
end

function ns.Class()
  local _, token = UnitClass("player")
  return token
end
