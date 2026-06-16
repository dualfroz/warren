-- Timed dungeon-wide events. Unlike atmosphere.lua's single weather reading
-- drawn once at generation and fixed for a floor's entire lifetime, an
-- event can start and end mid-visit: from depth two on, any turn with none
-- already running has a small chance of rolling one fresh, and a running
-- one always expires back to nothing after a fixed duration rather than
-- lingering for the rest of the floor. Only one runs at a time.
-- level.event is nil or { key, turnsLeft }, plain data like level.weather,
-- so it serializes with no special save-format handling.

local Events = {}

Events.BLOODMOON = "bloodmoon"
Events.RICHVEINS = "richveins"
Events.HUSH = "hush"

-- Fixed order so a given rng draw always names the same event.
Events.order = { Events.BLOODMOON, Events.RICHVEINS, Events.HUSH }

Events.DURATION = 15

Events.START_NUMERATOR = 1
Events.START_DENOMINATOR = 60

Events.BLOODMOON_MULTIPLIER = 1.5
Events.RICHVEINS_MULTIPLIER = 2
Events.HUSH_SIGHT_PENALTY = 1

function Events.describe(key)
  if key == Events.BLOODMOON then return "a bloodmoon rises; the monsters here hit harder" end
  if key == Events.RICHVEINS then return "the walls hum with rich veins; essence flows freely" end
  if key == Events.HUSH then return "a hush falls over the floor, dulling your senses" end
  return nil
end

function Events.endDescribe(key)
  if key == Events.BLOODMOON then return "the bloodmoon fades" end
  if key == Events.RICHVEINS then return "the veins fall quiet again" end
  if key == Events.HUSH then return "the hush lifts" end
  return nil
end

-- A monster's raw attack-minus-defense swing at the player is scaled by
-- this multiplier, read live wherever a monster lands a hit
-- (Game:monsterMelee, Game:monsterShoot, Game:triggerMimic's ambush) -
-- never baked permanently into a monster's own stats the way
-- atmosphere.lua's INFESTED reading is, since it must lift again the
-- instant the event ends.
function Events.monsterDamageMultiplier(event)
  if event and event.key == Events.BLOODMOON then return Events.BLOODMOON_MULTIPLIER end
  return 1
end

-- Essence earned from a kill (Game:awardKill) or an ore vein
-- (Nodes.harvest) is scaled by this multiplier, read live at the point
-- essence is actually credited.
function Events.essenceMultiplier(event)
  if event and event.key == Events.RICHVEINS then return Events.RICHVEINS_MULTIPLIER end
  return 1
end

-- Read alongside atmosphere.lua's own sightPenalty in Game:effectiveRadius.
function Events.sightPenalty(event)
  if event and event.key == Events.HUSH then return Events.HUSH_SIGHT_PENALTY end
  return 0
end

-- Advances a running event's clock by one turn, or rolls a fresh one onto
-- `level` when none is running. Returns a log line on start or expiry, nil
-- on an ordinary quiet turn - exactly like sanity.lua's Sanity.tick, which
-- reports only on a tier crossing rather than every single call.
function Events.step(level, rng)
  if level.event then
    level.event.turnsLeft = level.event.turnsLeft - 1
    if level.event.turnsLeft <= 0 then
      local line = Events.endDescribe(level.event.key)
      level.event = nil
      return line
    end
    return nil
  end
  if level.depth < 2 or not rng:chance(Events.START_NUMERATOR, Events.START_DENOMINATOR) then
    return nil
  end
  local key = rng:pick(Events.order)
  level.event = { key = key, turnsLeft = Events.DURATION }
  return Events.describe(key)
end

return Events
