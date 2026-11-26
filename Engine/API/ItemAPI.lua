-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- ItemAPI: item data. Items load asynchronously: until the client has an item's data, Info and
-- Stats return nil plus "pending" (never empty stats), and RequestLoad asks the client for it;
-- ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED say when it arrived (Scanner/CharacterScanner).
local _, ns = ...; ns = ns.Engine
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
  local ok, itemID, itemType, itemSubType, equipLoc, _, classID, subclassID = Compat.Call("C_Item.GetItemInfoInstant", linkOrID)
  if not ok or not itemID or itemID == Compat.SECRET then return nil end
  return {
    itemID = itemID, itemType = Compat.Plain(itemType), itemSubType = Compat.Plain(itemSubType),
    equipLoc = Compat.Plain(equipLoc), classID = Compat.Plain(classID), subclassID = Compat.Plain(subclassID),
  }
end

-- Full item info, or nil, "pending" while the client is still loading it.
function Item.Info(linkOrID)
  local ok, name, link, quality, itemLevel, minLevel, itemType, itemSubType, _, equipLoc, _,
    sellPrice, classID, subclassID, bindType, _, setID = Compat.Call("C_Item.GetItemInfo", linkOrID)
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

-- The item's tooltip: { left = { text... }, right = { [i] = text } } (same line numbers), or nil
function Item.Tooltip(link)
  local ok, data = Compat.Call("C_TooltipInfo.GetHyperlink", link)
  if not ok or type(data) ~= "table" then return nil end
  local lines = Compat.Field(data, "lines")
  if type(lines) ~= "table" then return nil end
  local out = { left = {}, right = {} }
  for _, l in ipairs(lines) do
    local t = Compat.Field(l, "leftText")
    local r = Compat.Field(l, "rightText")
    if type(t) == "string" and t ~= "" then
      out.left[#out.left + 1] = t
      if type(r) == "string" and r ~= "" then out.right[#out.left] = r end
    end
  end
  return out
end

-- the same link without its permanent enchant (item:ID:enchant: -> item:ID::)
function Item.WithoutEnchant(link)
  if type(link) ~= "string" then return nil end
  local out, n = link:gsub("(item:%-?%d+):%-?%d*:", "%1::", 1)
  return n > 0 and out or link
end

function Item.IsUnique(linkOrID)
  local ok, unique = Compat.Call("C_Item.GetItemUniquenessByID", linkOrID)
  if not ok or unique == Compat.SECRET then return nil end
  return unique and true or false
end

function Item.NumSockets(linkOrID) return Compat.Value("C_Item.GetItemNumSockets", linkOrID) end
function Item.SetName(setID) return Compat.Value("C_Item.GetItemSetInfo", setID) end
function Item.CanUse(itemID) return Compat.Value("C_PlayerInfo.CanUseItem", itemID) end
function Item.UseSpell(linkOrID)
  local ok, name, spellID = Compat.Call("C_Item.GetItemSpell", linkOrID)
  if not ok or name == nil then return nil end
  return { name = Compat.Plain(name), spellID = Compat.Plain(spellID) }
end
