-- Rune stones drop as dungeon loot and slot into a weapon or armor's rune
-- chain in the order they are socketed. A chain that exactly matches a
-- cataloged sequence forms a runeword: a fixed, always-on stat bonus read
-- live by combat.lua (the same additive-bonus pattern skills.lua already
-- uses for berserk/mana shield), rather than baked permanently into the
-- item's own power the way affixes.lua or crafting.lua's gems are - so a
-- runeword needs no equip-time stat sync, and simply stops applying the
-- instant a further rune breaks its exact match.

local Items = require("items")

local Runewords = {}

Runewords.MAX_RUNES = 3

Runewords.RUNES = { "sol", "ith", "tal", "ral", "eth", "amn" }

-- Keyed by the chain's runes joined in slotted order - an exact match only,
-- so a chain longer or shorter than a given word never qualifies for it.
Runewords.WORDS = {
  ["sol-ith"]     = { name = "Zenith",   attack = 3 },
  ["tal-ral"]     = { name = "Bastion",  defense = 3 },
  ["eth-amn-sol"] = { name = "Undertow", attack = 2, defense = 2 },
}

local function wordKey(runes)
  return table.concat(runes, "-")
end

function Runewords.rune(key)
  return { kind = Items.RUNE, rune = key, name = key .. " rune", glyph = "1" }
end

local function slottable(item)
  return item.kind == Items.WEAPON or item.kind == Items.ARMOR
end

-- Appends `rune`'s key to `item`'s chain. Fails once the item is full or is
-- not a weapon/armor; never fails on a rune that will not complete a known
-- word, since an unmatched chain simply confers no bonus rather than being
-- rejected outright - there is no wasted resource to protect against the way
-- crafting.lua guards a gem merge against mismatched pairs.
function Runewords.socket(item, rune)
  if not slottable(item) then return false, "cannot hold runes" end
  item.runes = item.runes or {}
  if #item.runes >= Runewords.MAX_RUNES then return false, "the rune chain is full" end
  item.runes[#item.runes + 1] = rune.rune
  return true
end

-- The cataloged word `item`'s current chain forms, or nil if it matches none
-- (including an empty chain, or one that no longer exactly matches any entry
-- once it has grown past a shorter word's own length).
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
