-- TalentScanner: the active talent configuration, raw (what each node is and its rank). It doesn't
-- interpret talents: what a talent does to stats or abilities belongs to the class profiles and the
-- talent interpreter (Milestone 2), so the two stay separate.
local _, ns = ...
local TalentScanner = ns.Module("TalentScanner")
local Talent, Spell, Compat, Cache = ns.TalentAPI, ns.SpellAPI, ns.Compat, ns.Cache

local function num(v) return type(v) == "number" and v or nil end

function TalentScanner.Scan(profile)
  local cached = Cache.Get("talents", "active")
  if cached then
    profile.talents = ns.Database.Copy(cached)
    return profile.talents
  end
  local t = { trees = {}, nodes = {}, readable = false }
  local configID = Talent.ActiveConfigID()
  t.configID = configID
  local config = configID and Talent.ConfigInfo(configID)
  local treeIDs = config and Compat.Field(config, "treeIDs")
  if type(treeIDs) ~= "table" then
    ns.CharacterProfile.AddIssue(profile, "warn", "talents-unreadable", "no active talent configuration (C_ClassTalents / C_Traits gave nothing)")
    profile.talents = t
    return t
  end
  for _, treeID in ipairs(treeIDs) do
    for _, g in ipairs(Talent.Groups(treeID)) do
      t.trees[#t.trees + 1] = { treeID = treeID, groupID = num(Compat.Field(g, "groupID")),
        name = Compat.Field(g, "displayName"), order = num(Compat.Field(g, "orderIndex")) }
    end
    for _, nodeID in ipairs(Talent.TreeNodes(treeID)) do
      local node = Talent.NodeInfo(configID, nodeID)
      if node then
        local active = Compat.Field(node, "activeEntry")
        local entryIDs = Compat.Field(node, "entryIDs")
        local entryID = (type(active) == "table" and num(active.entryID)) or (type(entryIDs) == "table" and num(entryIDs[1]))
        local entry = entryID and Talent.EntryInfo(configID, entryID)
        local defID = entry and num(Compat.Field(entry, "definitionID"))
        local def = defID and Talent.DefinitionInfo(defID)
        local spellID = def and num(Compat.Field(def, "spellID"))
        local name = def and Compat.Field(def, "overrideName")
        if (not name or name == "") and spellID then name = Spell.Name(spellID) end
        local groups = Compat.Field(node, "groupIDs")
        if name and name ~= "" then
          t.nodes[#t.nodes + 1] = {
            nodeID = nodeID, treeID = treeID, entryID = entryID, definitionID = defID, spellID = spellID, name = name,
            rank = num(Compat.Field(node, "currentRank")) or num(Compat.Field(node, "ranksPurchased")) or 0,
            maxRank = num(Compat.Field(node, "maxRanks")) or num(entry and Compat.Field(entry, "maxRanks")),
            groupID = type(groups) == "table" and num(groups[1]) or nil,
            posX = num(Compat.Field(node, "posX")), posY = num(Compat.Field(node, "posY")),
          }
        end
      end
    end
  end
  table.sort(t.trees, function(a, b) return (a.order or 99) < (b.order or 99) end)
  t.readable = #t.nodes > 0
  if not t.readable then
    ns.CharacterProfile.AddIssue(profile, "warn", "talents-empty", "the talent configuration has no readable nodes")
  end
  ns.CharacterProfile.SumTreePoints(t)
  profile.talents = t
  if t.readable then Cache.Set("talents", "active", ns.Database.Copy(t)) end
  return t
end
