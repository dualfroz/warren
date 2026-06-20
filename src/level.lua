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
    hazards = fields.hazards or {},
    shrines = fields.shrines or {},
    questBoards = fields.questBoards or {},
    cauldrons = fields.cauldrons or {},
    nodes = fields.nodes or {},
    corpses = fields.corpses or {},
    chests = fields.chests or {},
    captives = fields.captives or {},
    vaultLevers = fields.vaultLevers or {},
    vaultDoors = fields.vaultDoors or {},
    secretDoors = fields.secretDoors or {},
    blocks = fields.blocks or {},
    plates = fields.plates or {},
    gates = fields.gates or {},
    prefabVaults = fields.prefabVaults or {},
    rifts = fields.rifts or {},
    weather = fields.weather,
    biome = fields.biome,
    event = fields.event,
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

function Level:entityById(id)
  for _, entity in ipairs(self.entities) do
    if entity.id == id then return entity end
  end
  return nil
end

function Level:trapAt(x, y)
  for _, trap in ipairs(self.traps) do
    if trap.x == x and trap.y == y then return trap end
  end
  return nil
end

function Level:shrineAt(x, y)
  for _, shrine in ipairs(self.shrines) do
    if shrine.x == x and shrine.y == y then return shrine end
  end
  return nil
end

function Level:questBoardAt(x, y)
  for _, board in ipairs(self.questBoards) do
    if board.x == x and board.y == y then return board end
  end
  return nil
end

function Level:cauldronAt(x, y)
  for _, cauldron in ipairs(self.cauldrons) do
    if cauldron.x == x and cauldron.y == y then return cauldron end
  end
  return nil
end

function Level:nodeAt(x, y)
  for _, node in ipairs(self.nodes) do
    if node.x == x and node.y == y then return node end
  end
  return nil
end

function Level:corpseAt(x, y)
  for _, corpse in ipairs(self.corpses) do
    if corpse.x == x and corpse.y == y then return corpse end
  end
  return nil
end

function Level:chestAt(x, y)
  for _, chest in ipairs(self.chests) do
    if chest.x == x and chest.y == y then return chest end
  end
  return nil
end

function Level:captiveAt(x, y)
  for _, captive in ipairs(self.captives) do
    if captive.x == x and captive.y == y then return captive end
  end
  return nil
end

function Level:vaultLeverAt(x, y)
  for _, lever in ipairs(self.vaultLevers) do
    if lever.x == x and lever.y == y then return lever end
  end
  return nil
end

function Level:blockAt(x, y)
  for _, block in ipairs(self.blocks) do
    if block.x == x and block.y == y then return block end
  end
  return nil
end

function Level:plateAt(x, y)
  for _, plate in ipairs(self.plates) do
    if plate.x == x and plate.y == y then return plate end
  end
  return nil
end

function Level:gateAt(x, y)
  for _, gate in ipairs(self.gates) do
    if gate.x == x and gate.y == y then return gate end
  end
  return nil
end

function Level:riftAt(x, y)
  for _, rift in ipairs(self.rifts) do
    if rift.x == x and rift.y == y then return rift end
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
    hazards = self.hazards,
    shrines = self.shrines,
    questBoards = self.questBoards,
    cauldrons = self.cauldrons,
    nodes = self.nodes,
    corpses = self.corpses,
    chests = self.chests,
    captives = self.captives,
    vaultLevers = self.vaultLevers,
    vaultDoors = self.vaultDoors,
    secretDoors = self.secretDoors,
    blocks = self.blocks,
    plates = self.plates,
    gates = self.gates,
    prefabVaults = self.prefabVaults,
    rifts = self.rifts,
    weather = self.weather,
    biome = self.biome,
    event = self.event,
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
    hazards = snapshot.hazards,
    shrines = snapshot.shrines,
    questBoards = snapshot.questBoards,
    cauldrons = snapshot.cauldrons,
    nodes = snapshot.nodes,
    corpses = snapshot.corpses,
    chests = snapshot.chests,
    captives = snapshot.captives,
    vaultLevers = snapshot.vaultLevers,
    vaultDoors = snapshot.vaultDoors,
    secretDoors = snapshot.secretDoors,
    blocks = snapshot.blocks,
    plates = snapshot.plates,
    gates = snapshot.gates,
    prefabVaults = snapshot.prefabVaults,
    rifts = snapshot.rifts,
    weather = snapshot.weather,
    biome = snapshot.biome,
    event = snapshot.event,
    dark = snapshot.dark,
    explored = explored,
    upX = snapshot.upX, upY = snapshot.upY,
    downX = snapshot.downX, downY = snapshot.downY,
  })
end

return Level
