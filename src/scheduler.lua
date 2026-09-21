local Scheduler = {}

Scheduler.COST = 100

local function actorList(game)
  local actors = { game.player }
  for _, monster in ipairs(game:currentEntities()) do
    if monster:isAlive() then actors[#actors + 1] = monster end
  end
  return actors
end

local function ready(actor)
  return actor:isAlive() and actor.energy >= Scheduler.COST
end

function Scheduler.next(game)
  for _ = 1, 10000 do
    local actors = actorList(game)
    if #actors == 0 then return nil end
    local chosen
    for _, actor in ipairs(actors) do
      if ready(actor) then
        if chosen == nil
          or actor.energy > chosen.energy
          or (actor.energy == chosen.energy and actor.id < chosen.id) then
          chosen = actor
        end
      end
    end
    if chosen then return chosen end
    table.sort(actors, function(a, b) return a.id < b.id end)
    for _, actor in ipairs(actors) do
      actor.energy = actor.energy + actor:effectiveSpeed()
    end
  end
  return nil
end

function Scheduler.spend(actor)
  actor.energy = actor.energy - Scheduler.COST
end

return Scheduler
