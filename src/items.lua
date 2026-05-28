-- Items are plain data tables so they serialize without metatable handling.
-- Potions and scrolls carry an effect key resolved by the effects module; gear
-- modifies effective stats when equipped and may carry an affix. Potion and
-- scroll type catalogs drive the identification system.

local Items = {}

Items.POTION = "potion"
Items.SCROLL = "scroll"
Items.WEAPON = "weapon"
Items.ARMOR = "armor"
Items.RING = "ring"
Items.FOOD = "food"
Items.KEY = "key"

-- Catalogs list every distinct type in a fixed order; identification assigns a
-- random appearance to each entry, so the order here must stay stable.
Items.potionTypes = {
  { effect = "heal",     name = "potion of healing",   power = 10 },
  { effect = "poison",   name = "potion of poison",    power = 3 },
  { effect = "strength", name = "potion of strength",  power = 0 },
  { effect = "haste",    name = "potion of speed",     power = 0 },
}

Items.scrollTypes = {
  { effect = "teleport", name = "scroll of teleportation" },
  { effect = "identify", name = "scroll of identify" },
  { effect = "mapping",  name = "scroll of magic mapping" },
  { effect = "fireball", name = "scroll of fireball" },
}

function Items.typeId(item)
  return item.kind .. "/" .. (item.effect or "")
end

function Items.potion(power)
  return { kind = Items.POTION, effect = "heal", name = "potion of healing", glyph = "!", power = power }
end

function Items.potionOf(effect, power)
  local spec
  for _, entry in ipairs(Items.potionTypes) do
    if entry.effect == effect then spec = entry end
  end
  return { kind = Items.POTION, effect = effect, name = spec.name, glyph = "!", power = power or spec.power }
end

function Items.scroll(effect)
  local spec
  for _, entry in ipairs(Items.scrollTypes) do
    if entry.effect == effect then spec = entry end
  end
  return { kind = Items.SCROLL, effect = effect, name = spec.name, glyph = "?" }
end

function Items.weapon(name, power)
  return { kind = Items.WEAPON, name = name, glyph = "/", power = power }
end

function Items.armor(name, power)
  return { kind = Items.ARMOR, name = name, glyph = "[", power = power }
end

function Items.ring(name, attack, defense)
  return { kind = Items.RING, name = name, glyph = "=", attack = attack or 0, defense = defense or 0 }
end

function Items.food(name, nutrition)
  return { kind = Items.FOOD, name = name, glyph = "%", nutrition = nutrition }
end

function Items.key(name)
  return { kind = Items.KEY, name = name or "iron key", glyph = "*" }
end

function Items.equipWeapon(item, entity)
  if entity.weapon then
    entity.attack = entity.attack - entity.weapon.power
    entity.inventory[#entity.inventory + 1] = entity.weapon
  end
  entity.weapon = item
  entity.attack = entity.attack + item.power
  return item.power
end

function Items.equipArmor(item, entity)
  if entity.armor then
    entity.defense = entity.defense - entity.armor.power
    entity.inventory[#entity.inventory + 1] = entity.armor
  end
  entity.armor = item
  entity.defense = entity.defense + item.power
  return item.power
end

function Items.equipRing(item, entity)
  if entity.ring then
    entity.attack = entity.attack - entity.ring.attack
    entity.defense = entity.defense - entity.ring.defense
    entity.inventory[#entity.inventory + 1] = entity.ring
  end
  entity.ring = item
  entity.attack = entity.attack + item.attack
  entity.defense = entity.defense + item.defense
  return item.attack + item.defense
end

-- Applies a self-contained item to an entity and returns the magnitude of its
-- effect. Effects that need the wider world (teleport, mapping, fireball) are
-- routed through the effects module by the game instead.
function Items.use(item, entity)
  if item.kind == Items.POTION and item.effect == "heal" then
    local before = entity.hp
    entity.hp = math.min(entity.maxHp, entity.hp + item.power)
    return entity.hp - before
  elseif item.kind == Items.WEAPON then
    return Items.equipWeapon(item, entity)
  elseif item.kind == Items.ARMOR then
    return Items.equipArmor(item, entity)
  elseif item.kind == Items.RING then
    return Items.equipRing(item, entity)
  end
  return 0
end

function Items.useFromInventory(entity, index)
  local item = table.remove(entity.inventory, index)
  local effect = Items.use(item, entity)
  return item, effect
end

return Items
