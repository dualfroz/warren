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
  maze = require("gen.maze").generate,
}

-- Deterministic ordering of names for callers that want to cycle generators by
-- depth without depending on hash iteration order. gen.maze is deliberately
-- absent: builder.lua's chosenGenerator indexes into this list by depth, and
-- every existing seed-pinned test downstream of it already assumes today's
-- four-way cycle. Reaching a maze floor is always explicit, via
-- options.generator = "maze" (see Gen.has/Gen.build below).
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
