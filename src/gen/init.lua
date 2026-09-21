local Connect = require("gen.connect")

local Gen = {}

Gen.generators = {
  rooms = require("gen.rooms").generate,
  bsp = require("gen.bsp").generate,
  cellular = require("gen.cellular").generate,
  drunkard = require("gen.drunkard").generate,
  maze = require("gen.maze").generate,
}

Gen.order = { "rooms", "bsp", "cellular", "drunkard" }

function Gen.has(name)
  return Gen.generators[name] ~= nil
end

function Gen.build(name, width, height, rng, options)
  local generate = Gen.generators[name]
  local map = generate(width, height, rng, options)
  local reachable = Connect.ensure(map, rng)
  return map, reachable
end

return Gen
