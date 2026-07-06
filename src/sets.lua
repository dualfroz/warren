-- Item sets: matching gear that all share a `set` tag and grants an
-- escalating stat bonus once enough pieces are worn together at once - a
-- fixed weapon/armor/ring/bow catalog of named pieces (see Sets.create),
-- unlike affixes.lua's random roll bolted onto an ordinary base item. The
-- bonus is read live off however many pieces of a given set the wearer
-- currently has equipped (Sets.attackBonus/defenseBonus, wired into
-- combat.lua exactly the way runewords.lua's own live bonus is), so
-- swapping a single piece out mid-run instantly drops back to a lower
-- threshold - or none at all - rather than needing an explicit uninstall
-- step the way a socketed gem or an enchant would.

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
    -- Independent totals, not a stacking ladder: reaching the 3-piece
    -- threshold replaces the 2-piece bonus rather than adding to it.
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

-- Every (set, slot) pairing flattened in a fixed order, mirroring
-- artifacts.lua's own Artifacts.order: the list a builder placement rolls
-- a single uniform index into so every piece of every set is equally
-- likely to turn up on a given floor.
Sets.order = {}
for _, spec in ipairs(Sets.catalog) do
  for _, slot in ipairs(SLOT_ORDER) do
    if spec.pieces[slot] then
      Sets.order[#Sets.order + 1] = { set = spec.key, slot = slot }
    end
  end
end

-- Builds the dropped item for `setKey`'s `slot` piece in the same shape
-- items.lua's own constructors return for that slot, tagged with the
-- `set` field every function below keys its live bonus off.
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

-- How many of `entity`'s four equip slots currently carry a piece of each
-- set it has at least one piece of, keyed by set key. Walks a fixed slot
-- order rather than pairs() over the entity itself, so the result never
-- depends on Lua's unspecified table iteration order.
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

-- The richest bonus tier `count` pieces of `setKey` qualify for, and the
-- threshold it came from, or nil below its lowest threshold.
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

-- Hp `entity` regenerates this turn from any active set bonus that grants
-- one, summed the same way attack/defense are above.
function Sets.regenAmount(entity)
  local total = 0
  local counts = Sets.equippedCounts(entity)
  for _, spec in ipairs(Sets.catalog) do
    local bonus = Sets.bonusFor(spec.key, counts[spec.key])
    if bonus then total = total + (bonus.regen or 0) end
  end
  return total
end

-- A human-readable "Name Npc" tag for every set currently meeting its
-- lowest threshold, in catalog order - read by render.lua's status panel
-- and by nothing that affects game logic.
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
