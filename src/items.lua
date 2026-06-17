-- Items are plain data tables so they serialize without metatable handling.
-- Potions and scrolls carry an effect key resolved by the effects module; gear
-- modifies effective stats when equipped and may carry an affix. Potion and
-- scroll type catalogs drive the identification system.

local Durability = require("durability")

local Items = {}

Items.POTION = "potion"
Items.SCROLL = "scroll"
Items.WEAPON = "weapon"
Items.ARMOR = "armor"
Items.RING = "ring"
Items.FOOD = "food"
Items.KEY = "key"
Items.TOME = "tome"
Items.AMULET = "amulet"
Items.BOW = "bow"
Items.AMMO = "ammo"
Items.GOLD = "gold"
Items.GEM = "gem"
Items.CHARM = "charm"
Items.KIT = "kit"
Items.HERB = "herb"
Items.RUNE = "rune"
Items.PICK = "pick"
Items.LOCKPICK = "lockpick"
Items.CONTRACT = "contract"
Items.NET = "net"
Items.RIFTSTONE = "riftstone"

-- Catalogs list every distinct type in a fixed order; identification assigns a
-- random appearance to each entry, so the order here must stay stable.
-- New entries append at the end: identify.lua assigns appearances by index
-- into this list, so inserting anywhere else would reshuffle which look
-- every earlier, already-loot-tested effect gets for a given seed. There are
-- exactly as many potionLooks in identify.lua as there are entries here, so
-- adding one more type here requires a matching look there too.
Items.potionTypes = {
  { effect = "heal",     name = "potion of healing",   power = 10 },
  { effect = "poison",   name = "potion of poison",    power = 3 },
  { effect = "strength", name = "potion of strength",  power = 0 },
  { effect = "haste",    name = "potion of speed",     power = 0 },
  { effect = "fortify",  name = "potion of fortification", power = 0 },
  { effect = "clarity",  name = "potion of clarity",   power = 30 },
  { effect = "cure",     name = "potion of cleansing", power = 0 },
  { effect = "confuse",  name = "potion of confusion", power = 0 },
  { effect = "blind",    name = "potion of blindness", power = 0 },
  { effect = "levitate", name = "potion of levitation", power = 0 },
}

Items.scrollTypes = {
  { effect = "teleport",    name = "scroll of teleportation" },
  { effect = "identify",    name = "scroll of identify" },
  { effect = "mapping",     name = "scroll of magic mapping" },
  { effect = "fireball",    name = "scroll of fireball" },
  { effect = "removecurse", name = "scroll of remove curse" },
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
  return { kind = Items.WEAPON, name = name, glyph = "/", power = power,
    durability = Durability.MAX, maxDurability = Durability.MAX }
end

function Items.armor(name, power)
  return { kind = Items.ARMOR, name = name, glyph = "[", power = power,
    durability = Durability.MAX, maxDurability = Durability.MAX }
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

function Items.tome(spellKey, name)
  return { kind = Items.TOME, spell = spellKey, name = name or ("tome of " .. spellKey), glyph = "&" }
end

function Items.amulet(name)
  return { kind = Items.AMULET, name = name or "Amulet of Warren", glyph = "\"" }
end

function Items.bow(name, power, range)
  return { kind = Items.BOW, name = name, glyph = "}", power = power, range = range,
    durability = Durability.MAX, maxDurability = Durability.MAX }
end

function Items.ammo(name, count)
  return { kind = Items.AMMO, name = name or "arrow", glyph = "^", count = count }
end

function Items.gold(amount)
  return { kind = Items.GOLD, name = "gold", glyph = "$", amount = amount }
end

function Items.charm(companionKey, name)
  return { kind = Items.CHARM, companion = companionKey, name = name or ("charm of the " .. companionKey), glyph = "0" }
end

function Items.kit(effect)
  return { kind = Items.KIT, effect = effect, name = effect .. " trap kit", glyph = "t" }
end

-- A shopkeeper's contract to hire mercenaries.lua's `key` roster entry: paid
-- for outright at the shop's own price (see shop.lua's CONTRACT branch), so
-- using it just takes the mercenary on rather than spending any further
-- gold - unlike a trap kit above, which is free to find but costs nothing
-- to use either.
function Items.contract(key, name)
  return { kind = Items.CONTRACT, hireling = key, name = name or (key .. " contract"), glyph = "P" }
end

function Items.pick(name, uses)
  return { kind = Items.PICK, name = name or "miner's pick", glyph = "\\", uses = uses or 20 }
end

-- A single-use gamble against a locked chest's own lock (see chests.lua's
-- Chests.pick) - consumed win or lose, unlike the miner's pick above which
-- wears down over many swings instead of vanishing in one.
function Items.lockpick(name)
  return { kind = Items.LOCKPICK, name = name or "lockpick", glyph = ";" }
end

-- A weighted throwing net (see captives.lua's Captives.resolve): unlike a
-- thrown weapon above, which is aimed to hurt, a net is aimed to subdue a
-- battered wild monster alive instead of finishing it off - and is spent
-- from the inventory whether or not it actually holds, exactly like a
-- lockpick's own single gamble.
function Items.net(name)
  return { kind = Items.NET, name = name or "net", glyph = "o" }
end

-- Fuel for a single rift crossing (see branches.lua): unlike a key, which
-- only ever opens the one lock it was cut for, a shard is spent the instant
-- Game:enterRift first stabilizes a given rift, not on every crossing after -
-- so carrying more than one only ever matters if the run finds more than one
-- rift to open.
function Items.riftstone(name)
  return { kind = Items.RIFTSTONE, name = name or "rift shard", glyph = "R" }
end

-- Adds/removes a weapon or armor's power using its own durability-aware
-- effective power (see durability.lua) rather than its raw `power` field, so
-- unequipping and later re-equipping an already-broken piece never bakes
-- power back in for free.
function Items.equipWeapon(item, entity)
  if entity.weapon then
    entity.attack = entity.attack - Durability.effectivePower(entity.weapon)
    entity.inventory[#entity.inventory + 1] = entity.weapon
  end
  entity.weapon = item
  local gained = Durability.effectivePower(item)
  entity.attack = entity.attack + gained
  return gained
end

function Items.equipArmor(item, entity)
  if entity.armor then
    entity.defense = entity.defense - Durability.effectivePower(entity.armor)
    entity.inventory[#entity.inventory + 1] = entity.armor
  end
  entity.armor = item
  local gained = Durability.effectivePower(item)
  entity.defense = entity.defense + gained
  return gained
end

function Items.equipBow(item, entity)
  if entity.bow then
    entity.inventory[#entity.inventory + 1] = entity.bow
  end
  entity.bow = item
  return item.power
end

function Items.equipPick(item, entity)
  if entity.pick then
    entity.inventory[#entity.inventory + 1] = entity.pick
  end
  entity.pick = item
  return item.uses
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
  elseif item.kind == Items.BOW then
    return Items.equipBow(item, entity)
  elseif item.kind == Items.PICK then
    return Items.equipPick(item, entity)
  end
  return 0
end

function Items.useFromInventory(entity, index)
  local item = table.remove(entity.inventory, index)
  local effect = Items.use(item, entity)
  return item, effect
end

return Items
