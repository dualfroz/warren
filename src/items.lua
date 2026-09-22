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

Items.glyphs = {
  [Items.POTION] = "!",
  [Items.SCROLL] = "?",
  [Items.WEAPON] = "/",
  [Items.ARMOR] = "[",
  [Items.RING] = "=",
  [Items.FOOD] = "%",
  [Items.KEY] = "(",
  [Items.TOME] = "&",
  [Items.AMULET] = "\"",
  [Items.BOW] = ")",
  [Items.AMMO] = "{",
  [Items.GOLD] = "$",
  [Items.GEM] = "*",
  [Items.CHARM] = "]",
  [Items.KIT] = "t",
  [Items.HERB] = "Y",
  [Items.RUNE] = "1",
  [Items.PICK] = "\\",
  [Items.LOCKPICK] = "J",
  [Items.CONTRACT] = "P",
  [Items.NET] = "F",
  [Items.RIFTSTONE] = "R",
}

local glyphs = Items.glyphs

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
  return { kind = Items.POTION, effect = "heal", name = "potion of healing", glyph = glyphs[Items.POTION], power = power }
end

function Items.potionOf(effect, power)
  local spec
  for _, entry in ipairs(Items.potionTypes) do
    if entry.effect == effect then spec = entry end
  end
  return { kind = Items.POTION, effect = effect, name = spec.name, glyph = glyphs[Items.POTION],
    power = power or spec.power }
end

function Items.scroll(effect)
  local spec
  for _, entry in ipairs(Items.scrollTypes) do
    if entry.effect == effect then spec = entry end
  end
  return { kind = Items.SCROLL, effect = effect, name = spec.name, glyph = glyphs[Items.SCROLL] }
end

function Items.weapon(name, power)
  return { kind = Items.WEAPON, name = name, glyph = glyphs[Items.WEAPON], power = power,
    durability = Durability.MAX, maxDurability = Durability.MAX }
end

function Items.armor(name, power)
  return { kind = Items.ARMOR, name = name, glyph = glyphs[Items.ARMOR], power = power,
    durability = Durability.MAX, maxDurability = Durability.MAX }
end

function Items.ring(name, attack, defense)
  return { kind = Items.RING, name = name, glyph = glyphs[Items.RING], attack = attack or 0, defense = defense or 0 }
end

function Items.food(name, nutrition)
  return { kind = Items.FOOD, name = name, glyph = glyphs[Items.FOOD], nutrition = nutrition }
end

function Items.key(name)
  return { kind = Items.KEY, name = name or "iron key", glyph = glyphs[Items.KEY] }
end

function Items.tome(spellKey, name)
  return { kind = Items.TOME, spell = spellKey, name = name or ("tome of " .. spellKey), glyph = glyphs[Items.TOME] }
end

function Items.amulet(name)
  return { kind = Items.AMULET, name = name or "Amulet of Warren", glyph = glyphs[Items.AMULET] }
end

function Items.bow(name, power, range)
  return { kind = Items.BOW, name = name, glyph = glyphs[Items.BOW], power = power, range = range,
    durability = Durability.MAX, maxDurability = Durability.MAX }
end

function Items.ammo(name, count)
  return { kind = Items.AMMO, name = name or "arrow", glyph = glyphs[Items.AMMO], count = count }
end

function Items.gold(amount)
  return { kind = Items.GOLD, name = "gold", glyph = glyphs[Items.GOLD], amount = amount }
end

function Items.charm(companionKey, name)
  return { kind = Items.CHARM, companion = companionKey, name = name or ("charm of the " .. companionKey),
    glyph = glyphs[Items.CHARM] }
end

function Items.kit(effect)
  return { kind = Items.KIT, effect = effect, name = effect .. " trap kit", glyph = glyphs[Items.KIT] }
end

function Items.contract(key, name)
  return { kind = Items.CONTRACT, hireling = key, name = name or (key .. " contract"), glyph = glyphs[Items.CONTRACT] }
end

function Items.pick(name, uses)
  return { kind = Items.PICK, name = name or "miner's pick", glyph = glyphs[Items.PICK], uses = uses or 20 }
end

function Items.lockpick(name)
  return { kind = Items.LOCKPICK, name = name or "lockpick", glyph = glyphs[Items.LOCKPICK] }
end

function Items.net(name)
  return { kind = Items.NET, name = name or "net", glyph = glyphs[Items.NET] }
end

function Items.riftstone(name)
  return { kind = Items.RIFTSTONE, name = name or "rift shard", glyph = glyphs[Items.RIFTSTONE] }
end

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
