local helpers = require("helpers")
local Rng = require("rng")
local Monsters = require("monsters")
local Game = require("game")
local Crafting = require("crafting")
local Events = require("events")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.eventsCatalogEntriesEachHaveDistinctStartAndEndFlavorText()
  for _, key in ipairs(Events.order) do
    local start = Events.describe(key)
    local ending = Events.endDescribe(key)
    ok(start ~= nil, key .. " has a start line")
    ok(ending ~= nil, key .. " has an end line")
    ok(start ~= ending, key .. "'s start and end lines read differently")
  end
end

function tests.eventsMonsterDamageMultiplierOnlyFiresDuringBloodmoon()
  eq(Events.monsterDamageMultiplier(nil), 1, "no active event leaves monster damage unscaled")
  eq(Events.monsterDamageMultiplier({ key = Events.RICHVEINS }), 1, "a non-bloodmoon event leaves monster damage unscaled")
  eq(Events.monsterDamageMultiplier({ key = Events.BLOODMOON }), Events.BLOODMOON_MULTIPLIER,
    "bloodmoon scales monster damage by its fixed multiplier")
end

function tests.eventsEssenceMultiplierOnlyFiresDuringRichVeins()
  eq(Events.essenceMultiplier(nil), 1, "no active event leaves essence unscaled")
  eq(Events.essenceMultiplier({ key = Events.BLOODMOON }), 1, "a non-richveins event leaves essence unscaled")
  eq(Events.essenceMultiplier({ key = Events.RICHVEINS }), Events.RICHVEINS_MULTIPLIER,
    "rich veins scales essence by its fixed multiplier")
end

function tests.eventsSightPenaltyOnlyFiresDuringHush()
  eq(Events.sightPenalty(nil), 0, "no active event carries no sight penalty")
  eq(Events.sightPenalty({ key = Events.BLOODMOON }), 0, "a non-hush event carries no sight penalty")
  eq(Events.sightPenalty({ key = Events.HUSH }), Events.HUSH_SIGHT_PENALTY, "hush carries its fixed sight penalty")
end

function tests.eventsStepNeverStartsOnTheFirstFloorRegardlessOfTheRoll()
  for seed = 1, 100 do
    local level = { depth = 1 }
    eq(Events.step(level, Rng.new(seed)), nil, "a depth-one floor never rolls an event")
    eq(level.event, nil, "a depth-one floor's event stays nil across every seed")
  end
end

function tests.eventsStepEventuallyStartsFromDepthTwoAcrossAHandfulOfSeeds()
  local started = false
  for seed = 1, 400 do
    local level = { depth = 2 }
    if Events.step(level, Rng.new(seed)) then started = true break end
  end
  ok(started, "a depth-two floor eventually rolls a fresh event across a handful of seeds")
end

function tests.eventsStepCountsDownAndExpiresWithItsEndLine()
  local level = { depth = 2, event = { key = Events.BLOODMOON, turnsLeft = 2 } }
  eq(Events.step(level, Rng.new(1)), nil, "an ordinary tick of a running event reports no line")
  eq(level.event.turnsLeft, 1, "the running event's clock ticks down by one")
  eq(Events.step(level, Rng.new(1)), Events.endDescribe(Events.BLOODMOON),
    "the event's expiry is reported the turn its clock runs out")
  eq(level.event, nil, "an expired event clears itself from the level")
end

function tests.gameMonsterMeleeDamageScalesDuringBloodmoon()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  local before = game.player.hp
  game:monsterMelee(orc)
  local plainDamage = before - game.player.hp

  game.player.hp = before
  game.level.event = { key = Events.BLOODMOON, turnsLeft = 5 }
  game:monsterMelee(orc)
  local bloodmoonDamage = before - game.player.hp

  eq(bloodmoonDamage, math.floor(plainDamage * Events.BLOODMOON_MULTIPLIER),
    "bloodmoon scales a monster's melee damage by its fixed multiplier")
end

function tests.gameMonsterShootDamageScalesDuringBloodmoon()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local dragon = Monsters.create(Monsters.byKey.dragon, 1, 6, 6, 1)
  local before = game.player.hp
  game:monsterShoot(dragon)
  local plainDamage = before - game.player.hp

  game.player.hp = before
  game.player.statuses = {}
  game.level.event = { key = Events.BLOODMOON, turnsLeft = 5 }
  game:monsterShoot(dragon)
  local bloodmoonDamage = before - game.player.hp

  eq(bloodmoonDamage, math.floor(plainDamage * Events.BLOODMOON_MULTIPLIER),
    "bloodmoon scales a monster's ranged damage by its fixed multiplier")
end

function tests.gameKillEssenceIsDoubledDuringRichVeins()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.level.event = { key = Events.RICHVEINS, turnsLeft = 5 }
  local essenceBefore = game.player.essence
  game:playerAttack(rat)
  eq(game.player.essence, essenceBefore + Crafting.essenceFor(Monsters.xpFor(rat)) * Events.RICHVEINS_MULTIPLIER,
    "rich veins doubles the essence earned from a kill")
end

function tests.gameEffectiveRadiusShrinksDuringHush()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local plain = game:effectiveRadius()
  game.level.event = { key = Events.HUSH, turnsLeft = 5 }
  eq(game:effectiveRadius(), plain - Events.HUSH_SIGHT_PENALTY, "hush dulls the player's effective sight radius")
end

function tests.gameEndPlayerTurnEventuallyRollsAFreshEventFromDepthTwo()
  local triggered = false
  for seed = 1, 400 do
    local game = stagedGame(1, arena(21, 11), 3, 6)
    game.level.depth = 2
    game.rng = Rng.new(seed)
    game:endPlayerTurn()
    if game.level.event then triggered = true break end
  end
  ok(triggered, "ending a turn on a depth-two floor eventually rolls a fresh event across a handful of seeds")
end

function tests.gameEndPlayerTurnAnnouncesAnEventEndingInTheLog()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.event = { key = Events.RICHVEINS, turnsLeft = 1 }
  game:endPlayerTurn()
  eq(game.level.event, nil, "the event's clock runs out and clears itself")
  ok(contains(game.log:last(), "quiet"), "the event's end is reported in the message log")
end

function tests.eventFieldSurvivesSerialization()
  local game = Game.new(3)
  game.level.event = { key = Events.HUSH, turnsLeft = 9 }
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.level.event.key, Events.HUSH, "the active event's key survives a save/load round trip")
  eq(restored.level.event.turnsLeft, 9, "the active event's remaining turns survive a save/load round trip")
end

return tests
