-- EquipmentAPI: what's worn in each slot. Slot numbers are the game's inventory slot IDs; at
-- start-up each one is checked against GetInventorySlotInfo(slot name), and a mismatch is reported
-- by /eqn status instead of being trusted.
local _, ns = ...
local Equip = ns.Module("EquipmentAPI")
local Compat = ns.Compat

-- The slots the evaluator covers (the shirt and tabard are cosmetic and left out). The ranged slot
-- also holds relics (librams, idols, totems) on Forever's Classic content.
Equip.SLOTS = {
  { id = 1, key = "HEADSLOT", name = "Head" },
  { id = 2, key = "NECKSLOT", name = "Neck" },
  { id = 3, key = "SHOULDERSLOT", name = "Shoulders" },
  { id = 15, key = "BACKSLOT", name = "Back" },
  { id = 5, key = "CHESTSLOT", name = "Chest" },
  { id = 9, key = "WRISTSLOT", name = "Wrists" },
  { id = 10, key = "HANDSSLOT", name = "Hands" },
  { id = 6, key = "WAISTSLOT", name = "Waist" },
  { id = 7, key = "LEGSSLOT", name = "Legs" },
  { id = 8, key = "FEETSLOT", name = "Feet" },
  { id = 11, key = "FINGER0SLOT", name = "Ring 1" },
  { id = 12, key = "FINGER1SLOT", name = "Ring 2" },
  { id = 13, key = "TRINKET0SLOT", name = "Trinket 1" },
  { id = 14, key = "TRINKET1SLOT", name = "Trinket 2" },
  { id = 16, key = "MAINHANDSLOT", name = "Main hand" },
  { id = 17, key = "SECONDARYHANDSLOT", name = "Off hand" },
  { id = 18, key = "RANGEDSLOT", name = "Ranged / relic" },
}
-- weapon slots for temporary enchants (Enum.WeaponSlot in the docs: MainHand 0, OffHand 1, Ranged 2)
Equip.WEAPON_SLOT = { [16] = 0, [17] = 1, [18] = 2 }

-- Check our slot numbers against the client. Returns a list of mismatches (empty when all agree).
function Equip.VerifySlots()
  local bad = {}
  for _, s in ipairs(Equip.SLOTS) do
    local ok, id = Compat.Call("GetInventorySlotInfo", s.key)
    if not ok then
      bad[#bad + 1] = s.key .. ": " .. tostring(id)
    elseif id ~= s.id then
      bad[#bad + 1] = string.format("%s: client says %s, we use %d", s.key, tostring(id), s.id)
    end
  end
  return bad
end

function Equip.Link(slot)
  local v = Compat.Value("GetInventoryItemLink", "player", slot)
  return type(v) == "string" and v or nil
end

function Equip.ItemID(slot)
  return Compat.Value("GetInventoryItemID", "player", slot)
end

-- Temporary weapon enchants (poisons, oils, imbues): a list of { enchantID, timeLeft, charges }.
function Equip.TempEnchants(slot)
  local ws = Equip.WEAPON_SLOT[slot]
  if ws == nil then return nil end
  local ok, list = Compat.Call("C_Item.GetWeaponEnchantInfo", ws)
  if not ok or type(list) ~= "table" then return nil end
  local out = {}
  for _, e in ipairs(list) do
    local id = Compat.Field(e, "enchantID")
    if id and id > 0 then
      out[#out + 1] = { enchantID = id, timeLeft = Compat.Field(e, "timeLeft"), charges = Compat.Field(e, "charges"),
        type = Compat.Field(e, "enchantType") }
    end
  end
  return out
end

function Equip.CanDualWield() return Compat.Value("CanDualWield") == true end
