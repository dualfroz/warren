-- Secret doors: a wall tile that reads as ordinary rock (Tiles.WALL, same
-- glyph, same isPassable/blocksSight as any other wall) until the player
-- happens across it, gating a single hidden alcove otherwise unreachable
-- from the rest of the floor (see builder.lua's dead-last placement).
-- Detection is a passive roll against every still-hidden door within a
-- step of the player, rolled once per player turn from Game:endPlayerTurn -
-- the same shape disarm.lua's own trap sense already takes, and for the
-- same reason: a once-per-round sweep rather than once per actor keeps a
-- seeded run's discovery turn identical regardless of how many actors
-- acted that round. Once found, the wall becomes a plain Tiles.DOOR_CLOSED -
-- opened, from then on, through Game:openDoor exactly like any door the
-- builder cut in the open, since nothing about a secret door's mechanics
-- differs from an ordinary one once it is known to be there.

local Tiles = require("tiles")

local Secrets = {}

Secrets.SEARCH_NUMERATOR = 1
Secrets.SEARCH_DENOMINATOR = 5

-- Sweeps every secret door within Chebyshev distance 1 of (px, py) that is
-- not yet discovered, rolling each independently. Opens each newly-found
-- door's map tile into a plain closed door on the spot and returns the
-- doors discovered this call (in level.secretDoors order), so a caller only
-- ever needs to report what was found.
function Secrets.sweep(level, rng, px, py)
  local found = {}
  for _, door in ipairs(level.secretDoors) do
    if not door.discovered
      and math.max(math.abs(door.x - px), math.abs(door.y - py)) <= 1
      and rng:chance(Secrets.SEARCH_NUMERATOR, Secrets.SEARCH_DENOMINATOR) then
      door.discovered = true
      level.map:set(door.x, door.y, Tiles.DOOR_CLOSED)
      found[#found + 1] = door
    end
  end
  return found
end

-- Discovers every still-hidden secret door on the floor outright, with no
-- distance limit and no per-door roll - unlike Secrets.sweep's passive,
-- one-step, one-in-five search above. Used only by captives.lua's
-- interrogation, which trades a held captive for exactly this shortcut.
-- Returns the doors this actually revealed (in level.secretDoors order), so
-- a caller only ever needs to report what was found, same as Secrets.sweep.
function Secrets.revealAll(level)
  local found = {}
  for _, door in ipairs(level.secretDoors) do
    if not door.discovered then
      door.discovered = true
      level.map:set(door.x, door.y, Tiles.DOOR_CLOSED)
      found[#found + 1] = door
    end
  end
  return found
end

return Secrets
