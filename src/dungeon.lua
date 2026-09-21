local Rng = require("rng")
local Builder = require("builder")
local Level = require("level")

local Dungeon = {}
Dungeon.__index = Dungeon

local SALT = 0x9E3779B97F4A7C15

function Dungeon.new(worldSeed, options)
  return setmetatable({
    worldSeed = worldSeed,
    options = options or {},
    levels = {},
  }, Dungeon)
end

function Dungeon:levelSeed(depth)
  return math.tointeger(self.worldSeed ~ (depth * SALT)) or 0
end

function Dungeon:get(depth)
  if not self.levels[depth] then
    local rng = Rng.new(self:levelSeed(depth))
    self.levels[depth] = Builder.build(depth, rng, self.options)
  end
  return self.levels[depth]
end

function Dungeon:isGenerated(depth)
  return self.levels[depth] ~= nil
end

function Dungeon:toData()
  local depths = {}
  for depth in pairs(self.levels) do
    depths[#depths + 1] = depth
  end
  table.sort(depths)
  local stored = {}
  for _, depth in ipairs(depths) do
    stored[#stored + 1] = { depth = depth, level = self.levels[depth]:toData() }
  end
  return { worldSeed = self.worldSeed, options = self.options, levels = stored }
end

function Dungeon.fromData(snapshot)
  local dungeon = Dungeon.new(snapshot.worldSeed, snapshot.options)
  for _, entry in ipairs(snapshot.levels) do
    dungeon.levels[entry.depth] = Level.fromData(entry.level)
  end
  return dungeon
end

return Dungeon
