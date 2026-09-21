local Rng = require("rng")
local Builder = require("builder")
local Level = require("level")

local Branches = {}

Branches.DEPTH_BONUS = 4

local SALT = 0xC2B2AE3D27D4EB4F

function Branches.seedFor(worldSeed, depth)
  return math.tointeger(worldSeed ~ (depth * SALT)) or 0
end

function Branches.build(worldSeed, depth, options)
  local pocketDepth = depth + Branches.DEPTH_BONUS
  local rng = Rng.new(Branches.seedFor(worldSeed, depth))
  local pocketOptions = {}
  for k, v in pairs(options or {}) do pocketOptions[k] = v end
  pocketOptions.maxDepth = pocketDepth - 1
  return Builder.build(pocketDepth, rng, pocketOptions)
end

function Branches.levelsToData(riftLevels)
  local depths = {}
  for depth in pairs(riftLevels or {}) do depths[#depths + 1] = depth end
  table.sort(depths)
  local stored = {}
  for _, depth in ipairs(depths) do
    stored[#stored + 1] = { depth = depth, level = riftLevels[depth]:toData() }
  end
  return stored
end

function Branches.levelsFromData(stored)
  local riftLevels = {}
  for _, entry in ipairs(stored or {}) do
    riftLevels[entry.depth] = Level.fromData(entry.level)
  end
  return riftLevels
end

return Branches
