local Items = require("items")

local Sets = {}

local SLOT_ORDER = { "weapon", "armor", "ring", "bow" }

Sets.catalog = {
  {
    key = "ironclad", name = "Ironclad",
    pieces = {
      weapon = { name = "Ironclad Greatsword", power = 3 },
      armor  = { name = "Ironclad Plate", power = 3 },
      ring   = { name = "Ironclad Signet", attack = 0, defense = 1 },
    },
    bonuses = {
      [2] = { attack = 1, defense = 1 },
      [3] = { attack = 2, defense = 3, regen = 1 },
    },
  },
  {
    key = "duskrunner", name = "Duskrunner",
    pieces = {
      weapon = { name = "Duskrunner Fang", power = 2 },
      bow    = { name = "Duskrunner Bow", power = 2, range = 5 },
      ring   = { name = "Duskrunner Loop", attack = 1, defense = 0 },
    },
    bonuses = {
      [2] = { attack = 1 },
      [3] = { attack = 3, defense = 1 },
    },
  },
}

Sets.byKey = {}
for _, spec in ipairs(Sets.catalog) do
  Sets.byKey[spec.key] = spec
end

Sets.order = {}
for _, spec in ipairs(Sets.catalog) do
  for _, slot in ipairs(SLOT_ORDER) do
    if spec.pieces[slot] then
      Sets.order[#Sets.order + 1] = { set = spec.key, slot = slot }
    end
  end
end

function Sets.create(setKey, slot)
  local spec = Sets.byKey[setKey]
  local piece = spec and spec.pieces[slot]
  if not piece then return nil end
  local item
  if slot == "weapon" then item = Items.weapon(piece.name, piece.power)
  elseif slot == "armor" then item = Items.armor(piece.name, piece.power)
  elseif slot == "ring" then item = Items.ring(piece.name, piece.attack, piece.defense)
  elseif slot == "bow" then item = Items.bow(piece.name, piece.power, piece.range)
  end
  item.set = setKey
  return item
end

function Sets.equippedCounts(entity)
  local counts = {}
  for _, slot in ipairs(SLOT_ORDER) do
    local item = entity[slot]
    if item and item.set then
      counts[item.set] = (counts[item.set] or 0) + 1
    end
  end
  return counts
end

function Sets.bonusFor(setKey, count)
  local spec = Sets.byKey[setKey]
  if not spec or not count or count <= 0 then return nil end
  local best, bestThreshold
  for threshold, bonus in pairs(spec.bonuses) do
    if count >= threshold and (not bestThreshold or threshold > bestThreshold) then
      best, bestThreshold = bonus, threshold
    end
  end
  return best, bestThreshold
end

function Sets.attackBonus(entity)
  local total = 0
  local counts = Sets.equippedCounts(entity)
  for _, spec in ipairs(Sets.catalog) do
    local bonus = Sets.bonusFor(spec.key, counts[spec.key])
    if bonus then total = total + (bonus.attack or 0) end
  end
  return total
end

function Sets.defenseBonus(entity)
  local total = 0
  local counts = Sets.equippedCounts(entity)
  for _, spec in ipairs(Sets.catalog) do
    local bonus = Sets.bonusFor(spec.key, counts[spec.key])
    if bonus then total = total + (bonus.defense or 0) end
  end
  return total
end

function Sets.regenAmount(entity)
  local total = 0
  local counts = Sets.equippedCounts(entity)
  for _, spec in ipairs(Sets.catalog) do
    local bonus = Sets.bonusFor(spec.key, counts[spec.key])
    if bonus then total = total + (bonus.regen or 0) end
  end
  return total
end

function Sets.activeDescriptions(entity)
  local counts = Sets.equippedCounts(entity)
  local parts = {}
  for _, spec in ipairs(Sets.catalog) do
    local count = counts[spec.key]
    if Sets.bonusFor(spec.key, count) then
      parts[#parts + 1] = spec.name .. " " .. count .. "pc"
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ", ")
end

return Sets
