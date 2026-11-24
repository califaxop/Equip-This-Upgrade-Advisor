-- Your talents, and what they do to the value of your stats.
--
-- Forever Upgrades' stat weights come from its simulator playing each spec with a full level-60 talent
-- build (Guides.lua: `talents`). Some of those talents change what a stat is worth: Mental Dexterity
-- turns Intellect into attack power, Flurry makes crits speed up your swings, Spiritual Guidance turns
-- Spirit into healing. Until you have them, those stats are worth less to you than the site's weights
-- say. Each entry below: the talent, the stat it feeds, and how much of that stat's weight in the
-- site's build comes from it (our estimate, from the talent's own text in Forever). With fewer ranks
-- than the build, that part of the weight scales down; with none, it's gone.
-- Talents that only change abilities (cooldowns, costs, a spell's damage) don't change gear choices
-- and aren't listed.
local _, ns = ...
local T = {}
ns.Talents = T

local function t(name, stat, share) return { name, stat, share } end
T.STATS = {
  ["WARRIOR:1"] = { t("Deep Wounds", "CRIT", 0.1), t("Impale", "CRIT", 0.1) },
  ["WARRIOR:2"] = { t("Flurry", "CRIT", 0.25), t("Deep Wounds", "CRIT", 0.08), t("Impale", "CRIT", 0.08) },
  ["WARRIOR:3"] = { t("Shield Specialization", "BLOCKVALUE", 0.3) },
  ["PALADIN:1"] = { t("Divine Intellect", "INT", 0.1), t("Illumination", "SPELLCRIT", 0.3) },
  ["PALADIN:2"] = { t("Toughness", "ARMOR", 0.1), t("Shield Specialization", "BLOCKVALUE", 0.2), t("Divine Intellect", "INT", 0.1) },
  ["PALADIN:3"] = { t("Champion of the Light", "INT", 0.6), t("Divine Strength", "STR", 0.1), t("Divine Intellect", "INT", 0.1) },
  ["HUNTER:1"] = { t("Careful Aim", "INT", 0.8), t("Mortal Shots", "CRIT", 0.15) },
  ["HUNTER:2"] = { t("Careful Aim", "INT", 0.8), t("Mortal Shots", "CRIT", 0.15) },
  ["HUNTER:3"] = { t("Careful Aim", "INT", 0.8) },
  ["ROGUE:1"] = { t("Seal Fate", "CRIT", 0.2), t("Lethality", "CRIT", 0.1) },
  ["ROGUE:2"] = { t("Lethality", "CRIT", 0.1) },
  ["ROGUE:3"] = { t("Lethality", "CRIT", 0.1) },
  ["PRIEST:1"] = { t("Mental Strength", "INT", 0.15) },
  ["PRIEST:2"] = { t("Spiritual Guidance", "SPI", 0.6), t("Mental Strength", "INT", 0.12) },
  ["PRIEST:3"] = { t("Shadowform", "SPELLCRIT", 0.2), t("Mental Strength", "INT", 0.1) },
  ["SHAMAN:1"] = { t("Elemental Fury", "SPELLCRIT", 0.25), t("Ancestral Knowledge", "INT", 0.1) },
  ["SHAMAN:2"] = { t("Mental Dexterity", "INT", 0.7), t("Mental Quickness", "INT", 0.1), t("Flurry", "CRIT", 0.3),
                   t("Ancestral Knowledge", "INT", 0.05) },
  ["SHAMAN:3"] = { t("Ancestral Knowledge", "INT", 0.1) },
  ["MAGE:1"] = { t("Arcane Mind", "INT", 0.15), t("Arcane Mind", "SPELLCRIT", 0.15) },
  ["MAGE:2"] = { t("Ignite", "SPELLCRIT", 0.3) },
  ["MAGE:3"] = { t("Ice Shards", "SPELLCRIT", 0.25) },
  ["WARLOCK:1"] = { t("Pandemic", "SPELLCRIT", 0.15), t("Demonic Embrace", "STA", 0.15) },
  ["WARLOCK:2"] = { t("Ruin", "SPELLCRIT", 0.2), t("Demonic Embrace", "STA", 0.15) },
  ["WARLOCK:3"] = { t("Ruin", "SPELLCRIT", 0.3), t("Demonic Embrace", "STA", 0.15) },
  ["DRUID:1"] = { t("Nature's Grace", "SPELLCRIT", 0.15) },
  ["DRUID:2"] = { t("Heart of the Wild", "STR", 0.15) },
  ["DRUID:3"] = { t("Heart of the Wild", "INT", 0.15), t("Bloom", "SPI", 0.2), t("Living Spirit", "SPI", 0.1) },
}

---------------------------------------------------------------------------
-- Reading your ranks: { [talent name] = rank }, kept until your talents change. nil when the game
-- won't say (then nothing is scaled: the site's build is assumed).
---------------------------------------------------------------------------
local ranks
function T.Forget() ranks = nil end

local function call(fn, ...)
  if not fn then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return select(2, unpack(r))
end

-- Forever: its talents are Retail's trait system (three Classic-style trees in one config)
local function FromTraits()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
    and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then
    return nil
  end
  local configID = call(C_ClassTalents.GetActiveConfigID)
  local info = configID and call(C_Traits.GetConfigInfo, configID)
  if not (type(info) == "table" and type(info.treeIDs) == "table") then return nil end
  local out, any = {}, false
  for _, treeID in ipairs(info.treeIDs) do
    for _, nodeID in ipairs(call(C_Traits.GetTreeNodes, treeID) or {}) do
      local node = call(C_Traits.GetNodeInfo, configID, nodeID)
      if type(node) == "table" then
        local rank = tonumber(node.currentRank or node.ranksPurchased) or 0
        local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
        local entry = entryID and call(C_Traits.GetEntryInfo, configID, entryID)
        local def = entry and entry.definitionID and call(C_Traits.GetDefinitionInfo, entry.definitionID)
        local name = def and (def.overrideName or (def.spellID and ns.SpellName(def.spellID)))
        if type(name) == "string" and name ~= "" then
          any = true
          out[name] = math.max(out[name] or 0, rank)
        end
      end
    end
  end
  return any and out or nil
end

-- older clients: GetTalentInfo per tab
local function FromTabs()
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return nil end
  local out, any = {}, false
  for tab = 1, (call(GetNumTalentTabs) or 0) do
    for i = 1, (call(GetNumTalents, tab) or 0) do
      local name, _, _, _, rank = call(GetTalentInfo, tab, i)
      if type(name) == "string" then any = true; out[name] = tonumber(rank) or 0 end
    end
  end
  return any and out or nil
end

function T.Ranks()
  if ranks == nil then ranks = FromTraits() or FromTabs() or false end
  return ranks or nil
end

-- What your talents leave of each stat's weight, for a spec: { [stat] = factor 0-1 }, and the lines
-- that explain it ({ "Intellect x0.30: Mental Dexterity 0/3" }). Stats not listed: 1.
function T.Factors(key)
  local list = T.STATS[key]
  local mine = T.Ranks()
  local g = ns.GUIDE and ns.GUIDE[key]
  local build = g and g.talents or {}
  local f, why = {}, {}
  if not (list and mine) then return f, why end
  for _, e in ipairs(list) do
    local name, stat, share = e[1], e[2], e[3]
    local full = build[name]
    if full and full > 0 then
      local have = math.min(mine[name] or 0, full)
      if have < full then
        f[stat] = (f[stat] or 1) * (1 - share * (1 - have / full))
        why[#why + 1] = { stat, name, have, full }
      end
    end
  end
  return f, why
end
