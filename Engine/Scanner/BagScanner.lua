-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- BagScanner: weapons, shields and off-hands in your bags (backpack and the four bags), so a
-- one-hander can be compared with the off-hand you'd wear with it, and a shield with a one-hander.
-- Only these are read (not the whole bag); items still loading are left out until they arrive.
local _, ns = ...; ns = ns.Engine
local BagScanner = ns.Module("BagScanner")
local Compat, Item = ns.Compat, ns.ItemAPI

BagScanner.LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_2HWEAPON = true }

function BagScanner.Scan(profile)
  local out = {}
  for bag = 0, 4 do
    local n = Compat.Value("C_Container.GetContainerNumSlots", bag) or 0
    for slot = 1, n do
      local link = Compat.Value("C_Container.GetContainerItemLink", bag, slot)
      if type(link) == "string" then
        local inst = Item.Instant(link)
        if inst and BagScanner.LOCS[inst.equipLoc] then
          local it = ns.EquipmentScanner.ReadItem(link)
          if it.loaded and it.canUse ~= false then out[#out + 1] = it end
        end
      end
    end
  end
  profile.bags = out
  return out
end
