-- ItemAPI: item data. Items load asynchronously: until the client has an item's data, Info and
-- Stats return nil plus "pending" (never empty stats), and RequestLoad asks the client for it;
-- ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED say when it arrived (Scanner/CharacterScanner).
local _, ns = ...
local Item = ns.Module("ItemAPI")
local Compat = ns.Compat

-- Pure: the parts of an item link. "item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID:..."
-- Returns nil for anything that isn't an item link or item string.
function Item.ParseLink(link)
  if type(link) ~= "string" then return nil end
  local body = link:match("|Hitem:([%-%d:]*)|h") or link:match("^item:([%-%d:]*)")
  if not body then return nil end
  local f = {}
  for part in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = tonumber(part) or 0 end
  local itemID = f[1]
  if not itemID or itemID <= 0 then return nil end
  local gems = {}
  for i = 3, 6 do if (f[i] or 0) > 0 then gems[#gems + 1] = f[i] end end
  return {
    itemID = itemID,
    enchantID = (f[2] or 0) > 0 and f[2] or nil,
    gemIDs = gems,
    suffixID = (f[7] or 0) ~= 0 and f[7] or nil,
    uniqueID = (f[8] or 0) ~= 0 and f[8] or nil,
    linkLevel = (f[9] or 0) > 0 and f[9] or nil,
  }
end

function Item.IsCached(itemID)
  local v = Compat.Value("C_Item.IsItemDataCachedByID", itemID)
  return v == true
end

function Item.RequestLoad(itemID)
  return Compat.Call("C_Item.RequestLoadItemDataByID", itemID)
end

-- Always available (no server data needed): id, equip location, class and subclass.
function Item.Instant(linkOrID)
  local ok, itemID, itemType, itemSubType, equipLoc, icon, classID, subclassID = Compat.Call("C_Item.GetItemInfoInstant", linkOrID)
  if not ok or not itemID or itemID == Compat.SECRET then return nil end
  return {
    itemID = itemID, itemType = Compat.Plain(itemType), itemSubType = Compat.Plain(itemSubType),
    equipLoc = Compat.Plain(equipLoc), classID = Compat.Plain(classID), subclassID = Compat.Plain(subclassID),
  }
end

-- Full item info, or nil, "pending" while the client is still loading it.
function Item.Info(linkOrID)
  local ok, name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture,
    sellPrice, classID, subclassID, bindType, expansionID, setID = Compat.Call("C_Item.GetItemInfo", linkOrID)
  if not ok then return nil, "error" end
  if name == nil or name == Compat.SECRET then return nil, "pending" end
  return {
    name = name, link = Compat.Plain(link), quality = Compat.Plain(quality), itemLevel = Compat.Plain(itemLevel),
    minLevel = Compat.Plain(minLevel), itemType = Compat.Plain(itemType), itemSubType = Compat.Plain(itemSubType),
    equipLoc = Compat.Plain(equipLoc), sellPrice = Compat.Plain(sellPrice), classID = Compat.Plain(classID),
    subclassID = Compat.Plain(subclassID), bindType = Compat.Plain(bindType), setID = Compat.Plain(setID),
  }
end

-- The item's stat table (a copy, keys as the game gives them: ITEM_MOD_STAMINA_SHORT...), or nil.
function Item.Stats(link)
  local ok, t = Compat.Call("C_Item.GetItemStats", link)
  if not ok or type(t) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(t) do
    if not Compat.IsSecret(v) and type(v) == "number" then out[k] = v end
  end
  return out
end

function Item.NumSockets(linkOrID) return Compat.Value("C_Item.GetItemNumSockets", linkOrID) end
function Item.SetName(setID) return Compat.Value("C_Item.GetItemSetInfo", setID) end
function Item.CanUse(itemID) return Compat.Value("C_PlayerInfo.CanUseItem", itemID) end
function Item.UseSpell(linkOrID)
  local ok, name, spellID = Compat.Call("C_Item.GetItemSpell", linkOrID)
  if not ok or name == nil then return nil end
  return { name = Compat.Plain(name), spellID = Compat.Plain(spellID) }
end
