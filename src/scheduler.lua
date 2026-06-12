-- Energy-based turn scheduler. Every actor accrues its effective speed each
-- round; an actor may act once its energy reaches the cost threshold, and acting
-- spends that much. Faster actors therefore act more often. Ordering among ready
-- actors is fully deterministic: highest energy first, ties broken by ascending
-- id, so the same seed always yields the same interleaving.

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

-- Picks the next actor eligible to act, granting energy in id order whenever no
-- one is ready yet. Returns nil only if there are no living actors at all.
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
