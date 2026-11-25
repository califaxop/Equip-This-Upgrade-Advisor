-- SpellAPI: spell names and the player's spellbook (which spells, which ranks are known).
local _, ns = ...
local Spell = ns.Module("SpellAPI")
local Compat = ns.Compat

function Spell.Name(spellID)
  local v = Compat.Value("C_Spell.GetSpellName", spellID)
  return type(v) == "string" and v or nil
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
