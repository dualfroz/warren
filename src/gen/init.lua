-- Registry of selectable dungeon generators. Every entry takes the same
-- (width, height, rng, options) signature and returns a carved Map. After
-- generation connectivity is enforced so the dungeon layer can rely on a single
-- reachable region regardless of which algorithm ran.

local Connect = require("gen.connect")

local Gen = {}

Gen.generators = {
  rooms = require("gen.rooms").generate,
  bsp = require("gen.bsp").generate,
  cellular = require("gen.cellular").generate,
  drunkard = require("gen.drunkard").generate,
}

-- Deterministic ordering of names for callers that want to cycle generators by
-- depth without depending on hash iteration order.
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
