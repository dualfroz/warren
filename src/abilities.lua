local Status = require("status")
local Items = require("items")
local Los = require("los")
local Combat = require("combat")
local Durability = require("durability")
local Momentum = require("momentum")
local Text = require("text")

local Abilities = {}

function Abilities.regenTick(monster)
  local amount = monster.regen
  if not amount or not monster:isAlive() then return nil end
  if Status.has(monster, Status.BURNING) then return nil end
  local before = monster.hp
  monster.hp = math.min(monster.maxHp, monster.hp + amount)
  if monster.hp == before then return nil end
  return string.format("%s knits its wounds for %d", monster.name, monster.hp - before)
end

local bursts = {
  spores = function(game, monster)
    local hit = {}
    local targets = { game.player }
    for _, other in ipairs(game:currentEntities()) do targets[#targets + 1] = other end
    for _, victim in ipairs(targets) do
      if victim ~= monster and victim:isAlive()
        and math.abs(victim.x - monster.x) <= 1 and math.abs(victim.y - monster.y) <= 1 then
        Status.apply(victim, Status.POISON, 4, 2)
        hit[#hit + 1] = victim.name
      end
    end
    if #hit == 0 then return nil end
    return string.format("a burst of spores poisons %s", Text.joinNaturally(hit))
  end,
}

function Abilities.onDeath(game, monster)
  local burst = monster.onDeath and bursts[monster.onDeath]
  if not burst then return nil end
  return burst(game, monster)
end

local RANGE = { summon = 6, curse = 5, heal = 5, shriek = 5 }
local COOLDOWN = { summon = 6, curse = 4, heal = 5, rally = 8, shriek = 6 }
local MAX_SUMMONED = 2

local EIGHT_DIRS = {
  { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
  { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

local function freeAdjacent(game, x, y)
  for _, dir in ipairs(EIGHT_DIRS) do
    local nx, ny = x + dir[1], y + dir[2]
    if game.level.map:isWalkable(nx, ny) and not game.level:entityAt(nx, ny)
      and not (nx == game.player.x and ny == game.player.y) then
      return nx, ny
    end
  end
  return nil
end

function Abilities.tickCooldown(monster)
  if monster.cooldown and monster.cooldown > 0 then
    monster.cooldown = monster.cooldown - 1
  end
end

local function trySummon(game, monster)
  if not game:canSeePlayer(monster, RANGE.summon) then return false end
  local count = 0
  for _, other in ipairs(game.level.entities) do
    if other:isAlive() and other.summonedBy == monster.id then count = count + 1 end
  end
  if count >= MAX_SUMMONED then return false end
  local x, y = freeAdjacent(game, monster.x, monster.y)
  if not x then return false end
  local minion = game:spawnMinion(monster.summonSpecies, x, y)
  minion.summonedBy = monster.id
  monster.cooldown = COOLDOWN.summon
  return true, string.format("%s calls forth a %s", monster.name, minion.name)
end

local function tryCurse(game, monster)
  if game:playerAdjacent(monster) then return false end
  if not game:canSeePlayer(monster, RANGE.curse) or not game:hasClearShot(monster) then
    return false
  end
  local dealt = Combat.damage(monster, game.player, 1)
  game.player.hp = game.player.hp - dealt
  Momentum.onDamaged(game.player)
  local broke = Durability.wearArmor(game.player)
  if broke then game.log:add(broke) end
  Status.apply(game.player, Status.WEAKEN, 6, 3)
  monster.cooldown = COOLDOWN.curse
  return true, string.format("%s curses you for %d", monster.name, dealt)
end

local function tryShriek(game, monster)
  if game:playerAdjacent(monster) then return false end
  if not game:canSeePlayer(monster, RANGE.shriek) or not game:hasClearShot(monster) then
    return false
  end
  Status.apply(game.player, Status.BLIND, 5, 1)
  monster.cooldown = COOLDOWN.shriek
  return true, string.format("%s's wail blinds you", monster.name)
end

local function tryHeal(game, monster)
  local best, bestRatio = nil, 1
  for _, other in ipairs(game.level.entities) do
    if other ~= monster and other.kind == "monster" and other:isAlive() and other.hp < other.maxHp then
      local dist = math.max(math.abs(other.x - monster.x), math.abs(other.y - monster.y))
      if dist <= RANGE.heal and Los.clear(game.level.map, monster.x, monster.y, other.x, other.y) then
        local ratio = other.hp / other.maxHp
        if ratio < bestRatio then bestRatio, best = ratio, other end
      end
    end
  end
  if not best then return false end
  local amount = 6
  local before = best.hp
  best.hp = math.min(best.maxHp, best.hp + amount)
  monster.cooldown = COOLDOWN.heal
  return true, string.format("%s mends %s for %d", monster.name, best.name, best.hp - before)
end

local function tryRally(game, monster)
  local buffed = {}
  for _, other in ipairs(game.level.entities) do
    if other ~= monster and other.kind == "monster" and other:isAlive() and not Status.has(other, Status.STRENGTH)
      and math.abs(other.x - monster.x) <= 1 and math.abs(other.y - monster.y) <= 1 then
      Status.apply(other, Status.STRENGTH, 10, 2)
      buffed[#buffed + 1] = other.name
    end
  end
  if #buffed == 0 then return false end
  Status.apply(monster, Status.STRENGTH, 10, 2)
  monster.cooldown = COOLDOWN.rally
  return true, string.format("%s rallies %s", monster.name, Text.joinNaturally(buffed))
end

local function trySteal(game, monster)
  if monster.fleeing then
    game:stepMonsterAway(monster, game.player.x, game.player.y)
    return true
  end
  if not game:playerAdjacent(monster) then return false end
  local idx = game:findInInventory(function(item)
    return item.kind ~= Items.KEY and item.kind ~= Items.AMULET
  end)
  if not idx then
    monster.fleeing = true
    return true, string.format("%s finds nothing worth stealing and flees", monster.name)
  end
  local item = table.remove(game.player.inventory, idx)
  monster.stolen = item
  monster.fleeing = true
  return true, string.format("%s steals your %s and flees", monster.name, item.name)
end

local dispatch = { summon = trySummon, curse = tryCurse, heal = tryHeal, rally = tryRally, shriek = tryShriek }

function Abilities.tryAct(game, monster)
  if not monster.ability then return false end
  if monster.ability == "steal" then
    local acted, line = trySteal(game, monster)
    if acted and line then game.log:add(line) end
    return acted == true
  end
  local handler = dispatch[monster.ability]
  if not handler or (monster.cooldown and monster.cooldown > 0) then return false end
  local acted, line = handler(game, monster)
  if not acted then return false end
  if line then game.log:add(line) end
  return true
end

function Abilities.onHit(game, target)
  if target.ability ~= "split" then return nil end
  if not target:isAlive() or target.maxHp < 4 then return nil end
  if (target.splitGen or 0) >= 2 then return nil end
  local x, y = freeAdjacent(game, target.x, target.y)
  if not x then return nil end
  local newMax = target.maxHp // 2
  target.maxHp = newMax
  target.hp = math.min(target.hp, newMax)
  target.splitGen = (target.splitGen or 0) + 1
  local clone = game:spawnMinion(target.species, x, y)
  clone.maxHp = newMax
  clone.hp = newMax
  clone.splitGen = target.splitGen
  return string.format("the %s splits in two", target.name)
end

return Abilities
