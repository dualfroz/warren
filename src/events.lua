local Events = {}

Events.BLOODMOON = "bloodmoon"
Events.RICHVEINS = "richveins"
Events.HUSH = "hush"

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

function Events.monsterDamageMultiplier(event)
  if event and event.key == Events.BLOODMOON then return Events.BLOODMOON_MULTIPLIER end
  return 1
end

function Events.essenceMultiplier(event)
  if event and event.key == Events.RICHVEINS then return Events.RICHVEINS_MULTIPLIER end
  return 1
end

function Events.sightPenalty(event)
  if event and event.key == Events.HUSH then return Events.HUSH_SIGHT_PENALTY end
  return 0
end

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
