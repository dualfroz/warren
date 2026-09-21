local Items = require("items")

local Classes = {}

Classes.order = { "fighter", "rogue", "mage", "ranger" }

Classes.defs = {
  fighter = {
    name = "fighter",
    apply = function(player)
      player.maxHp = player.maxHp + 8
      player.hp = player.hp + 8
      player.attack = player.attack + 2
      player.baseAttack = player.baseAttack + 2
    end,
  },
  rogue = {
    name = "rogue",
    apply = function(player)
      player.gold = player.gold + 15
      player.attack = player.attack + 1
      player.baseAttack = player.baseAttack + 1
    end,
  },
  mage = {
    name = "mage",
    apply = function(player)
      player.maxMana = player.maxMana + 8
      player.mana = player.mana + 8
      player.attack = player.attack - 1
      player.baseAttack = player.baseAttack - 1
    end,
  },
  ranger = {
    name = "ranger",
    apply = function(player)
      Items.equipBow(Items.bow("shortbow", 3, 6), player)
      player.inventory[#player.inventory + 1] = Items.ammo("arrow", 12)
    end,
  },
}

function Classes.isValid(key)
  return Classes.defs[key] ~= nil
end

function Classes.apply(player, key)
  local def = Classes.defs[key]
  if not def then return false end
  player.class = key
  def.apply(player)
  return true
end

return Classes
