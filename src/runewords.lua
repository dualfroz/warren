local Items = require("items")

local Runewords = {}

Runewords.MAX_RUNES = 3

Runewords.RUNES = { "sol", "ith", "tal", "ral", "eth", "amn" }

Runewords.WORDS = {
  ["sol-ith"]     = { name = "Zenith",   attack = 3 },
  ["tal-ral"]     = { name = "Bastion",  defense = 3 },
  ["eth-amn-sol"] = { name = "Undertow", attack = 2, defense = 2 },
}

local function wordKey(runes)
  return table.concat(runes, "-")
end

function Runewords.rune(key)
  return { kind = Items.RUNE, rune = key, name = key .. " rune", glyph = Items.glyphs[Items.RUNE] }
end

local function slottable(item)
  return item.kind == Items.WEAPON or item.kind == Items.ARMOR
end

function Runewords.socket(item, rune)
  if not slottable(item) then return false, "cannot hold runes" end
  item.runes = item.runes or {}
  if #item.runes >= Runewords.MAX_RUNES then return false, "the rune chain is full" end
  item.runes[#item.runes + 1] = rune.rune
  return true
end

function Runewords.activeWord(item)
  if not item or not item.runes or #item.runes == 0 then return nil end
  return Runewords.WORDS[wordKey(item.runes)]
end

function Runewords.attackBonus(entity)
  local total = 0
  local weaponWord = entity.weapon and Runewords.activeWord(entity.weapon)
  if weaponWord then total = total + (weaponWord.attack or 0) end
  local armorWord = entity.armor and Runewords.activeWord(entity.armor)
  if armorWord then total = total + (armorWord.attack or 0) end
  return total
end

function Runewords.defenseBonus(entity)
  local total = 0
  local weaponWord = entity.weapon and Runewords.activeWord(entity.weapon)
  if weaponWord then total = total + (weaponWord.defense or 0) end
  local armorWord = entity.armor and Runewords.activeWord(entity.armor)
  if armorWord then total = total + (armorWord.defense or 0) end
  return total
end

return Runewords
