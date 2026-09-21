local Items = require("items")
local Affixes = require("affixes")
local Factions = require("factions")
local Mercenaries = require("mercenaries")

local Shop = {}

local POTION_PRICE = {
  heal = 15, poison = 6, strength = 45, haste = 25, clarity = 20, cure = 30,
  confuse = 8, blind = 8, levitate = 20,
}
local SCROLL_PRICE = { teleport = 25, identify = 18, mapping = 20, fireball = 35 }
local FLAT_PRICE = { [Items.FOOD] = 5, [Items.TOME] = 55, [Items.PICK] = 40 }
local AMMO_UNIT_PRICE = 2

function Shop.priceOf(item)
  if item.kind == Items.POTION then
    return POTION_PRICE[item.effect] or 10
  elseif item.kind == Items.SCROLL then
    return SCROLL_PRICE[item.effect] or 10
  elseif item.kind == Items.WEAPON or item.kind == Items.ARMOR then
    return 20 + item.power * 15
  elseif item.kind == Items.BOW then
    return 25 + item.power * 12
  elseif item.kind == Items.RING then
    return 30 + (item.attack + item.defense) * 20
  elseif item.kind == Items.AMMO then
    return AMMO_UNIT_PRICE * (item.count or 1)
  elseif item.kind == Items.CONTRACT then
    return Mercenaries.byKey[item.hireling].hireCost
  else
    return FLAT_PRICE[item.kind] or 10
  end
end

function Shop.sellValue(item)
  return math.max(1, Shop.priceOf(item) // 2)
end

function Shop.effectivePrice(game, ground)
  return math.max(1, math.floor(ground.price * Factions.priceMultiplier(game.player, Factions.MERCHANT)))
end

function Shop.buy(game, ground)
  if not ground.price then return nil end
  local price = Shop.effectivePrice(game, ground)
  if game.player.gold < price then return nil end
  game.player.gold = game.player.gold - price
  game.player.inventory[#game.player.inventory + 1] = ground.item
  return price
end

function Shop.sell(game, index)
  local item = game.player.inventory[index]
  if not item then return nil end
  local value = math.max(1, math.floor(Shop.sellValue(item) / Factions.priceMultiplier(game.player, Factions.MERCHANT)))
  game.player.gold = game.player.gold + value
  table.remove(game.player.inventory, index)
  return value
end

local weaponBases = { { name = "rapier", power = 3 }, { name = "war hammer", power = 5 } }
local armorBases = { { name = "banded mail", power = 2 } }

function Shop.stock(rng)
  local wares = {}
  local slots = rng:range(3, 5)
  for _ = 1, slots do
    local roll = rng:range(1, 100)
    local item
    if roll <= 30 then
      local effects = { "heal", "strength", "haste", "clarity", "cure" }
      item = Items.potionOf(effects[rng:range(1, #effects)])
    elseif roll <= 45 then
      local effects = { "identify", "mapping", "fireball" }
      item = Items.scroll(effects[rng:range(1, #effects)])
    elseif roll <= 62 then
      local base = weaponBases[rng:range(1, #weaponBases)]
      item = Affixes.decorate(Items.weapon(base.name, base.power), Affixes.rollWeapon(rng))
    elseif roll <= 75 then
      local base = armorBases[rng:range(1, #armorBases)]
      item = Affixes.decorate(Items.armor(base.name, base.power), Affixes.rollArmor(rng))
    elseif roll <= 85 then
      item = Items.ring("ring of the merchant", rng:range(0, 2), rng:range(0, 2))
    else
      local key = Mercenaries.order[rng:range(1, #Mercenaries.order)]
      item = Items.contract(key, "contract: hire the " .. Mercenaries.byKey[key].name)
    end
    wares[#wares + 1] = item
  end
  return wares
end

return Shop
