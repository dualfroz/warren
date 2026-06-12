-- Turn orchestration built on an energy scheduler: the world advances actor by
-- actor until the player is due, the player acts, and the cycle repeats. Owns
-- the dungeon, the player, identification and the message log, and drives the
-- headless autopilot that descends the dungeon deterministically.

local Rng = require("rng")
local Tiles = require("tiles")
local Astar = require("astar")
local Los = require("los")
local Light = require("light")
local Combat = require("combat")
local Items = require("items")
local Effects = require("effects")
local Status = require("status")
local Identify = require("identify")
local Dungeon = require("dungeon")
local Entity = require("entity")
local MessageLog = require("messagelog")
local Scheduler = require("scheduler")
local Ai = require("ai")
local Serialize = require("serialize")
local Render = require("render")

local Game = {}
Game.__index = Game

local FOV_RADIUS = 8

local function sign(n)
  if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end
end

function Game.new(seed)
  local game = setmetatable({}, Game)
  game.seed = seed
  game.rng = Rng.new(seed)
  game.depth = 1
  game.turn = 0
  game.log = MessageLog.new(32)
  game.identify = Identify.new(game.rng)
  game.dungeon = Dungeon.new(seed)
  game.level = game.dungeon:get(1)
  game.player = Entity.new({
    id = 0, x = game.level.upX, y = game.level.upY,
    glyph = "@", name = "you", kind = "player",
    hp = 30, maxHp = 30, attack = 5, defense = 1, speed = 100,
  })
  game.player.satiation = 1000
  game.player.light = { fuel = 400, radius = 8 }
  game.player.inventory = {
    Items.potion(10), Items.potion(10), Items.food("ration", 400), Items.scroll("mapping"),
  }
  game.visible = {}
  game:computeVisible()
  return game
end

function Game:currentEntities()
  return self.level.entities
end

function Game:effectiveRadius()
  if not self.level.dark then return FOV_RADIUS end
  if self.player.light.fuel > 0 then return self.player.light.radius end
  return 2
end

function Game:computeVisible()
  self.visible = Light.compute(self.level.map, self.player.x, self.player.y,
    self:effectiveRadius(), self.level.lights)
  for idx in pairs(self.visible) do
    self.level:markExplored(idx)
  end
end

function Game:cleanupDead()
  self.level:removeDead()
end

function Game:hasKey()
  for _, item in ipairs(self.player.inventory) do
    if item.kind == Items.KEY then return true end
  end
  return false
end

function Game:randomFloorCell()
  local map = self.level.map
  local cells = {}
  for y = 1, map.height do
    for x = 1, map.width do
      if map:isWalkable(x, y) and not self.level:entityAt(x, y)
        and not (x == self.player.x and y == self.player.y) then
        cells[#cells + 1] = { x = x, y = y }
      end
    end
  end
  if #cells == 0 then return nil end
  local pick = cells[self.rng:range(1, #cells)]
  return pick.x, pick.y
end

function Game:revealWholeLevel()
  local map = self.level.map
  for idx = 1, map.width * map.height do
    self.level:markExplored(idx)
  end
end

-- Monster-turn helpers used by the ai module.

function Game:playerAdjacent(monster)
  return math.abs(monster.x - self.player.x) + math.abs(monster.y - self.player.y) == 1
end

function Game:canSeePlayer(monster, range)
  local cheb = math.max(math.abs(monster.x - self.player.x), math.abs(monster.y - self.player.y))
  if cheb > range then return false end
  return Los.clear(self.level.map, monster.x, monster.y, self.player.x, self.player.y)
end

function Game:hasClearShot(monster)
  return Los.clear(self.level.map, monster.x, monster.y, self.player.x, self.player.y)
end

function Game:monsterMelee(monster)
  local outcome = Combat.attack(monster, self.player)
  self.log:add(string.format("%s hits you for %d", monster.name, outcome.damage))
end

function Game:monsterShoot(monster)
  local dealt = Combat.damage(monster, self.player)
  self.player.hp = self.player.hp - dealt
  self.log:add(string.format("%s shoots you for %d", monster.name, dealt))
end

local function blockedForMonster(game, self, goalX, goalY)
  return function(x, y)
    if x == goalX and y == goalY then return false end
    if not game.level.map:isWalkable(x, y) then return true end
    if x == game.player.x and y == game.player.y then return true end
    local occupant = game.level:entityAt(x, y)
    return occupant ~= nil and occupant ~= self
  end
end

function Game:stepMonsterToward(monster, tx, ty)
  local path = Astar.find(self.level.map, monster.x, monster.y, tx, ty,
    blockedForMonster(self, monster, tx, ty))
  if path and #path >= 2 then
    local step = path[2]
    if self.level.map:isWalkable(step.x, step.y) and not self.level:entityAt(step.x, step.y)
      and not (step.x == self.player.x and step.y == self.player.y) then
      monster.x, monster.y = step.x, step.y
    end
  end
end

local MONSTER_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Game:stepMonsterAway(monster, tx, ty)
  local current = math.abs(monster.x - tx) + math.abs(monster.y - ty)
  local best, bx, by = current, nil, nil
  for _, dir in ipairs(MONSTER_DIRS) do
    local nx, ny = monster.x + dir[1], monster.y + dir[2]
    if self.level.map:isWalkable(nx, ny) and not self.level:entityAt(nx, ny)
      and not (nx == self.player.x and ny == self.player.y) then
      local dist = math.abs(nx - tx) + math.abs(ny - ty)
      if dist > best then
        best, bx, by = dist, nx, ny
      end
    end
  end
  if bx then monster.x, monster.y = bx, by end
end

function Game:moveMonster(monster, dx, dy)
  local nx, ny = monster.x + dx, monster.y + dy
  if nx == self.player.x and ny == self.player.y then
    self:monsterMelee(monster)
  elseif self.level.map:isWalkable(nx, ny) and not self.level:entityAt(nx, ny) then
    monster.x, monster.y = nx, ny
  end
end

function Game:nearestAlly(monster)
  local best, ally = math.huge, nil
  for _, other in ipairs(self.level.entities) do
    if other ~= monster and other:isAlive() then
      local dist = math.abs(other.x - monster.x) + math.abs(other.y - monster.y)
      if dist < best or (dist == best and ally and other.id < ally.id) then
        best, ally = dist, other
      end
    end
  end
  return ally
end

function Game:takeMonsterTurn(monster)
  self.log:addAll(Status.tick(monster))
  if not monster:isAlive() then
    self:cleanupDead()
    return
  end
  if not Status.skipsTurn(monster) then
    Ai.act(self, monster)
  end
  Scheduler.spend(monster)
  self:cleanupDead()
end

function Game:runToPlayer()
  while true do
    local actor = Scheduler.next(self)
    if actor == nil or actor == self.player then return end
    self:takeMonsterTurn(actor)
    if not self.player:isAlive() then return end
  end
end

-- Player actions.

function Game:playerAttack(target)
  local outcome = Combat.attack(self.player, target)
  self.log:add(string.format("you hit %s for %d", target.name, outcome.damage))
  local weapon = self.player.weapon
  if weapon and weapon.affix and weapon.affix.onHit and target:isAlive() then
    local rider = weapon.affix.onHit
    Status.apply(target, rider.status, rider.duration, rider.potency)
    self.log:add(string.format("%s is %s", target.name, rider.status))
  end
  if outcome.killed then
    self.log:add(target.name .. " dies")
    self:cleanupDead()
  end
end

function Game:openDoor(x, y)
  local map = self.level.map
  if map:get(x, y) == Tiles.DOOR_LOCKED then
    for i, item in ipairs(self.player.inventory) do
      if item.kind == Items.KEY then
        table.remove(self.player.inventory, i)
        map:set(x, y, Tiles.DOOR_OPEN)
        self.log:add("you unlock the door")
        return true
      end
    end
    self.log:add("the door is locked")
    return true
  end
  map:set(x, y, Tiles.DOOR_OPEN)
  self.log:add("you open the door")
  return true
end

function Game:triggerTrap(trap)
  trap.revealed = true
  self.level.map:set(trap.x, trap.y, Tiles.TRAP)
  if trap.effect == "dart" then
    local dmg = 3 + self.depth // 2
    self.player.hp = self.player.hp - dmg
    self.log:add(string.format("a dart trap hits you for %d", dmg))
  elseif trap.effect == "poison" then
    Status.apply(self.player, Status.POISON, 5, 2)
    self.log:add("you stumble into a poison trap")
  else
    local x, y = self:randomFloorCell()
    if x then
      self.player.x, self.player.y = x, y
      self.log:add("a trap flings you across the level")
    end
  end
end

function Game:pickupHere()
  for i = #self.level.floorItems, 1, -1 do
    local ground = self.level.floorItems[i]
    if ground.x == self.player.x and ground.y == self.player.y then
      self.player.inventory[#self.player.inventory + 1] = ground.item
      self.log:add("you pick up " .. Identify.label(self.identify, ground.item))
      table.remove(self.level.floorItems, i)
    end
  end
end

function Game:movePlayer(dx, dy)
  local nx, ny = self.player.x + dx, self.player.y + dy
  local map = self.level.map
  if Tiles.isClosedDoor(map:get(nx, ny)) then
    return self:openDoor(nx, ny)
  end
  local target = self.level:entityAt(nx, ny)
  if target then
    self:playerAttack(target)
    return true
  end
  if map:isWalkable(nx, ny) then
    self.player.x, self.player.y = nx, ny
    local trap = self.level:trapAt(nx, ny)
    if trap and not trap.revealed then self:triggerTrap(trap) end
    self:pickupHere()
    return true
  end
  return false
end

function Game:useItem(index)
  local item = self.player.inventory[index]
  if not item then return false end
  if item.kind == Items.POTION or item.kind == Items.SCROLL then
    self.log:addAll(Effects.apply(item.effect, self, self.player, item))
    Identify.reveal(self.identify, item)
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.FOOD then
    self.player.satiation = self.player.satiation + item.nutrition
    self.log:add("you eat the " .. item.name)
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.WEAPON or item.kind == Items.ARMOR or item.kind == Items.RING then
    Items.useFromInventory(self.player, index)
    self.log:add("you equip " .. Identify.label(self.identify, item))
  else
    return false
  end
  return true
end

function Game:descend()
  if self.player.x ~= self.level.downX or self.player.y ~= self.level.downY then return false end
  self.depth = self.depth + 1
  self.level = self.dungeon:get(self.depth)
  self.player.x, self.player.y = self.level.upX, self.level.upY
  self.log:add("you descend to depth " .. self.depth)
  self:computeVisible()
  return true
end

function Game:ascend()
  if self.player.x ~= self.level.upX or self.player.y ~= self.level.upY then return false end
  if self.depth <= 1 then
    self.log:add("you climb toward the surface")
    return true
  end
  self.depth = self.depth - 1
  self.level = self.dungeon:get(self.depth)
  self.player.x, self.player.y = self.level.downX, self.level.downY
  self.log:add("you climb to depth " .. self.depth)
  self:computeVisible()
  return true
end

-- Autopilot.

function Game:findInInventory(predicate)
  for i, item in ipairs(self.player.inventory) do
    if predicate(item) then return i end
  end
  return nil
end

function Game:adjacentMonster()
  for _, dir in ipairs(MONSTER_DIRS) do
    local monster = self.level:entityAt(self.player.x + dir[1], self.player.y + dir[2])
    if monster then return monster end
  end
  return nil
end

function Game:playerPathTo(tx, ty)
  local hasKey = self:hasKey()
  return Astar.find(self.level.map, self.player.x, self.player.y, tx, ty, function(x, y)
    if x == tx and y == ty then return false end
    if not self.level.map:isPassable(x, y, hasKey) then return true end
    return self.level:entityAt(x, y) ~= nil
  end)
end

-- First step of the shortest route to the nearest monster the player can
-- actually reach, so blockers standing between the player and the stairs get
-- hunted down. Ties break on ascending monster id for determinism.
function Game:reachableMonsterStep()
  local bestLen, bestId, step = math.huge, math.huge, nil
  for _, monster in ipairs(self.level.entities) do
    local path = self:playerPathTo(monster.x, monster.y)
    if path and #path >= 2 then
      if #path < bestLen or (#path == bestLen and monster.id < bestId) then
        bestLen, bestId, step = #path, monster.id, path[2]
      end
    end
  end
  return step
end

-- First step toward the nearest not-yet-explored walkable cell via a BFS that
-- routes around monsters. Lets the autopilot discover a way onward when the
-- direct path to the stairs is temporarily blocked.
function Game:exploreStep()
  local map = self.level.map
  local hasKey = self:hasKey()
  local start = map:index(self.player.x, self.player.y)
  local came = { [start] = start }
  local queue = { { self.player.x, self.player.y, start } }
  local head = 1
  while head <= #queue do
    local cell = queue[head]
    head = head + 1
    local cx, cy, idx = cell[1], cell[2], cell[3]
    if idx ~= start and not self.level.explored[idx] and map:isWalkable(cx, cy) then
      local cursor = idx
      while came[cursor] ~= start do
        cursor = came[cursor]
      end
      local stepX = (cursor - 1) % map.width + 1
      local stepY = (cursor - 1) // map.width + 1
      return sign(stepX - self.player.x), sign(stepY - self.player.y)
    end
    for _, dir in ipairs(MONSTER_DIRS) do
      local nx, ny = cx + dir[1], cy + dir[2]
      if map:inBounds(nx, ny) and map:isPassable(nx, ny, hasKey)
        and not self.level:entityAt(nx, ny) then
        local nIdx = map:index(nx, ny)
        if not came[nIdx] then
          came[nIdx] = idx
          queue[#queue + 1] = { nx, ny, nIdx }
        end
      end
    end
  end
  return nil
end

function Game:anyMonsterVisible()
  for _, monster in ipairs(self.level.entities) do
    if self.visible[self.level.map:index(monster.x, monster.y)] then return true end
  end
  return false
end

-- Inventory index of the single best equipment upgrade to put on this turn, or
-- nil. Weapons and armour compare on power, rings on attack plus defence.
function Game:bestUpgrade()
  local player = self.player
  local weaponPower = player.weapon and player.weapon.power or 0
  local armorPower = player.armor and player.armor.power or 0
  local ringValue = player.ring and (player.ring.attack + player.ring.defense) or 0
  for i, item in ipairs(player.inventory) do
    if item.kind == Items.WEAPON and item.power > weaponPower then return i end
  end
  for i, item in ipairs(player.inventory) do
    if item.kind == Items.ARMOR and item.power > armorPower then return i end
  end
  for i, item in ipairs(player.inventory) do
    if item.kind == Items.RING and (item.attack + item.defense) > ringValue then return i end
  end
  return nil
end

function Game:choosePlayerAction()
  local player = self.player
  if not self:anyMonsterVisible() then
    local upgrade = self:bestUpgrade()
    if upgrade then self:useItem(upgrade); return end
  end
  if player.hp < player.maxHp // 3 then
    local potion = self:findInInventory(function(item)
      return item.kind == Items.POTION and item.effect == "heal"
    end)
    if potion then self:useItem(potion); return end
  end
  if player.satiation < 150 then
    local food = self:findInInventory(function(item) return item.kind == Items.FOOD end)
    if food then self:useItem(food); return end
  end
  local target = self:adjacentMonster()
  if target then
    self:movePlayer(sign(target.x - player.x), sign(target.y - player.y))
    return
  end
  if player.x == self.level.downX and player.y == self.level.downY then
    self:descend()
    return
  end
  local path = self:playerPathTo(self.level.downX, self.level.downY)
  if path and #path >= 2 then
    self:movePlayer(path[2].x - player.x, path[2].y - player.y)
    return
  end
  local hunt = self:reachableMonsterStep()
  if hunt then
    self:movePlayer(hunt.x - player.x, hunt.y - player.y)
    return
  end
  local ex, ey = self:exploreStep()
  if ex then self:movePlayer(ex, ey) end
end

function Game:hungerTorchTick()
  self.player.satiation = self.player.satiation - 1
  if self.player.satiation <= 0 then
    self.player.satiation = 0
    self.player.hp = self.player.hp - 1
    self.log:add("you are starving")
  end
  if self.player.light.fuel > 0 then
    self.player.light.fuel = self.player.light.fuel - 1
  end
end

function Game:endPlayerTurn()
  Scheduler.spend(self.player)
  self:hungerTorchTick()
  self.turn = self.turn + 1
  self:computeVisible()
end

function Game:autoStep()
  self:runToPlayer()
  if not self.player:isAlive() then return end
  self.log:addAll(Status.tick(self.player))
  if not self.player:isAlive() then return end
  if Status.skipsTurn(self.player) then
    self.log:add("you are stunned")
  else
    self:choosePlayerAction()
  end
  self:endPlayerTurn()
end

function Game:render()
  return Render.frame(self)
end

function Game:toData()
  return {
    seed = self.seed,
    depth = self.depth,
    turn = self.turn,
    rng = self.rng:serialize(),
    identify = self.identify,
    dungeon = self.dungeon:toData(),
    player = self.player:toData(),
    playerExtra = { satiation = self.player.satiation, light = self.player.light },
    log = self.log:toData(),
  }
end

function Game.fromData(snapshot)
  local game = setmetatable({}, Game)
  game.seed = snapshot.seed
  game.depth = snapshot.depth
  game.turn = snapshot.turn
  game.rng = Rng.deserialize(snapshot.rng)
  game.identify = snapshot.identify
  game.dungeon = Dungeon.fromData(snapshot.dungeon)
  game.level = game.dungeon:get(game.depth)
  game.player = Entity.fromData(snapshot.player)
  game.player.satiation = snapshot.playerExtra.satiation
  game.player.light = snapshot.playerExtra.light
  game.log = MessageLog.fromData(snapshot.log)
  game.visible = {}
  game:computeVisible()
  return game
end

function Game:save(path)
  Serialize.saveFile(path, self:toData())
end

function Game.load(path)
  return Game.fromData(Serialize.loadFile(path))
end

return Game
