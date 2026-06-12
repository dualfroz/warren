-- One dungeon floor: its map plus the mutable contents that live on it -
-- monsters, dropped items, traps, light emitters and what the player has
-- explored. Levels are cached by the dungeon so revisiting one restores its
-- exact state, dead monsters and all.

local Map = require("map")
local Entity = require("entity")

local Level = {}
Level.__index = Level

function Level.new(fields)
  return setmetatable({
    depth = fields.depth,
    generator = fields.generator,
    map = fields.map,
    entities = fields.entities or {},
    floorItems = fields.floorItems or {},
    traps = fields.traps or {},
    lights = fields.lights or {},
    dark = fields.dark or false,
    explored = fields.explored or {},
    upX = fields.upX, upY = fields.upY,
    downX = fields.downX, downY = fields.downY,
  }, Level)
end

function Level:entityAt(x, y)
  for _, monster in ipairs(self.entities) do
    if monster:isAlive() and monster.x == x and monster.y == y then
      return monster
    end
  end
  return nil
end

function Level:trapAt(x, y)
  for _, trap in ipairs(self.traps) do
    if trap.x == x and trap.y == y then return trap end
  end
  return nil
end

function Level:itemsAt(x, y)
  local here = {}
  for _, ground in ipairs(self.floorItems) do
    if ground.x == x and ground.y == y then here[#here + 1] = ground end
  end
  return here
end

function Level:removeDead()
  for i = #self.entities, 1, -1 do
    if not self.entities[i]:isAlive() then
      table.remove(self.entities, i)
    end
  end
end

function Level:markExplored(idx)
  self.explored[idx] = true
end

function Level:toData()
  local monsters = {}
  for i, monster in ipairs(self.entities) do
    monsters[i] = monster:toData()
  end
  local explored = {}
  for idx in pairs(self.explored) do
    explored[#explored + 1] = idx
  end
  table.sort(explored)
  return {
    depth = self.depth,
    generator = self.generator,
    map = self.map:toData(),
    entities = monsters,
    floorItems = self.floorItems,
    traps = self.traps,
    lights = self.lights,
    dark = self.dark,
    explored = explored,
    upX = self.upX, upY = self.upY,
    downX = self.downX, downY = self.downY,
  }
end

function Level.fromData(snapshot)
  local entities = {}
  for i, monsterData in ipairs(snapshot.entities) do
    entities[i] = Entity.fromData(monsterData)
  end
  local explored = {}
  for _, idx in ipairs(snapshot.explored) do
    explored[idx] = true
  end
  return Level.new({
    depth = snapshot.depth,
    generator = snapshot.generator,
    map = Map.fromData(snapshot.map),
    entities = entities,
    floorItems = snapshot.floorItems,
    traps = snapshot.traps,
    lights = snapshot.lights,
    dark = snapshot.dark,
    explored = explored,
    upX = snapshot.upX, upY = snapshot.upY,
    downX = snapshot.downX, downY = snapshot.downY,
  })
end

return Level
