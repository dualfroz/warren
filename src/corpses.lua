-- Raw meat left behind by a fallen wild monster - a second, turn-costed food
-- source alongside a found or bought ration (see Items.food, shop.lua). A
-- corpse decays over a fixed number of rounds whether or not the player is
-- even on this floor to see it (Corpses.step runs off Game:endPlayerTurn
-- exactly like hazards.lua's fire/gas and nodes.lua's vein cooldown); left
-- alone past its rot threshold it still butchers in one stroke, but the
-- reward turns from a meal into a bout of poisoning instead. Undead crumble
-- to dust and leave nothing to carve (see factions.lua's UNDEAD tag), a mimic
-- was never alive to begin with (mimics.lua), and a boss's fixed loot drop
-- (bosses.lua) is reward enough on its own - none of the three spawn a
-- corpse. Corpses are plain data on level.corpses, exactly like
-- level.hazards and level.nodes, so they serialize with no special
-- save-format handling.

local Factions = require("factions")
local Items = require("items")
local Status = require("status")

local Corpses = {}

Corpses.DECAY_TURNS = 60
Corpses.ROT_TURNS = 25

Corpses.NUTRITION_MIN = 30
Corpses.NUTRITION_MAX = 200
Corpses.NUTRITION_PER_HP = 8

-- Wild monster corpses only: the undead were already dead before the player
-- got there, a mimic's "corpse" would just be its loot disguise falling
-- apart, and a boss's own scripted drop already covers its reward.
function Corpses.leavesCorpse(target)
  return target.faction ~= Factions.UNDEAD and not target.mimic and not target.isBoss
end

-- Nutrition scales with how tough the felled species was (maxHp, itself
-- depth-scaled per monsters.lua), clamped to a fixed band so a late-game
-- dragon corpse never trivializes hunger outright.
local function nutritionFor(maxHp)
  local raw = maxHp * Corpses.NUTRITION_PER_HP
  return math.max(Corpses.NUTRITION_MIN, math.min(Corpses.NUTRITION_MAX, raw))
end

function Corpses.new(target)
  return {
    x = target.x, y = target.y,
    species = target.species, name = target.name,
    nutrition = nutritionFor(target.maxHp),
    decay = Corpses.DECAY_TURNS,
  }
end

-- Appends a fresh corpse for `target` onto `level.corpses`, or does nothing
-- for anything Corpses.leavesCorpse rules out.
function Corpses.spawn(level, target)
  if not Corpses.leavesCorpse(target) then return end
  level.corpses[#level.corpses + 1] = Corpses.new(target)
end

function Corpses.isRotten(corpse)
  return corpse.decay <= Corpses.ROT_TURNS
end

-- Advances every corpse on the level one round toward fully rotting away,
-- exactly like hazards.step and nodes.step - called once per round, not per
-- actor, so a seeded run always loses a given corpse on the identical turn
-- regardless of how many actors acted that round.
function Corpses.step(level)
  for i = #level.corpses, 1, -1 do
    local corpse = level.corpses[i]
    corpse.decay = corpse.decay - 1
    if corpse.decay <= 0 then table.remove(level.corpses, i) end
  end
end

-- Drops `corpse` off level.corpses outright - shared by every way of
-- spending one (see Corpses.butcher below and scavenging.lua's own harvest),
-- so a corpse can never be carved twice over.
function Corpses.remove(level, corpse)
  for i, candidate in ipairs(level.corpses) do
    if candidate == corpse then
      table.remove(level.corpses, i)
      return
    end
  end
end

-- Carves up `corpse` in one stroke, always spending it whether the meat is
-- still good or not. A corpse still inside its rot threshold yields a fresh
-- Items.food ration into the player's inventory, eaten later exactly like a
-- found one; a corpse butchered past that threshold instead poisons the
-- player outright - the corpse itself is just as gone either way.
function Corpses.butcher(game, corpse)
  Corpses.remove(game.level, corpse)
  if Corpses.isRotten(corpse) then
    Status.apply(game.player, Status.POISON, 5, 2)
    return string.format("the %s corpse has rotted; you gag it down and immediately regret it", corpse.name)
  end
  local food = Items.food(corpse.name .. " meat", corpse.nutrition)
  game.player.inventory[#game.player.inventory + 1] = food
  return string.format("you carve %d nutrition worth of meat from the %s corpse", corpse.nutrition, corpse.name)
end

return Corpses
