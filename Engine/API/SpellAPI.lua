-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- SpellAPI: spell names and the player's spellbook (which spells, which ranks are known).
local _, ns = ...; ns = ns.Engine
local Spell = ns.Module("SpellAPI")
local Compat = ns.Compat

function Spell.Name(spellID)
  local v = Compat.Value("C_Spell.GetSpellName", spellID)
  return type(v) == "string" and v or nil
end

function Spell.Description(spellID)
  local v = Compat.Value("C_Spell.GetSpellDescription", spellID)
  return type(v) == "string" and v ~= "" and v or nil
end

-- Enum.SpellBookSpellBank.Player (0 when the enum isn't there)
local function playerBank()
  return (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
end

function Spell.NumSkillLines() return Compat.Value("C_SpellBook.GetNumSpellBookSkillLines") or 0 end

function Spell.SkillLine(index)
  local ok, info = Compat.Call("C_SpellBook.GetSpellBookSkillLineInfo", index)
  if not ok or type(info) ~= "table" then return nil end
  return { name = Compat.Field(info, "name"), offset = Compat.Field(info, "itemIndexOffset"),
    count = Compat.Field(info, "numSpellBookItems"), hidden = Compat.Field(info, "shouldHide") }
end

function Spell.BookItem(index)
  local ok, info = Compat.Call("C_SpellBook.GetSpellBookItemInfo", index, playerBank())
  if not ok or type(info) ~= "table" then return nil end
  return { spellID = Compat.Field(info, "spellID"), name = Compat.Field(info, "name"),
    subName = Compat.Field(info, "subName"), passive = Compat.Field(info, "isPassive"),
    itemType = Compat.Field(info, "itemType") }
end

-- A spell's tooltip as the game shows it ({ left = {...}, right = {...} }): the right side holds
-- "8 sec cooldown", "Instant"...
function Spell.Tooltip(spellID)
  local ok, data = Compat.Call("C_TooltipInfo.GetSpellByID", spellID)
  if not ok or type(data) ~= "table" then return nil end
  local lines = Compat.Field(data, "lines")
  if type(lines) ~= "table" then return nil end
  local out = { left = {}, right = {} }
  for _, l in ipairs(lines) do
    local t, r = Compat.Field(l, "leftText"), Compat.Field(l, "rightText")
    if type(t) == "string" and t ~= "" then
      out.left[#out.left + 1] = t
      if type(r) == "string" and r ~= "" then out.right[#out.left] = r end
    end
  end
  return out
end

function Spell.IsKnown(spellID)
  local v = Compat.Value("C_SpellBook.IsSpellKnown", spellID)
  if v == nil or v == Compat.SECRET then return nil end
  return v and true or false
end
