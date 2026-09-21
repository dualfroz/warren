local Factions = require("factions")
local Items = require("items")
local Status = require("status")

local Corpses = {}

Corpses.DECAY_TURNS = 60
Corpses.ROT_TURNS = 25

Corpses.NUTRITION_MIN = 30
Corpses.NUTRITION_MAX = 200
Corpses.NUTRITION_PER_HP = 8

function Corpses.leavesCorpse(target)
  return target.faction ~= Factions.UNDEAD and not target.mimic and not target.isBoss
end

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

function Corpses.spawn(level, target)
  if not Corpses.leavesCorpse(target) then return end
  level.corpses[#level.corpses + 1] = Corpses.new(target)
end

function Corpses.isRotten(corpse)
  return corpse.decay <= Corpses.ROT_TURNS
end

function Corpses.step(level)
  for i = #level.corpses, 1, -1 do
    local corpse = level.corpses[i]
    corpse.decay = corpse.decay - 1
    if corpse.decay <= 0 then table.remove(level.corpses, i) end
  end
end

function Corpses.remove(level, corpse)
  for i, candidate in ipairs(level.corpses) do
    if candidate == corpse then
      table.remove(level.corpses, i)
      return
    end
  end
end

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
