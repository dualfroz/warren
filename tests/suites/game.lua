local helpers = require("helpers")
local Rng = require("rng")
local Map = require("map")
local Items = require("items")
local Status = require("status")
local Monsters = require("monsters")
local Level = require("level")
local Builder = require("builder")
local Game = require("game")
local Companions = require("companions")
local Stealth = require("stealth")
local Corpses = require("corpses")
local Reanimation = require("reanimation")
local Mercenaries = require("mercenaries")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local function splitArena(w, h, gapX)
  local map = Map.new(w, h)
  for y = 2, h - 1 do
    for x = 2, gapX - 1 do map:set(x, y, Map.FLOOR) end
    for x = gapX + 1, w - 1 do map:set(x, y, Map.FLOOR) end
  end
  return Level.new({
    depth = 1, generator = "arena", map = map,
    entities = {}, floorItems = {}, traps = {}, lights = {}, dark = false, explored = {},
    upX = 2, upY = 2, downX = w - 1, downY = h - 1,
  })
end

local tests = helpers.suite()

function tests.amuletSpawnsOnFinalFloorOnly()
  local finalLevel = Builder.build(Builder.MAX_DEPTH, Rng.new(999), {})
  local finalCount = 0
  for _, ground in ipairs(finalLevel.floorItems) do
    if ground.item.kind == Items.AMULET then finalCount = finalCount + 1 end
  end
  eq(finalCount, 1, "exactly one amulet is placed on the final floor")

  local shallowLevel = Builder.build(Builder.MAX_DEPTH - 1, Rng.new(999), {})
  local shallowCount = 0
  for _, ground in ipairs(shallowLevel.floorItems) do
    if ground.item.kind == Items.AMULET then shallowCount = shallowCount + 1 end
  end
  eq(shallowCount, 0, "no amulet appears above the final floor")
end

function tests.descendIsBlockedAtTheFinalFloor()
  local game = Game.new(555)
  game.depth = game.maxDepth
  game.level = game.dungeon:get(game.maxDepth)
  game.player.x, game.player.y = game.level.downX, game.level.downY
  local result = game:descend()
  eq(result, false, "descend fails once at the final floor")
  eq(game.depth, game.maxDepth, "depth is unchanged after a blocked descend")
  ok(contains(game.log:last(), "rock"), "a message explains why the descent is blocked")
end

function tests.ascendWithoutAmuletDoesNotWin()
  local game = Game.new(7)
  game.player.x, game.player.y = game.level.upX, game.level.upY
  local result = game:ascend()
  eq(result, true, "climbing out at depth 1 is still a valid move")
  eq(game.won, false, "climbing out without the amulet does not win the game")
end

function tests.ascendWithAmuletWinsTheGame()
  local game = Game.new(7)
  game.player.inventory[#game.player.inventory + 1] = Items.amulet()
  game.player.x, game.player.y = game.level.upX, game.level.upY
  local result = game:ascend()
  eq(result, true, "climbing out at depth 1 with the amulet succeeds")
  eq(game.won, true, "carrying the amulet to the surface wins the game")
  ok(contains(game.log:last(), "win"), "the victory is logged")
end

function tests.gameDescendTracksDeepestDepthEvenAfterAscending()
  local game = Game.new(9, { maxDepth = 4 })
  eq(game.deepestDepth, 1, "a fresh game's deepest depth is its starting depth")
  game.player.x, game.player.y = game.level.downX, game.level.downY
  game:descend()
  game.player.x, game.player.y = game.level.downX, game.level.downY
  game:descend()
  eq(game.deepestDepth, 3, "descending twice raises the deepest depth to the floor just reached")
  game.player.x, game.player.y = game.level.upX, game.level.upY
  game:ascend()
  eq(game.depth, 2, "ascending drops the live depth")
  eq(game.deepestDepth, 3, "ascending back up does not erase the deepest depth already reached")
end

function tests.gameDescendCarriesEveryLivingAllyOntoTheNextFloorInsteadOfAbandoningThem()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local oldLevel = game.level
  local golem = Companions.summon(game, "golem")
  local hireling = Mercenaries.hire(game, "sellsword")
  local rat = Monsters.create(Monsters.byKey.rat, 99, 8, 6, 1)
  Corpses.spawn(game.level, rat)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  ok(golem ~= nil and hireling ~= nil and thrall ~= nil, "all three allies bond before the descent")

  game.player.x, game.player.y = game.level.downX, game.level.downY
  ok(game:descend(), "descending succeeds")
  eq(game.depth, 2, "the game is now on the second floor")
  ok(game:hasCompanion(), "the companion is with the player on the new floor")
  ok(game:hasHireling(), "the hireling is with the player on the new floor")
  local thrallFound
  for _, entity in ipairs(game.level.entities) do
    if entity.kind == "thrall" then thrallFound = entity end
  end
  eq(thrallFound, thrall, "the very same thrall instance rises with the player, not a rebuilt one")

  local leftBehind = 0
  for _, entity in ipairs(oldLevel.entities) do
    if entity.kind == "companion" or entity.kind == "hireling" or entity.kind == "thrall" then
      leftBehind = leftBehind + 1
    end
  end
  eq(leftBehind, 0, "none of the three allies are stranded on the departing floor")
end

function tests.gameAscendCarriesEveryLivingAllyBackOntoThePreviousFloorToo()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.x, game.player.y = game.level.downX, game.level.downY
  game:descend()
  eq(game.depth, 2, "now on the second floor")
  local golem = Companions.summon(game, "golem")
  local hireling = Mercenaries.hire(game, "sellsword")
  ok(golem ~= nil and hireling ~= nil, "both allies bond on the second floor")
  local descendLevel = game.level

  game.player.x, game.player.y = game.level.upX, game.level.upY
  ok(game:ascend(), "ascending succeeds")
  eq(game.depth, 1, "back on the first floor")
  ok(game:hasCompanion(), "the companion follows back up the stairs")
  ok(game:hasHireling(), "the hireling follows back up the stairs too")

  local leftBehind = 0
  for _, entity in ipairs(descendLevel.entities) do
    if entity.kind == "companion" or entity.kind == "hireling" then leftBehind = leftBehind + 1 end
  end
  eq(leftBehind, 0, "neither ally is stranded on the floor just climbed away from")
end

function tests.gameManualStepEndsTheTurnOnlyWhenTheCommandActuallySucceeds()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local turnBefore = game.turn
  local consumesTurn = game:manualStep("north")
  eq(consumesTurn, true, "a valid move spends the turn")
  eq(game.turn, turnBefore + 1, "Game:manualStep advances the turn counter on a successful command")
end

function tests.gameManualStepLeavesTheTurnCounterUntouchedOnARejectedCommand()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local turnBefore = game.turn
  local consumesTurn, message = game:manualStep("nonsense")
  eq(consumesTurn, false, "an unrecognized command reports failure")
  ok(message ~= nil, "the rejection carries a reason")
  eq(game.turn, turnBefore, "the turn counter never advances on a rejected command")
end

function tests.gameManualStepIsIdempotentAcrossRepeatedRejectedCommandsWithinOneUnspentTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Status.apply(game.player, Status.POISON, 5, 5)
  game:manualStep("nonsense")
  local hpAfterFirst = game.player.hp
  local durationAfterFirst = game.player.statuses[1].duration
  game:manualStep("gibberish")
  eq(game.player.hp, hpAfterFirst,
    "a second rejected command within the same unspent turn does not re-tick poison damage")
  eq(game.player.statuses[1].duration, durationAfterFirst,
    "...nor does it re-decrement the poison's own remaining duration")
end

function tests.gameManualStepStunnedPlayerIgnoresTheTypedCommandButStillSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Status.apply(game.player, Status.STUN, 2, 0)
  local turnBefore = game.turn
  local px, py = game.player.x, game.player.y
  local consumesTurn = game:manualStep("north")
  eq(consumesTurn, true, "a stunned turn is spent regardless of the typed command")
  eq(game.player.x, px, "the player never actually moves while stunned")
  eq(game.player.y, py, "the player never actually moves while stunned")
  eq(game.turn, turnBefore + 1, "the stunned turn still advances the turn counter")
end

function tests.gameManualStepHaltsWithoutSpendingATurnOnceTheRunIsAlreadyWon()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.won = true
  local turnBefore = game.turn
  local consumesTurn = game:manualStep("north")
  eq(consumesTurn, false, "a manual command after victory spends no turn")
  eq(game.turn, turnBefore, "the turn counter never advances once the run is already won")
end

function tests.gameAutoExploreWalksTowardUnexploredTerrainUntilTheWholeReachableAreaIsSeen()
  local level = arena(25, 15)
  local game = stagedGame(1, level, 3, 3)
  local turnBefore = game.turn
  local consumesTurn, message = game:autoExplore()
  eq(consumesTurn, true, "a run with real ground left to cover spends turns")
  eq(message, "you have finished exploring", "a completed run reports it finished")
  ok(game.turn > turnBefore, "autoExplore actually advances the turn counter")
  local map = level.map
  local allSeen = true
  for y = 2, 14 do
    for x = 2, 24 do
      if not level.explored[map:index(x, y)] then allSeen = false end
    end
  end
  ok(allSeen, "every walkable cell in the reachable room ends up explored")
end

function tests.gameAutoExploreReportsNothingLeftWithoutSpendingATurnWhenAlreadyFullyExplored()
  local game = stagedGame(1, arena(11, 9), 5, 5)
  local turnBefore = game.turn
  local consumesTurn, message = game:autoExplore()
  eq(consumesTurn, false, "a room already fully visible from the start spends no turn")
  eq(message, "there is nothing left to explore", "the refusal explains why")
  eq(game.turn, turnBefore, "the turn counter never advances")
end

function tests.gameAutoExploreHaltsWithoutSpendingATurnOnceTheRunIsAlreadyWon()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.won = true
  local turnBefore = game.turn
  local consumesTurn, message = game:autoExplore()
  eq(consumesTurn, false, "an autoexplore attempt after victory spends no turn")
  eq(message, "there is nothing left to do", "the refusal matches Game:manualStep's own halted message")
  eq(game.turn, turnBefore, "the turn counter never advances once the run is already won")
end

function tests.gameAutoExploreStopsTheInstantThePlayerTakesDamage()
  local game = stagedGame(1, arena(25, 15), 3, 3)
  Status.apply(game.player, Status.POISON, 5, 4)
  local turnBefore = game.turn
  local hpBefore = game.player.hp
  local consumesTurn, message = game:autoExplore()
  eq(consumesTurn, true, "the interrupted turn itself still spends")
  eq(message, "you stop exploring - you have taken damage", "the interrupt explains itself")
  eq(game.turn, turnBefore + 1, "exactly the one turn that took the damage was spent")
  eq(game.player.hp, hpBefore - 4, "the poison tick's own damage lands normally before the interrupt fires")
end

function tests.gameAutoExploreRefusesToStartWhileAHostileIsAlreadyInSight()
  local level = arena(21, 11)
  local game = stagedGame(1, level, 5, 5)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 7, 5, 1)
  orc.awareness = Stealth.DORMANT
  level.entities = { orc }
  game:computeVisible()
  local turnBefore = game.turn
  local consumesTurn, message = game:autoExplore()
  eq(consumesTurn, false, "a hostile already visible refuses to even start")
  eq(message, "a monster is already in sight", "the refusal names the reason")
  eq(game.turn, turnBefore, "the turn counter never advances")
end

function tests.gameAutoExploreStopsTheMomentAHostileComesIntoSightWithoutEngagingIt()
  local level = arena(30, 11)
  local game = stagedGame(2, level, 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 25, 6, 1)
  orc.awareness = Stealth.DORMANT
  level.entities = { orc }
  local turnBefore = game.turn
  local hpBefore = game.player.hp
  local orcHpBefore = orc.hp
  local consumesTurn, message = game:autoExplore()
  eq(consumesTurn, true, "real ground was covered before the interrupt fired")
  eq(message, "you stop exploring - a monster is in sight", "the interrupt names a sighted hostile")
  eq(game.turn, turnBefore + 14, "exactly the steps needed to bring the orc within vision range 8 were taken")
  eq(game.player.hp, hpBefore, "no damage was taken - explore stops on sight, not on contact")
  eq(orc.hp, orcHpBefore, "the orc is only spotted, never engaged")
  ok(game.visible[level.map:index(orc.x, orc.y)], "the orc really is the thing that got seen")
  eq(orc.x, 25, "the still-dormant orc never took a single step of its own")
  eq(orc.awareness, Stealth.DORMANT, "and never woke up at all")
end

function tests.gameManualStepDrivenExploreSpendsExactlyAsManyTurnsAsCallingGameAutoExploreDirectly()
  local direct = stagedGame(9, arena(25, 15), 3, 3)
  direct:autoExplore()
  local viaManualStep = stagedGame(9, arena(25, 15), 3, 3)
  viaManualStep:manualStep("explore")
  eq(viaManualStep.turn, direct.turn,
    "routing explore through Game:manualStep must not end the turn a second time on top of what " ..
    "autoExplore already closed itself")
end

function tests.gameRestUntilHealedRefusesWithoutSpendingATurnWhenAlreadyAtFullHealth()
  local game = stagedGame(1, arena(11, 9), 5, 5)
  local turnBefore = game.turn
  local consumesTurn, message = game:restUntilHealed()
  eq(consumesTurn, false, "resting at full health spends no turn")
  eq(message, "you are already at full health", "the refusal explains why")
  eq(game.turn, turnBefore, "the turn counter never advances")
end

function tests.gameRestUntilHealedRefusesWithoutSpendingATurnWhileAHostileIsAlreadyInSight()
  local level = arena(21, 11)
  local game = stagedGame(1, level, 5, 5)
  game.player.hp = game.player.maxHp - 5
  local orc = Monsters.create(Monsters.byKey.orc, 1, 7, 5, 1)
  orc.awareness = Stealth.DORMANT
  level.entities = { orc }
  game:computeVisible()
  local turnBefore = game.turn
  local consumesTurn, message = game:restUntilHealed()
  eq(consumesTurn, false, "a hostile already visible refuses to even start")
  eq(message, "a monster is already in sight", "the refusal names the reason")
  eq(game.turn, turnBefore, "the turn counter never advances")
end

function tests.gameRestUntilHealedHealsTurnByTurnUntilFullThenStops()
  local game = stagedGame(1, arena(11, 9), 5, 5)
  game.player.hp = game.player.maxHp - 6
  Status.apply(game.player, Status.REGEN, 20, 2)
  local turnBefore = game.turn
  local consumesTurn, message = game:restUntilHealed()
  eq(consumesTurn, true, "a rest that actually heals spends turns")
  eq(message, "you rest until your wounds close", "a completed rest reports it finished")
  eq(game.player.hp, game.player.maxHp, "hp is capped exactly at maxHp, never over it")
  eq(game.turn, turnBefore + 3, "exactly ceil(6/2) turns of the regen tick were needed")
end

function tests.gameRestUntilHealedStopsAfterTwoUnchangedTurnsWhenNothingIsHealingThePlayer()
  local game = stagedGame(1, arena(11, 9), 5, 5)
  game.player.hp = game.player.maxHp - 5
  local turnBefore = game.turn
  local consumesTurn, message = game:restUntilHealed()
  eq(consumesTurn, true, "the turns spent checking still count as spent")
  eq(message, "you stop resting - nothing here is healing you", "the interrupt explains itself")
  eq(game.turn, turnBefore + 2, "exactly two turns were spent before giving up")
  eq(game.player.hp, game.player.maxHp - 5, "hp is unchanged - nothing was healing it in the first place")
end

function tests.gameRestUntilHealedStopsTheInstantThePlayerTakesDamage()
  local game = stagedGame(1, arena(11, 9), 5, 5)
  game.player.hp = game.player.maxHp - 5
  Status.apply(game.player, Status.POISON, 5, 4)
  local turnBefore = game.turn
  local hpBefore = game.player.hp
  local consumesTurn, message = game:restUntilHealed()
  eq(consumesTurn, true, "the interrupted turn itself still spends")
  eq(message, "you stop resting - you have taken damage", "the interrupt explains itself")
  eq(game.turn, turnBefore + 1, "exactly the one turn that took the damage was spent")
  eq(game.player.hp, hpBefore - 4, "the poison tick's own damage lands normally before the interrupt fires")
end

function tests.gameRestUntilHealedStopsTheMomentAHostileComesIntoSightWithoutEngagingIt()
  local level = arena(30, 11)
  local game = stagedGame(2, level, 20, 6)
  game.player.hp = game.player.maxHp - 20
  Status.apply(game.player, Status.REGEN, 50, 1)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 11, 6, 1)
  orc.awareness = Stealth.HUNTING
  level.entities = { orc }
  game:computeVisible()
  ok(not game.visible[level.map:index(orc.x, orc.y)], "the orc starts out of sight")
  local turnBefore = game.turn
  local hpBefore = game.player.hp
  local orcHpBefore = orc.hp
  local consumesTurn, message = game:restUntilHealed()
  eq(consumesTurn, true, "real turns were spent healing before the interrupt fired")
  eq(message, "you stop resting - a monster is in sight", "the interrupt names a sighted hostile")
  eq(game.turn, turnBefore + 2, "exactly the steps needed to bring the orc within vision range 8 were taken")
  ok(game.player.hp > hpBefore, "the turns spent before the interrupt actually healed the player")
  eq(orc.hp, orcHpBefore, "the orc is only spotted, never engaged")
  ok(game.visible[level.map:index(orc.x, orc.y)], "the orc really is the thing that got seen")
  eq(orc.awareness, Stealth.HUNTING, "the orc's own awareness is unaffected by simply being spotted")
end

function tests.gameManualStepDrivenRestSpendsExactlyAsManyTurnsAsCallingGameRestUntilHealedDirectly()
  local direct = stagedGame(9, arena(11, 9), 5, 5)
  direct.player.hp = direct.player.maxHp - 6
  Status.apply(direct.player, Status.REGEN, 20, 2)
  direct:restUntilHealed()
  local viaManualStep = stagedGame(9, arena(11, 9), 5, 5)
  viaManualStep.player.hp = viaManualStep.player.maxHp - 6
  Status.apply(viaManualStep.player, Status.REGEN, 20, 2)
  viaManualStep:manualStep("rest")
  eq(viaManualStep.turn, direct.turn,
    "routing rest through Game:manualStep must not end the turn a second time on top of what " ..
    "restUntilHealed already closed itself, and must credit the turn manualStep primes before " ..
    "Commands.apply ever runs to the same run rather than losing it")
  eq(viaManualStep.player.hp, direct.player.hp, "both paths heal the player by the same total amount")
end

function tests.gameTravelToWalksTheShortestPathAndArrivesAtTheDestination()
  local level = arena(21, 11)
  local game = stagedGame(1, level, 3, 6)
  local expectedSteps = #game:playerPathTo(level.downX, level.downY) - 1
  local turnBefore = game.turn
  local consumesTurn, message = game:travelTo(level.downX, level.downY)
  eq(consumesTurn, true, "a real trip spends turns")
  eq(message, "you arrive", "arriving reports so")
  eq(game.player.x, level.downX, "the player actually reaches the destination x")
  eq(game.player.y, level.downY, "the player actually reaches the destination y")
  eq(game.turn, turnBefore + expectedSteps, "exactly the shortest path's own number of steps were spent")
end

function tests.gameTravelToRefusesWithoutSpendingATurnWhenAlreadyThere()
  local level = arena(11, 9)
  local game = stagedGame(1, level, level.downX, level.downY)
  local turnBefore = game.turn
  local consumesTurn, message = game:travelTo(level.downX, level.downY)
  eq(consumesTurn, false, "already standing on the destination spends no turn")
  eq(message, "you are already there", "the refusal explains why")
  eq(game.turn, turnBefore, "the turn counter never advances")
end

function tests.gameTravelToRefusesWithoutSpendingATurnWhenNoRouteExists()
  local level = splitArena(21, 9, 11)
  local game = stagedGame(1, level, 3, 5)
  local turnBefore = game.turn
  local consumesTurn, message = game:travelTo(level.downX, level.downY)
  eq(consumesTurn, false, "an unreachable destination refuses to even start")
  eq(message, "you cannot find a path there", "the refusal names the reason")
  eq(game.turn, turnBefore, "the turn counter never advances")
end

function tests.gameTravelToRefusesWithoutSpendingATurnWhileAHostileIsAlreadyInSight()
  local level = arena(21, 11)
  local game = stagedGame(1, level, 5, 5)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 7, 5, 1)
  orc.awareness = Stealth.DORMANT
  level.entities = { orc }
  game:computeVisible()
  local turnBefore = game.turn
  local consumesTurn, message = game:travelTo(level.downX, level.downY)
  eq(consumesTurn, false, "a hostile already visible refuses to even start")
  eq(message, "a monster is already in sight", "the refusal names the reason")
  eq(game.turn, turnBefore, "the turn counter never advances")
end

function tests.gameTravelToHaltsWithoutSpendingATurnOnceTheRunIsAlreadyWon()
  local level = arena(21, 11)
  local game = stagedGame(1, level, 5, 5)
  game.won = true
  local turnBefore = game.turn
  local consumesTurn, message = game:travelTo(level.downX, level.downY)
  eq(consumesTurn, false, "a travel attempt after victory spends no turn")
  eq(message, "there is nothing left to do", "the refusal matches Game:manualStep's own halted message")
  eq(game.turn, turnBefore, "the turn counter never advances once the run is already won")
end

function tests.gameTravelToStopsTheInstantThePlayerTakesDamage()
  local level = arena(25, 15)
  local game = stagedGame(1, level, 3, 3)
  Status.apply(game.player, Status.POISON, 5, 4)
  local turnBefore = game.turn
  local hpBefore = game.player.hp
  local consumesTurn, message = game:travelTo(level.downX, level.downY)
  eq(consumesTurn, true, "the interrupted turn itself still spends")
  eq(message, "you stop traveling - you have taken damage", "the interrupt explains itself")
  eq(game.turn, turnBefore + 1, "exactly the one turn that took the damage was spent")
  eq(game.player.hp, hpBefore - 4, "the poison tick's own damage lands normally before the interrupt fires")
end

function tests.gameTravelToStopsTheMomentAHostileComesIntoSightWithoutEngagingIt()
  local level = arena(30, 11)
  local game = stagedGame(2, level, 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 25, 6, 1)
  orc.awareness = Stealth.DORMANT
  level.entities = { orc }
  local turnBefore = game.turn
  local hpBefore = game.player.hp
  local orcHpBefore = orc.hp
  local consumesTurn, message = game:travelTo(28, 6)
  eq(consumesTurn, true, "real ground was covered before the interrupt fired")
  eq(message, "you stop traveling - a monster is in sight", "the interrupt names a sighted hostile")
  eq(game.turn, turnBefore + 14, "exactly the steps needed to bring the orc within vision range 8 were taken")
  eq(game.player.hp, hpBefore, "no damage was taken - travel stops on sight, not on contact")
  eq(orc.hp, orcHpBefore, "the orc is only spotted, never engaged")
  ok(game.visible[level.map:index(orc.x, orc.y)], "the orc really is the thing that got seen")
  eq(orc.x, 25, "the still-dormant orc never took a single step of its own")
  eq(orc.awareness, Stealth.DORMANT, "and never woke up at all")
end

function tests.gameManualStepDrivenTravelSpendsExactlyAsManyTurnsAsCallingGameTravelToDirectly()
  local level1 = arena(21, 11)
  local direct = stagedGame(9, level1, 3, 6)
  direct:travelTo(level1.downX, level1.downY)
  local level2 = arena(21, 11)
  local viaManualStep = stagedGame(9, level2, 3, 6)
  viaManualStep:manualStep("travel down")
  eq(viaManualStep.turn, direct.turn,
    "routing travel through Game:manualStep must not end the turn a second time on top of what " ..
    "travelTo already closed itself")
  eq(viaManualStep.player.x, direct.player.x, "both paths reach the same destination x")
  eq(viaManualStep.player.y, direct.player.y, "both paths reach the same destination y")
end

return tests
