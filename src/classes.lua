-- Player classes. A class is chosen once at character creation (Game.new
-- options.class) and never changes; it grants a one-time stat or kit delta
-- and, through skills.lua, gates which skills the player is allowed to spend
-- points on. Classless play (no options.class given) is unaffected - every
-- class delta is opt-in so existing unclassed games keep their exact stats.

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

-- Applies the one-time delta for `key` to a freshly created player. Must run
-- after the player's base stats, mana pool and starting inventory are all in
-- place, since every delta is additive on top of whatever is already there.
function Classes.apply(player, key)
  local def = Classes.defs[key]
  if not def then return false end
  player.class = key
  def.apply(player)
  return true
end

return Classes
