-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- TalentAPI: Forever's talents live in Retail's trait system. The active config holds one tree
-- with the class's three Classic talent trees as node groups (C_Traits.GetGroupDisplayInfoByTreeID
-- names them and gives their order). Thin wrappers only; Scanner/TalentScanner reads them.
local _, ns = ...; ns = ns.Engine
local Talent = ns.Module("TalentAPI")
local Compat = ns.Compat

function Talent.ActiveConfigID() return Compat.Value("C_ClassTalents.GetActiveConfigID") end

function Talent.ConfigInfo(configID)
  local ok, info = Compat.Call("C_Traits.GetConfigInfo", configID)
  if not ok or type(info) ~= "table" then return nil end
  return info
end

function Talent.TreeNodes(treeID)
  local ok, nodes = Compat.Call("C_Traits.GetTreeNodes", treeID)
  if not ok or type(nodes) ~= "table" then return {} end
  return nodes
end

function Talent.NodeInfo(configID, nodeID)
  local ok, info = Compat.Call("C_Traits.GetNodeInfo", configID, nodeID)
  if not ok or type(info) ~= "table" then return nil end
  return info
end

function Talent.EntryInfo(configID, entryID)
  local ok, info = Compat.Call("C_Traits.GetEntryInfo", configID, entryID)
  if not ok or type(info) ~= "table" then return nil end
  return info
end

function Talent.DefinitionInfo(definitionID)
  local ok, info = Compat.Call("C_Traits.GetDefinitionInfo", definitionID)
  if not ok or type(info) ~= "table" then return nil end
  return info
end

-- Points the game says were spent per group: { [groupID] = points } (shape as the released Equip This!
-- reads it: { { traitNodeGroupID, currencyInfos = { { spent } } } }), or nil.
function Talent.SpentByGroup(configID, groupIDs)
  local ok, list = Compat.Call("C_Traits.GetGroupCurrencyInfo", configID, groupIDs)
  if not ok or type(list) ~= "table" then return nil end
  local out = {}
  for _, c in ipairs(list) do
    local gid = Compat.Field(c, "traitNodeGroupID")
    local infos = Compat.Field(c, "currencyInfos")
    if gid then
      local n = 0
      for _, ci in ipairs(type(infos) == "table" and infos or {}) do
        local s = Compat.Field(ci, "spent")
        if type(s) == "number" then n = n + s end
      end
      out[gid] = n
    end
  end
  return out
end

-- { { groupID, displayName, orderIndex } } for the tree, or {} (unverified shape: see DEVELOPMENT.md)
function Talent.Groups(treeID)
  local ok, groups = Compat.Call("C_Traits.GetGroupDisplayInfoByTreeID", treeID)
  if not ok or type(groups) ~= "table" then return {} end
  return groups
end
