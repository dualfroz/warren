local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Status = require("status")
local Monsters = require("monsters")
local Spells = require("spells")
local Skills = require("skills")
local Crafting = require("crafting")
local Alchemy = require("alchemy")
local Factions = require("factions")
local Runewords = require("runewords")
local Durability = require("durability")
local Mercenaries = require("mercenaries")
local Commands = require("commands")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.commandsParseSplitsAVerbAndArgsLowercasedAndTrimmed()
  local parsed = Commands.parse("  ThRoW  3  ")
  eq(parsed.verb, "throw", "the verb is lowercased")
  eq(parsed.args[1], "3", "the remaining token becomes an arg")
  eq(Commands.parse(""), nil, "an empty line parses to nil")
  eq(Commands.parse("   "), nil, "an all-whitespace line parses to nil")
end

function tests.commandsApplyRejectsAnUnknownVerbWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local consumesTurn, message = Commands.apply(game, "dance")
  eq(consumesTurn, false, "an unrecognized verb spends no turn")
  ok(contains(message, "unknown command"), "the message names the bad verb")
end

function tests.commandsApplyMovingIntoAWallFailsWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 2, 2)
  local consumesTurn, message = Commands.apply(game, "north")
  eq(consumesTurn, false, "walking into the arena's own boundary wall spends no turn")
  eq(message, "you cannot go that way", "the failure explains itself")
  eq(game.player.x, 2, "the player never actually moves on a rejected step")
  eq(game.player.y, 2, "the player never actually moves on a rejected step")
end

function tests.commandsApplyMovementBumpsIntoAnAdjacentHostileAsAnAttack()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 5, 1)
  rat.hp = 20
  game.level.entities = { rat }
  local consumesTurn = Commands.apply(game, "east")
  eq(consumesTurn, true, "bumping into a hostile spends the turn")
  eq(game.player.x, 5, "the player does not step onto the monster's own tile")
  ok(rat.hp < 20, "the bump attack actually lands through Game:movePlayer")
end

function tests.commandsApplyAttackAliasesMovementIntoAnExplicitDirection()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 5, 1)
  rat.hp = 20
  game.level.entities = { rat }
  local consumesTurn = Commands.apply(game, "attack east")
  eq(consumesTurn, true, "attack <dir> spends the turn")
  ok(rat.hp < 20, "attack <dir> lands the same bump attack a plain direction would")
  local rejected, message = Commands.apply(game, "attack sideways")
  eq(rejected, false, "attack with an unrecognized direction word spends no turn")
  eq(message, "attack which direction?", "the failure names what is missing")
end

function tests.commandsApplyWaitAlwaysSucceedsAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local consumesTurn, message = Commands.apply(game, "wait")
  eq(consumesTurn, true, "waiting always spends the turn")
  eq(message, "you wait", "waiting reports itself")
end

function tests.commandsApplyPickupSweepsFloorItemsAtThePlayersFeetAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.floorItems = { { x = 5, y = 5, item = Items.gold(15) } }
  local goldBefore = game.player.gold
  local consumesTurn = Commands.apply(game, "pickup")
  eq(consumesTurn, true, "pickup always spends the turn")
  eq(game.player.gold, goldBefore + 15, "gold sitting on the player's own tile is swept up")
  eq(#game.level.floorItems, 0, "the picked-up item leaves the floor")
end

function tests.commandsApplyUseDrinksAPotionByInventoryIndexAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local before = #game.player.inventory
  local consumesTurn = Commands.apply(game, "use 1")
  eq(consumesTurn, true, "using a valid inventory item spends the turn")
  eq(#game.player.inventory, before - 1, "the consumed potion leaves the inventory")
end

function tests.commandsApplyItemCommandsRejectAMissingOrNonNumericIndexWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  for _, verb in ipairs({ "use", "drop", "sell", "throw", "capture" }) do
    local consumesTurn, message = Commands.apply(game, verb)
    eq(consumesTurn, false, verb .. " with no inventory number spends no turn")
    ok(message ~= nil and #message > 0, verb .. " explains what index it needs")
  end
  local consumesTurn, message = Commands.apply(game, "use ninety")
  eq(consumesTurn, false, "a non-numeric inventory argument spends no turn")
  ok(message ~= nil, "the non-numeric argument still gets a clear reason")
end

function tests.commandsApplyCastAutoTargetsTheNearestVisibleHostile()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local near = Monsters.create(Monsters.byKey.rat, 5, 8, 5, 1)
  local far = Monsters.create(Monsters.byKey.rat, 9, 15, 5, 1)
  near.hp, far.hp = 30, 30
  game.level.entities = { near, far }
  local consumesTurn = Commands.apply(game, "cast missile")
  eq(consumesTurn, true, "casting a known targeted spell at a visible hostile spends the turn")
  ok(near.hp < 30, "the nearer visible hostile takes the hit")
  eq(far.hp, 30, "the farther hostile is left untouched")
end

function tests.commandsApplyCastBreaksATiedDistanceByAscendingMonsterId()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local higherId = Monsters.create(Monsters.byKey.rat, 9, 8, 5, 1)
  local lowerId = Monsters.create(Monsters.byKey.rat, 3, 5, 8, 1)
  higherId.hp, lowerId.hp = 30, 30
  game.level.entities = { higherId, lowerId }
  Commands.apply(game, "cast missile")
  ok(lowerId.hp < 30, "a tied Chebyshev distance is broken toward the lower monster id")
  eq(higherId.hp, 30, "the higher-id tied hostile is left untouched")
end

function tests.commandsApplyCastFailsWithoutSpendingATurnWhenNoHostileIsVisible()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local consumesTurn, message = Commands.apply(game, "cast missile")
  eq(consumesTurn, false, "a targeted spell with nothing to target spends no turn")
  eq(message, "there is nothing in sight to cast that at", "the failure explains itself")
end

function tests.commandsApplyCastRejectsAnUnknownOrUnlearnedSpellWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local consumesTurn, message = Commands.apply(game, "cast nonsense")
  eq(consumesTurn, false, "an unknown spell key spends no turn")
  eq(message, "you know no spell by that name", "the failure names the problem")
end

function tests.commandsApplyCastConfuseAppliesTheStatusThroughTheFullCommandPipeline()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Spells.learn(game.player, "confuse")
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 5, 1)
  game.level.entities = { rat }
  local consumesTurn = Commands.apply(game, "cast confuse")
  eq(consumesTurn, true, "casting confuse on a visible hostile spends the turn")
  eq(Status.has(rat, Status.CONFUSE), true, "the nearest visible hostile carries the confuse status afterward")
end

function tests.commandsApplyCastBlindAppliesTheStatusThroughTheFullCommandPipeline()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Spells.learn(game.player, "blind")
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 5, 1)
  game.level.entities = { rat }
  local consumesTurn = Commands.apply(game, "cast blind")
  eq(consumesTurn, true, "casting blind on a visible hostile spends the turn")
  eq(Status.has(rat, Status.BLIND), true, "the nearest visible hostile carries the blind status afterward")
end

function tests.commandsApplyCastWeakenAppliesTheStatusThroughTheFullCommandPipeline()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Spells.learn(game.player, "weaken")
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 5, 1)
  game.level.entities = { rat }
  local consumesTurn = Commands.apply(game, "cast weaken")
  eq(consumesTurn, true, "casting weaken on a visible hostile spends the turn")
  eq(Status.has(rat, Status.WEAKEN), true, "the nearest visible hostile carries the weaken status afterward")
end

function tests.commandsApplyCastLevitateAppliesTheStatusToTheCasterThroughTheFullCommandPipeline()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Spells.learn(game.player, "levitate")
  local consumesTurn = Commands.apply(game, "cast levitate")
  eq(consumesTurn, true, "casting levitate spends the turn")
  eq(Status.has(game.player, Status.LEVITATE), true, "the caster carries the levitate status afterward")
end

function tests.commandsApplyCastCleanseLiftsTheCastersOwnStatusThroughTheFullCommandPipeline()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Spells.learn(game.player, "cleanse")
  Status.apply(game.player, Status.POISON, 5, 2)
  local consumesTurn = Commands.apply(game, "cast cleanse")
  eq(consumesTurn, true, "casting cleanse spends the turn")
  eq(Status.has(game.player, Status.POISON), false, "the caster's own poison is gone afterward")
end

function tests.commandsApplyThrowAndFireFailWithoutSpendingATurnWhenNoHostileIsVisible()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local consumesTurn1, message1 = Commands.apply(game, "throw 1")
  eq(consumesTurn1, false, "throwing with nothing in sight spends no turn")
  eq(message1, "there is nothing in sight to throw at", "the failure explains itself")
  local consumesTurn2, message2 = Commands.apply(game, "fire")
  eq(consumesTurn2, false, "firing with nothing in sight spends no turn")
  eq(message2, "there is nothing in sight to fire at", "the failure explains itself")
end

function tests.commandsApplyUseskillRejectsAnUnknownOrUnlearnedSkillWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local unknown = Commands.apply(game, "useskill nonsense")
  eq(unknown, false, "an unknown skill key spends no turn")
  local unlearned = Commands.apply(game, "useskill cleave")
  eq(unlearned, false, "a skill the player never learned spends no turn")
end

function tests.commandsApplyUseskillCleaveAutoTargetsAnAdjacentHostile()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.class = "fighter"
  Skills.learn(game.player, "cleave")
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 5, 1)
  rat.hp = 20
  game.level.entities = { rat }
  local consumesTurn = Commands.apply(game, "useskill cleave")
  eq(consumesTurn, true, "cleave against an adjacent hostile spends the turn")
  ok(rat.hp < 20, "cleave's own attack lands on the auto-targeted adjacent hostile")
end

function tests.commandsApplyThrowWithAnExplicitTargetNumberHitsThatHostileInsteadOfTheNearestOne()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  local near = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  local far = Monsters.create(Monsters.byKey.rat, 1, 5, 8, 1)
  near.hp, far.hp = 20, 20
  game.level.entities = { near, far }
  game.player.inventory[#game.player.inventory + 1] = Items.weapon("dagger", 2)
  local index = #game.player.inventory
  local consumesTurn = Commands.apply(game, "throw " .. index .. " 2")
  eq(consumesTurn, true, "throwing at an explicit in-sight target number spends the turn")
  ok(far.hp < 20, "the explicitly named second hostile takes the hit")
  eq(near.hp, 20, "the nearer, non-targeted hostile is left untouched")
end

function tests.commandsApplyThrowRejectsAnExplicitTargetNumberThatIsNotInSightWithoutSpendingATurn()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.weapon("dagger", 2)
  local index = #game.player.inventory
  local before = #game.player.inventory
  local consumesTurn, message = Commands.apply(game, "throw " .. index .. " 5")
  eq(consumesTurn, false, "naming a target number nothing is visible at spends no turn")
  eq(message, "no monster in sight at that number", "the failure names the specific problem")
  eq(#game.player.inventory, before, "the item is never spent on a rejected target number")
end

function tests.commandsApplyFireWithAnExplicitTargetNumberShootsThatHostileInsteadOfTheNearestOne()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  local near = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  local far = Monsters.create(Monsters.byKey.rat, 1, 5, 8, 1)
  near.hp, far.hp = 20, 20
  game.level.entities = { near, far }
  game.player.bow = Items.bow("short bow", 2, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 2)
  local consumesTurn = Commands.apply(game, "fire 2")
  eq(consumesTurn, true, "firing at an explicit in-sight target number spends the turn")
  ok(far.hp < 20, "the explicitly named second hostile takes the shot")
  eq(near.hp, 20, "the nearer, non-targeted hostile is left untouched")
end

function tests.commandsApplyCastWithAnExplicitTargetNumberHitsThatHostileInsteadOfTheNearestOne()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  local near = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  local far = Monsters.create(Monsters.byKey.rat, 1, 5, 8, 1)
  near.hp, far.hp = 20, 20
  game.level.entities = { near, far }
  local consumesTurn = Commands.apply(game, "cast missile 2")
  eq(consumesTurn, true, "casting at an explicit in-sight target number spends the turn")
  ok(far.hp < 20, "the explicitly named second hostile takes the hit")
  eq(near.hp, 20, "the nearer, non-targeted hostile is left untouched")
end

function tests.commandsApplyCaptureWithAnExplicitTargetNumberTargetsThatHostileInsteadOfTheNearestOne()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  local near = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  local far = Monsters.create(Monsters.byKey.rat, 1, 5, 8, 1)
  near.hp, far.hp = 1, 1
  game.level.entities = { near, far }
  game.player.inventory[#game.player.inventory + 1] = Items.net()
  local index = #game.player.inventory
  game.rng = Rng.new(2)
  local consumesTurn = Commands.apply(game, "capture " .. index .. " 2")
  eq(consumesTurn, true, "capturing at an explicit in-sight target number spends the turn")
  eq(#game.level.captives, 1, "exactly one captive results from the attempt")
  eq(game.level.captives[1].x, far.x, "the explicitly named second hostile is the one caught")
  eq(game.level.captives[1].y, far.y, "the explicitly named second hostile is the one caught")
  ok(near:isAlive(), "the nearer, non-targeted hostile is left alive and free")
end

function tests.commandsApplyUseskillCleaveWithAnExplicitTargetNumberHitsThatAdjacentHostileInsteadOfTheDefaultNearestOne()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.class = "fighter"
  Skills.learn(game.player, "cleave")
  local ratA = Monsters.create(Monsters.byKey.rat, 1, 6, 5, 1)
  local ratB = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  ratA.hp, ratB.hp = 20, 20
  game.level.entities = { ratA, ratB }
  local consumesTurn = Commands.apply(game, "useskill cleave 2")
  eq(consumesTurn, true, "cleave against an explicit in-sight target number spends the turn")
  local dealtToB, dealtToA = 20 - ratB.hp, 20 - ratA.hp
  ok(dealtToB > dealtToA, "the explicitly named second hostile takes cleave's full hit, not just its splash")
end

function tests.commandsApplyUseskillMultishotWithExplicitTargetNumbersHitsExactlyThoseTwoHostiles()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.class = "ranger"
  Skills.learn(game.player, "multishot")
  game.player.bow = Items.bow("short bow", 2, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 2)
  local first = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  local middle = Monsters.create(Monsters.byKey.rat, 1, 6, 5, 1)
  local third = Monsters.create(Monsters.byKey.rat, 1, 5, 8, 1)
  first.hp, middle.hp, third.hp = 20, 20, 20
  game.level.entities = { first, middle, third }
  local consumesTurn = Commands.apply(game, "useskill multishot 1 3")
  eq(consumesTurn, true, "multishot against two explicit in-sight target numbers spends the turn")
  ok(first.hp < 20, "the first explicitly named hostile takes a shot")
  ok(third.hp < 20, "the second explicitly named hostile takes a shot")
  eq(middle.hp, 20, "the un-named, nearer-by-distance hostile in between is left untouched")
end

function tests.commandsApplyUseskillMultishotWithOnlyOneExplicitTargetNumberFallsBackToAutoTargetingBoth()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.class = "ranger"
  Skills.learn(game.player, "multishot")
  game.player.bow = Items.bow("short bow", 2, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 2)
  local near = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  near.hp = 20
  game.level.entities = { near }
  local consumesTurn = Commands.apply(game, "useskill multishot 1")
  eq(consumesTurn, true, "an ambiguous single explicit target still falls back to auto-targeting")
  ok(near.hp < 20, "the only visible hostile still takes a shot via the auto-target fallback")
end

function tests.commandsApplyContextActionsFailCleanlyWithNothingHereWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  for _, verb in ipairs({
    "open", "pray", "quest", "butcher", "raise", "scavenge", "harvest",
    "ransom", "sellcaptive", "interrogate", "descend", "ascend", "enterrift", "exitrift",
  }) do
    local consumesTurn, message = Commands.apply(game, verb)
    eq(consumesTurn, false, verb .. " with nothing here spends no turn")
    ok(message ~= nil and #message > 0, verb .. " gives a reason")
  end
end

function tests.commandsApplyDigRejectsAnUnknownDirectionAndAnUnreadiedPickWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local badDirection, message1 = Commands.apply(game, "dig sideways")
  eq(badDirection, false, "an unrecognized direction word spends no turn")
  eq(message1, "dig which direction?", "the failure names what is missing")
  local noPick, message2 = Commands.apply(game, "dig north")
  eq(noPick, false, "digging without a readied pick spends no turn")
  ok(message2 ~= nil, "the failure explains itself")
end

function tests.commandsApplyDisarmRejectsAMissingDirectionOrAnUndetectedTrapWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local badDirection, message1 = Commands.apply(game, "disarm sideways")
  eq(badDirection, false, "an unrecognized direction word spends no turn")
  eq(message1, "disarm which direction?", "the failure names what is missing")

  local undetected = { x = 6, y = 5, effect = "dart", revealed = false }
  game.level.traps = { undetected }
  local noTarget, message2 = Commands.apply(game, "disarm east")
  eq(noTarget, false, "a trap never yet noticed spends no turn")
  eq(message2, "there is nothing here you have noticed to disarm", "the failure explains itself")
  eq(#game.level.traps, 1, "the untouched trap is still there")

  local sprung = { x = 4, y = 5, effect = "dart", revealed = true, detected = true }
  game.level.traps = { sprung }
  local alreadySprung = Commands.apply(game, "disarm west")
  eq(alreadySprung, false, "an already-sprung trap spends no turn either")
end

function tests.commandsApplyDisarmAlwaysSpendsTheTurnAgainstADetectedTrapWhetherItSucceedsOrSprings()
  local sawSuccess, sawFailure = false, false
  for seed = 1, 300 do
    if sawSuccess and sawFailure then break end
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local trap = { x = 4, y = 6, effect = "dart", revealed = false, detected = true }
    game.level.traps = { trap }
    local consumesTurn = Commands.apply(game, "disarm east")
    eq(consumesTurn, true, "a disarm attempt against a real detected trap always spends the turn")
    if #game.level.traps == 0 then
      sawSuccess = true
    else
      eq(trap.revealed, true, "a failed disarm still springs and reveals the trap")
      sawFailure = true
    end
  end
  ok(sawSuccess, "disarming through the command eventually succeeds across a handful of seeds")
  ok(sawFailure, "disarming through the command eventually springs across a handful of seeds")
end

function tests.commandsApplyAppeaseBuysFactionStandingWithGoldAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.gold = 100
  local repBefore = Factions.reputationFor(game.player, Factions.MERCHANT)
  local costBefore = Factions.appeaseCost(game.player, Factions.MERCHANT)
  local consumesTurn = Commands.apply(game, "appease merchant")
  eq(consumesTurn, true, "affording tribute to a real faction spends the turn")
  eq(game.player.gold, 100 - costBefore, "the tribute's cost is charged in gold")
  ok(Factions.reputationFor(game.player, Factions.MERCHANT) > repBefore, "standing actually improves")
end

function tests.commandsApplyAppeaseRejectsAMissingOrUnknownFactionWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local missing, message1 = Commands.apply(game, "appease")
  eq(missing, false, "appease with no faction name spends no turn")
  ok(contains(message1, "merchant"), "the failure lists the valid faction names")

  local unknown, message2 = Commands.apply(game, "appease atlanteans")
  eq(unknown, false, "an unrecognized faction name spends no turn")
  ok(contains(message2, "merchant"), "the failure lists the valid faction names")
end

function tests.commandsApplyAppeaseFailsWithoutSpendingATurnWhenGoldIsShort()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.gold = 0
  local repBefore = Factions.reputationFor(game.player, Factions.MERCHANT)
  local consumesTurn = Commands.apply(game, "appease merchant")
  eq(consumesTurn, false, "an unaffordable tribute spends no turn")
  eq(game.player.gold, 0, "no gold is spent on a failed tribute")
  eq(Factions.reputationFor(game.player, Factions.MERCHANT), repBefore, "standing is untouched")
end

function tests.commandsApplyHordeEntersTheArenaAtWaveOneAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local consumesTurn = Commands.apply(game, "horde")
  eq(consumesTurn, true, "entering the horde arena spends the turn")
  eq(game.horde.wave, 1, "the arena begins at wave one")
  eq(game.level.generator, "horde", "the current level is swapped for the arena")
end

function tests.commandsApplyHordeRefusesToRestartAnArenaAlreadyInProgressWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Commands.apply(game, "horde")
  for _, entity in ipairs(game.level.entities) do entity.hp = 0 end
  game:cleanupDead()
  game:endPlayerTurn()
  local waveBefore = game.horde.wave
  local consumesTurn, message = Commands.apply(game, "horde")
  eq(consumesTurn, false, "re-entering an arena already in progress spends no turn")
  eq(game.horde.wave, waveBefore, "wave progress already made is left untouched")
  ok(message ~= nil, "the refusal explains itself")
end

function tests.commandsApplyInformationalVerbsNeverSpendATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local turnBefore = game.turn
  for _, verb in ipairs({ "inventory", "status", "look", "help" }) do
    local consumesTurn, message = Commands.apply(game, verb)
    eq(consumesTurn, false, verb .. " never spends a turn")
    ok(message ~= nil and #message > 0, verb .. " always answers with something")
  end
  eq(game.turn, turnBefore, "none of the informational commands advanced the turn counter")
end

function tests.commandsApplyLookListsOnlyVisibleHostilesByName()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 5, 1)
  game.level.entities = { rat }
  local consumesTurn, message = Commands.apply(game, "look")
  eq(consumesTurn, false, "look never spends a turn")
  ok(contains(message, rat.name), "look names a visible hostile")
end

function tests.commandsApplyExamineDescribesAnInventoryItemWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Items.weapon("dagger", 3) }
  local turnBefore = game.turn
  local consumesTurn, message = Commands.apply(game, "examine 1")
  eq(consumesTurn, false, "examine never spends a turn")
  eq(game.turn, turnBefore, "the turn counter stays put")
  ok(contains(message, "dagger") and contains(message, "power 3"), "the report describes the inventory item")
  local aliased = Commands.apply(game, "x 1")
  eq(aliased, false, "the x alias behaves identically and never spends a turn")
end

function tests.commandsApplyExamineMonsterDescribesTheSameEntryLookJustNumbered()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 5, 1)
  local orc = Monsters.create(Monsters.byKey.orc, 2, 9, 6, 1)
  game.level.entities = { rat, orc }
  local _, lookMessage = Commands.apply(game, "look")
  ok(contains(lookMessage, "1) " .. rat.name), "look numbers the rat first")
  ok(contains(lookMessage, "2) " .. orc.name), "look numbers the orc second")
  local consumesTurn, examineMessage = Commands.apply(game, "examine monster 2")
  eq(consumesTurn, false, "examining a monster never spends a turn")
  ok(contains(examineMessage, orc.name), "examine monster 2 describes the same monster look numbered 2")
end

function tests.commandsApplyExamineFailsCleanlyOnBadOrMissingArgumentsWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  eq(Commands.apply(game, "examine"), false, "examine with no argument spends no turn")
  eq(Commands.apply(game, "examine 1"), false, "examining an empty inventory slot spends no turn")
  eq(Commands.apply(game, "examine monster"), false, "examine monster with no index spends no turn")
  eq(Commands.apply(game, "examine monster 1"), false, "examining with nothing in sight spends no turn")
end

function tests.commandsApplyHelpMentionsExamine()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local _, message = Commands.apply(game, "help")
  ok(contains(message, "examine"), "help mentions examine")
end

function tests.commandsApplyForgeAndMergeDriveTheGemPipelineAndSpendTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.essence = Crafting.FORGE_COST * 2
  ok(Commands.apply(game, "forge fire"), "forging a known element spends the turn")
  ok(Commands.apply(game, "forge fire"), "forging a second matching gem spends the turn")
  local a, b
  for i, item in ipairs(game.player.inventory) do
    if item.kind == Items.GEM then
      if not a then a = i else b = i end
    end
  end
  local consumesTurn = Commands.apply(game, "merge " .. a .. " " .. b)
  eq(consumesTurn, true, "merging two matching gems spends the turn")
end

function tests.commandsApplyForgeRejectsAMissingOrUnknownElementWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local missing, message1 = Commands.apply(game, "forge")
  eq(missing, false, "forge with no element spends no turn")
  ok(message1 ~= nil, "the failure names what is missing")
  game.player.essence = Crafting.FORGE_COST
  local unknown = Commands.apply(game, "forge lava")
  eq(unknown, false, "an unrecognized element spends no turn")
end

function tests.commandsApplyMergeRejectsAMissingOrMismatchedPairWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local missing, message = Commands.apply(game, "merge")
  eq(missing, false, "merge with no indices spends no turn")
  ok(message ~= nil, "the failure names what is missing")
  game.player.inventory = { Crafting.gem(Crafting.FIRE, 1), Crafting.gem(Crafting.FROST, 1) }
  local mismatched = Commands.apply(game, "merge 1 2")
  eq(mismatched, false, "mismatched gems spend no turn")
  eq(#game.player.inventory, 2, "a rejected merge leaves both gems untouched")
end

function tests.commandsApplySocketTemperEnchantDisenchantDriveTheEquippedWeaponAndSpendTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  game.player.inventory = { Crafting.gem(Crafting.FIRE, 1) }

  local socketed = Commands.apply(game, "socket weapon 1")
  eq(socketed, true, "socketing a gem into the equipped weapon spends the turn")
  eq(weapon.socket.element, Crafting.FIRE, "the socketed gem's element lands on the weapon")

  game.player.essence = Crafting.temperCost(weapon)
  local tempered = Commands.apply(game, "temper weapon")
  eq(tempered, true, "tempering the equipped weapon spends the turn")

  game.player.essence = Crafting.ENCHANT_COST
  local enchanted = Commands.apply(game, "enchant weapon vicious")
  eq(enchanted, true, "enchanting the equipped weapon spends the turn")
  eq(weapon.affix.key, "vicious", "the chosen affix lands on the weapon")

  local disenchanted = Commands.apply(game, "disenchant weapon")
  eq(disenchanted, true, "disenchanting the equipped weapon spends the turn")
  eq(weapon.affix, nil, "the affix is gone once disenchanted")
end

function tests.commandsApplySocketRuneCompletesARunewordAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  game.player.inventory = { Runewords.rune("sol"), Runewords.rune("ith") }
  ok(Commands.apply(game, "socketrune weapon 1"), "socketing the first rune spends the turn")
  local consumesTurn, message = Commands.apply(game, "socketrune weapon 1")
  eq(consumesTurn, true, "completing the runeword spends the turn")
  ok(contains(game.log:last(), "Zenith"), "completing a runeword is announced by name")
end

function tests.commandsApplyCraftingVerbsFailCleanlyWithBadTargetsWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  for _, verb in ipairs({ "socket", "socketrune", "temper", "enchant", "disenchant" }) do
    local consumesTurn, message = Commands.apply(game, verb)
    eq(consumesTurn, false, verb .. " with no target spends no turn")
    ok(message ~= nil and #message > 0, verb .. " explains what it needs")
  end
  Items.equipWeapon(Items.weapon("dagger", 2), game.player)
  local badSocket = Commands.apply(game, "socket weapon 1")
  eq(badSocket, false, "socketing with an empty inventory slot spends no turn")
end

function tests.commandsApplyRepairFixesTheEquippedWeaponAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  game.player.weapon.durability = 0
  game.player.gold = 1000
  local consumesTurn = Commands.apply(game, "repair weapon")
  eq(consumesTurn, true, "repairing an affordable broken weapon spends the turn")
  eq(game.player.weapon.durability, Durability.MAX, "the weapon comes back to full durability")
end

function tests.commandsApplyRepairRejectsAnUnknownSlotOrAnEmptyPurseWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local badSlot, message = Commands.apply(game, "repair shield")
  eq(badSlot, false, "an unrecognized slot spends no turn")
  eq(message, "repair what? weapon, armor or bow", "the failure names the valid slots")
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  game.player.weapon.durability = 0
  game.player.gold = 0
  local shortPurse = Commands.apply(game, "repair weapon")
  eq(shortPurse, false, "an empty purse cannot repair, and spends no turn")
end

function tests.commandsApplyStealTakesTheWardedWareUnderfootAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.level.floorItems = { { x = 5, y = 5, item = Items.scroll("identify"), price = 18, shopId = keeper.id } }
  local invBefore = #game.player.inventory
  local consumesTurn = Commands.apply(game, "steal")
  eq(consumesTurn, true, "stealing a warded ware underfoot spends the turn")
  eq(#game.player.inventory, invBefore + 1, "the stolen item joins the inventory")
  eq(keeper.hostile, true, "the keeper turns hostile after the theft")
end

function tests.commandsApplyStealFailsWithNothingWardedUnderfootWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local consumesTurn, message = Commands.apply(game, "steal")
  eq(consumesTurn, false, "stealing with nothing underfoot spends no turn")
  eq(message, "there is nothing here worth stealing", "the failure explains itself")
end

function tests.commandsApplyDismissReleasesTheHirelingAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Mercenaries.hire(game, "sellsword")
  ok(game:hasHireling(), "the hire itself succeeded")
  local consumesTurn = Commands.apply(game, "dismiss")
  eq(consumesTurn, true, "dismissing an under-contract hireling spends the turn")
  eq(game:hasHireling(), false, "the hireling is gone")
end

function tests.commandsApplyDismissFailsWithNoHirelingWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local consumesTurn = Commands.apply(game, "dismiss")
  eq(consumesTurn, false, "dismissing with nobody under contract spends no turn")
end

function tests.commandsApplyLearnSpendsAPointNeverATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.class = "fighter"
  game.player.skillPoints = 1
  local turnBefore = game.turn
  local success = Commands.apply(game, "learn cleave")
  eq(success, false, "learning a skill never spends a turn")
  eq(game.turn, turnBefore, "the turn counter is untouched by learning")
  eq(Skills.has(game.player, "cleave"), true, "the skill is actually learned")
  eq(game.player.skillPoints, 0, "the skill point is spent")
  ok(contains(game.log:last(), "learn"), "learning is logged")

  local missing, message = Commands.apply(game, "learn")
  eq(missing, false, "learn with no skill name spends no turn")
  ok(message ~= nil, "the failure names what is missing")

  local alreadyKnown = Commands.apply(game, "learn cleave")
  eq(alreadyKnown, false, "re-learning an already-known skill spends no turn")
  ok(contains(game.log:last(), "already"), "the failure to re-learn is logged")
end

function tests.commandsApplyLearnAcceptsTheSkillsOwnCamelCaseSpellingDespiteTheParserLowercasingIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.class = "fighter"
  game.player.level = 5
  game.player.skillPoints = 2
  local success = Commands.apply(game, "learn secondWind")
  eq(success, false, "learning a skill never spends a turn")
  eq(Skills.has(game.player, "secondWind"), true, "the camelCase skill is actually learned under its real key")
  ok(contains(game.log:last(), "second wind"), "learning is logged under the skill's real name")

  local rogue = stagedGame(2, arena(21, 11), 5, 5)
  rogue.player.class = "rogue"
  rogue.player.level = 5
  rogue.player.skillPoints = 2
  Commands.apply(rogue, "learn poisonBlade")
  eq(Skills.has(rogue.player, "poisonBlade"), true, "a differently-classed camelCase skill also resolves correctly")

  local mage = stagedGame(3, arena(21, 11), 5, 5)
  mage.player.class = "mage"
  mage.player.level = 5
  mage.player.skillPoints = 2
  Commands.apply(mage, "learn manaShield")
  eq(Skills.has(mage.player, "manaShield"), true, "a camelCase PASSIVE skill resolves too, not only active ones")
end

function tests.commandsApplyUseskillAcceptsACamelCaseSkillNameDespiteTheParserLowercasingIt()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  game.player.class = "fighter"
  game.player.level = 5
  Skills.learn(game.player, "secondWind")
  game.player.hp = 1
  local consumesTurn = Commands.apply(game, "useskill secondWind")
  eq(consumesTurn, true, "using a camelCase-named skill by its real spelling spends the turn")
  ok(game.player.hp > 1, "second wind actually healed the player, proving the real skill ran")
  eq(game.player.skillCooldowns.secondWind, Skills.active.secondWind.cooldown,
    "the cooldown lands on the real camelCase key, not a lowercased one")

  local rogue = stagedGame(5, arena(21, 11), 5, 5)
  rogue.player.class = "rogue"
  rogue.player.level = 5
  Skills.learn(rogue.player, "poisonBlade")
  local consumesTurn2 = Commands.apply(rogue, "useskill poisonBlade")
  eq(consumesTurn2, true, "using poisonBlade by its real camelCase spelling spends the turn")
  eq(rogue.player.pendingPoisonBlade, true, "the venom is actually readied, proving the real skill ran")
end

function tests.commandsApplyBrewCombinesTwoHerbsAtACauldronAndSpendsTheTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Alchemy.herb(Alchemy.BLOODROOT) }
  local consumesTurn = Commands.apply(game, "brew 1 2")
  eq(consumesTurn, true, "brewing two herbs at a cauldron underfoot spends the turn")
  eq(game.player.inventory[1].kind, Items.POTION, "the brewed potion replaces the spent herbs")
end

function tests.commandsApplyBrewFailsAwayFromACauldronWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Alchemy.herb(Alchemy.BLOODROOT) }
  local consumesTurn = Commands.apply(game, "brew 1 2")
  eq(consumesTurn, false, "brewing away from any cauldron spends no turn")
  eq(#game.player.inventory, 2, "a failed brew for lack of a cauldron spends nothing")
  local missing, message = Commands.apply(game, "brew")
  eq(missing, false, "brew with no indices spends no turn")
  ok(message ~= nil, "the failure names what is missing")
end

function tests.commandsApplyBrewSpendsTheTurnEvenWhenThePairingCurdles()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Alchemy.herb(Alchemy.NIGHTCAP) }
  local consumesTurn, message = Commands.apply(game, "brew 1 2")
  eq(consumesTurn, true, "a curdled brew still consumed a real attempt and must spend the turn")
  eq(message, nil, "the curdle's own log line speaks for it, like a successful brew's message does")
  eq(#game.player.inventory, 0, "the curdle already spent both herbs before the handler ever saw the outcome")
  ok(contains(game.log:recent(1)[1] or "", "curdle"), "the curdle is still logged through the command pipeline")
end

function tests.commandsApplyBrewRejectsTheSameIndexTwiceOrANonHerbItemWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Items.potion(10) }
  local sameIndex = Commands.apply(game, "brew 1 1")
  eq(sameIndex, false, "naming the same inventory slot twice spends no turn")
  local nonHerb = Commands.apply(game, "brew 1 2")
  eq(nonHerb, false, "pairing a herb with a non-herb item spends no turn")
  eq(#game.player.inventory, 2, "neither rejected attempt spends any item")
end

function tests.commandsApplyHelpMentionsTheCraftingAndEconomyVerbs()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local _, message = Commands.apply(game, "help")
  for _, word in ipairs({ "steal", "dismiss", "learn", "forge", "merge", "brew", "socket", "temper", "enchant", "repair" }) do
    ok(contains(message, word), "help mentions " .. word)
  end
end

function tests.commandsApplyHelpMentionsAppeaseDisarmAndHorde()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local _, message = Commands.apply(game, "help")
  for _, word in ipairs({ "appease", "disarm", "horde" }) do
    ok(contains(message, word), "help mentions " .. word)
  end
end

function tests.commandsApplyExploreDrivesGameAutoExploreAndReturnsItsResult()
  local game = stagedGame(1, arena(11, 9), 5, 5)
  local consumesTurn, message = Commands.apply(game, "explore")
  eq(consumesTurn, false, "a room already fully visible from the start spends no turn")
  eq(message, "there is nothing left to explore", "the command surfaces Game:autoExplore's own message verbatim")
end

function tests.commandsApplyHelpMentionsExplore()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local _, message = Commands.apply(game, "help")
  ok(contains(message, "explore"), "help mentions explore")
end

function tests.commandsApplyHelpMentionsTheOptionalTargetNumberOnEveryTargetedVerb()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local _, message = Commands.apply(game, "help")
  ok(contains(message, "throw <n> [target]"), "help spells out throw's optional target number")
  ok(contains(message, "fire [target]"), "help spells out fire's optional target number")
  ok(contains(message, "capture <n> [target]"), "help spells out capture's optional target number")
  ok(contains(message, "cast <spell> [target]"), "help spells out cast's optional target number")
  ok(contains(message, "useskill <skill> [target]"), "help spells out useskill's optional target number")
end

function tests.commandsApplyRestDrivesGameRestUntilHealedAndReturnsItsResult()
  local game = stagedGame(1, arena(11, 9), 5, 5)
  local consumesTurn, message = Commands.apply(game, "rest")
  eq(consumesTurn, false, "a player already at full health spends no turn")
  eq(message, "you are already at full health", "the command surfaces Game:restUntilHealed's own message verbatim")
end

function tests.commandsApplyHelpMentionsRest()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local _, message = Commands.apply(game, "help")
  ok(contains(message, "rest"), "help mentions rest")
end

function tests.commandsApplyTravelDownDrivesGameTravelToTowardTheDownStairs()
  local level = arena(21, 11)
  local game = stagedGame(1, level, level.downX, level.downY)
  local consumesTurn, message = Commands.apply(game, "travel down")
  eq(consumesTurn, false, "already standing on the down stairs spends no turn")
  eq(message, "you are already there", "the command surfaces Game:travelTo's own message verbatim")
end

function tests.commandsApplyTravelUpDrivesGameTravelToTowardTheUpStairs()
  local level = arena(21, 11)
  local game = stagedGame(1, level, level.upX, level.upY)
  local consumesTurn, message = Commands.apply(game, "travel up")
  eq(consumesTurn, false, "already standing on the up stairs spends no turn")
  eq(message, "you are already there", "the command surfaces Game:travelTo's own message verbatim")
end

function tests.commandsApplyTravelWithoutAnArgumentFailsWithoutSpendingATurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local consumesTurn, message = Commands.apply(game, "travel")
  eq(consumesTurn, false, "an unrecognized destination spends no turn")
  eq(message, "travel where? down or up", "the failure explains the two valid destinations")
end

function tests.commandsApplyHelpMentionsTravel()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local _, message = Commands.apply(game, "help")
  ok(contains(message, "travel down/up"), "help mentions travel down/up")
end

return tests
