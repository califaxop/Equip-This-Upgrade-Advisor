-- EquipmentScanner: every covered slot into profile.equipment. An item the client hasn't loaded yet
-- is recorded as loaded = false with no stats (never as an empty item) and its data is requested;
-- the character scanner rescans when the data arrives.
local _, ns = ...
local EquipmentScanner = ns.Module("EquipmentScanner")
local Item, Equip, Cache = ns.ItemAPI, ns.EquipmentAPI, ns.Cache

-- One item link -> item record (cached by link: the same link always has the same data).
function EquipmentScanner.ReadItem(link, slot, slotName)
  local parsed = Item.ParseLink(link)
  local it = { slot = slot, slotName = slotName, link = link, loaded = false }
  if not parsed then
    it.unreadable = true
    return it
  end
  it.itemID, it.enchantID, it.gemIDs, it.suffixID = parsed.itemID, parsed.enchantID, parsed.gemIDs, parsed.suffixID
  local cached = Cache.Get("item", link)
  if cached then
    for k, v in pairs(cached) do it[k] = v end
    it.loaded = true
    return it
  end
  local inst = Item.Instant(link)
  if inst then it.equipLoc, it.classID, it.subclassID = inst.equipLoc, inst.classID, inst.subclassID end
  local info = Item.IsCached(parsed.itemID) and Item.Info(link)
  local stats = info and Item.Stats(link)
  if not (info and stats) then
    Item.RequestLoad(parsed.itemID)
    return it
  end
  local data = {
    name = info.name, quality = info.quality, itemLevel = info.itemLevel, minLevel = info.minLevel,
    equipLoc = info.equipLoc or it.equipLoc, classID = info.classID, subclassID = info.subclassID,
    setID = (info.setID and info.setID > 0) and info.setID or nil, bindType = info.bindType,
    sellPrice = info.sellPrice, stats = stats, sockets = Item.NumSockets(link) or 0,
    useSpell = Item.UseSpell(link),
    effects = ns.ItemEffects.Uncounted(Item.TooltipLines(link)),
  }
  Cache.Set("item", link, data)
  for k, v in pairs(data) do it[k] = v end
  it.loaded = true
  return it
end

function EquipmentScanner.Scan(profile)
  local eq = { slots = {}, pending = {} }
  local waiting = 0
  for _, s in ipairs(Equip.SLOTS) do
    local link = Equip.Link(s.id)
    local it
    if not link then
      -- the slot may hold an item whose link isn't ready yet: an ID without a link is not "empty"
      local id = Equip.ItemID(s.id)
      if id then
        it = { slot = s.id, slotName = s.name, itemID = id, loaded = false, gemIDs = {} }
        Item.RequestLoad(id)
      else
        it = { slot = s.id, slotName = s.name, empty = true }
      end
    else
      it = EquipmentScanner.ReadItem(link, s.id, s.name)
    end
    if Equip.WEAPON_SLOT[s.id] and not it.empty then it.tempEnchants = Equip.TempEnchants(s.id) end
    if not it.empty and not it.loaded then
      waiting = waiting + 1
      if it.itemID then eq.pending[it.itemID] = s.id end
    end
    eq.slots[s.id] = it
  end
  profile.equipment = eq
  profile.meta.pendingItems = waiting
  profile.sets = ns.CharacterProfile.CountSets(eq)
  for setID, set in pairs(profile.sets) do set.name = Item.SetName(setID) end
  if waiting > 0 then
    ns.CharacterProfile.AddIssue(profile, "info", "items-loading", waiting .. " item(s) still loading; they'll be read when the game has them")
  end
  return eq
end
