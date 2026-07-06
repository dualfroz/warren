-- Monster alertness state machine layered on top of ai.lua's chase/pack/etc
-- behaviours. A wild monster the builder places starts dormant (asleep) and
-- takes no action at all until something wakes it: on each of its own turns
-- a still-dormant monster rolls a wake chance driven by distance, line of
-- sight and the player's detection-penalty skills (see skills.lua's
-- camouflage), guaranteed once the player stands right next to it. Landing
-- any hit on it - melee, spell or ranged - wakes it outright regardless of
-- the roll.
--
-- Once alert a monster hunts exactly as ai.lua always has; losing line of
-- sight for several turns in a row drops it to searching, where it makes
-- for wherever it last saw the player instead of running its usual
-- behaviour. Giving up the search with nothing found puts it back to sleep.
--
-- A blow struck against a monster that is still dormant is a sneak attack:
-- it never saw the swing coming, so it lands for several times the normal
-- damage (see Stealth.sneakMultiplier, read by Game:playerAttack).
--
-- Bosses, the shopkeeper and anything summoned or split mid-fight (see
-- game.lua's spawnMinion and bosses.lua's create) start "hunting" outright
-- rather than dormant, so none of this changes behaviour that was already
-- always-alert. A monster built directly without ever passing through
-- builder.lua's placement loop - as most of tests/run.lua's fixtures do -
-- also defaults to "hunting" whenever its awareness field is simply absent,
-- which keeps every existing hand-built scenario acting exactly as it did
-- before this module existed.

local Los = require("los")
local Skills = require("skills")

local Stealth = {}

Stealth.DORMANT = "dormant"
Stealth.HUNTING = "hunting"
Stealth.SEARCHING = "searching"

Stealth.WAKE_RADIUS = 6
Stealth.TRACK_RADIUS = 20
Stealth.LOST_TURNS_LIMIT = 4
Stealth.SEARCH_TURNS_LIMIT = 4
Stealth.SNEAK_MULTIPLIER = 3

function Stealth.isUnaware(monster)
  return monster.awareness == Stealth.DORMANT
end

-- Read by Game:playerAttack before Stealth.alert (below) fires on the same
-- swing, so the bonus is computed against the state the monster was
-- actually in the instant the blow landed.
function Stealth.sneakMultiplier(monster)
  if Stealth.isUnaware(monster) then return Stealth.SNEAK_MULTIPLIER end
  return 1
end

-- Called the instant a monster is provoked by any offensive player action -
-- whatever it was doing before, it now knows exactly where the player is.
function Stealth.alert(monster, px, py)
  monster.awareness = Stealth.HUNTING
  monster.lastKnownX, monster.lastKnownY = px, py
  monster.lostTurns = 0
end

-- Called when noise.lua's flood reaches a still-dormant monster (see
-- game.lua's Game:emitNoise). Unlike alert() above - a direct provocation,
-- which snaps a monster straight to hunting with the player's exact
-- position - a monster that only heard something does not know it was the
-- player specifically, or where they actually are now: it starts searching
-- the noise's own origin instead, exactly like a hunter that just lost
-- track (see Stealth.tick's searching branch below), so it may well arrive
-- to find nothing there and give up. A monster that is not currently
-- dormant is already tracking something better than a noise and ignores
-- this outright.
function Stealth.hear(monster, x, y)
  if monster.awareness ~= Stealth.DORMANT then return end
  monster.awareness = Stealth.SEARCHING
  monster.lastKnownX, monster.lastKnownY = x, y
  monster.searchTurns = 0
end

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local function canSpot(game, monster, radius)
  local penalty = Skills.detectionPenalty(game.player, game.level.dark)
  local effective = radius - penalty
  if effective < 1 then effective = 1 end
  if chebyshev(monster.x, monster.y, game.player.x, game.player.y) > effective then return false end
  return Los.clear(game.level.map, monster.x, monster.y, game.player.x, game.player.y)
end

-- Whether a dormant monster notices the player this turn: guaranteed once
-- adjacent, otherwise a chance that improves the closer the player stands,
-- scaled against the monster's own (penalty-adjusted) waking radius.
local function rollWake(game, monster)
  if not canSpot(game, monster, Stealth.WAKE_RADIUS) then return false end
  local dist = chebyshev(monster.x, monster.y, game.player.x, game.player.y)
  if dist <= 1 then return true end
  local penalty = Skills.detectionPenalty(game.player, game.level.dark)
  local radius = math.max(Stealth.WAKE_RADIUS - penalty, 1)
  local roll = game.rng:range(1, radius)
  return roll <= (radius - dist + 1)
end

-- Advances one monster's alertness ahead of its upcoming turn and reports
-- whether game.lua should still run its normal ability/ai dispatch this
-- turn. A monster that stays dormant, or one that spends the turn marching
-- back toward wherever it last saw the player, returns false - stealth.lua
-- has already fully resolved its turn (for dormant, that means doing
-- nothing at all).
function Stealth.tick(game, monster)
  local awareness = monster.awareness or Stealth.HUNTING
  if awareness == Stealth.DORMANT then
    if rollWake(game, monster) then
      Stealth.alert(monster, game.player.x, game.player.y)
      game.log:add(string.format("%s stirs awake", monster.name))
      return true
    end
    return false
  end
  if awareness == Stealth.SEARCHING then
    if canSpot(game, monster, Stealth.TRACK_RADIUS) then
      Stealth.alert(monster, game.player.x, game.player.y)
      return true
    end
    monster.searchTurns = (monster.searchTurns or 0) + 1
    if monster.lastKnownX and (monster.x ~= monster.lastKnownX or monster.y ~= monster.lastKnownY) then
      game:stepMonsterToward(monster, monster.lastKnownX, monster.lastKnownY)
    end
    if monster.searchTurns >= Stealth.SEARCH_TURNS_LIMIT then
      monster.awareness = Stealth.DORMANT
      monster.lastKnownX, monster.lastKnownY = nil, nil
      monster.lostTurns, monster.searchTurns = nil, nil
      game.log:add(string.format("%s gives up the search and settles back down", monster.name))
    end
    return false
  end
  -- hunting
  if canSpot(game, monster, Stealth.TRACK_RADIUS) then
    monster.lastKnownX, monster.lastKnownY = game.player.x, game.player.y
    monster.lostTurns = 0
    return true
  end
  monster.lostTurns = (monster.lostTurns or 0) + 1
  if monster.lostTurns >= Stealth.LOST_TURNS_LIMIT and monster.lastKnownX then
    monster.awareness = Stealth.SEARCHING
    monster.searchTurns = 0
    game.log:add(string.format("%s loses track of you", monster.name))
    return Stealth.tick(game, monster)
  end
  return true
end

return Stealth
