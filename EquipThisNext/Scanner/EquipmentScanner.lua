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
  local tip = Item.Tooltip(link)
  local data = {
    name = info.name, quality = info.quality, itemLevel = info.itemLevel, minLevel = info.minLevel,
    equipLoc = info.equipLoc or it.equipLoc, classID = info.classID, subclassID = info.subclassID,
    setID = (info.setID and info.setID > 0) and info.setID or nil, bindType = info.bindType,
    sellPrice = info.sellPrice, stats = stats, sockets = Item.NumSockets(link) or 0,
    useSpell = Item.UseSpell(link),
    effects = ns.ItemEffects.Uncounted(tip and tip.left),
    unique = Item.IsUnique(link), canUse = Item.CanUse(parsed.itemID),
  }
  local IT = ns.ItemText
  if data.classID == 2 then   -- a weapon: its speed from the tooltip, its damage per swing from its DPS
    local spd = IT.Speed(tip)
    local dps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
    data.weapon = { speed = spd, dps = dps, min = nil, max = nil }
    data.weapon.min, data.weapon.max = IT.Damage(tip)
  end
  if data.equipLoc == "INVTYPE_SHIELD" then data.shieldBlock = IT.ShieldBlock(tip) end
  if data.setID then data.setBonuses = IT.SetBonuses(tip) end
  -- a permanent enchant: the lines its tooltip has that the same item without it hasn't
  if parsed.enchantID and tip then
    local bare = Item.Tooltip(Item.WithoutEnchant(link))
    if bare then
      local had = {}
      for _, l in ipairs(bare.left) do had[l] = (had[l] or 0) + 1 end
      local extra = {}
      for _, l in ipairs(tip.left) do
        if (had[l] or 0) > 0 then had[l] = had[l] - 1 else extra[#extra + 1] = l end
      end
      data.enchantText = #extra > 0 and table.concat(extra, "; ") or nil
      -- (an enchant line is also an "effect" line on the enchanted tooltip: not the item's own)
      local own = {}
      for _, e in ipairs(data.effects) do
        local mine = true
        for _, x in ipairs(extra) do if x == e then mine = false end end
        if mine then own[#own + 1] = e end
      end
      data.effects = own
    end
  end
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
