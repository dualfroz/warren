local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Items = require("items")
local Status = require("status")
local Monsters = require("monsters")
local Level = require("level")
local Builder = require("builder")
local Game = require("game")
local Disarm = require("disarm")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.traps()
  local dartGame = stagedGame(1, arena(21, 11), 3, 6)
  dartGame.level.traps = { { x = 4, y = 6, effect = "dart", revealed = false } }
  local hpBefore = dartGame.player.hp
  dartGame:movePlayer(1, 0)
  ok(dartGame.player.hp < hpBefore, "a dart trap wounds the stepper")
  eq(dartGame.level.traps[1].revealed, true, "a sprung trap becomes revealed")
  eq(dartGame.level.map:get(4, 6), Tiles.TRAP, "a sprung trap shows on the map")

  local poisonGame = stagedGame(1, arena(21, 11), 3, 6)
  poisonGame.level.traps = { { x = 4, y = 6, effect = "poison", revealed = false } }
  poisonGame:movePlayer(1, 0)
  eq(Status.has(poisonGame.player, Status.POISON), true, "a poison trap poisons the stepper")

  local confuseGame = stagedGame(1, arena(21, 11), 3, 6)
  confuseGame.level.traps = { { x = 4, y = 6, effect = "confuse", revealed = false } }
  confuseGame:movePlayer(1, 0)
  eq(Status.has(confuseGame.player, Status.CONFUSE), true, "a confuse trap confuses the stepper")
  eq(confuseGame.level.traps[1].revealed, true, "a sprung confuse trap becomes revealed too")

  local blindGame = stagedGame(1, arena(21, 11), 3, 6)
  blindGame.level.traps = { { x = 4, y = 6, effect = "blind", revealed = false } }
  blindGame:movePlayer(1, 0)
  eq(Status.has(blindGame.player, Status.BLIND), true, "a blind trap blinds the stepper")
  eq(blindGame.level.traps[1].revealed, true, "a sprung blind trap becomes revealed too")
  eq(blindGame:effectiveRadius(), 1, "the freshly blinded stepper's own sight radius is clamped straight away")

  local stunGame = stagedGame(1, arena(21, 11), 3, 6)
  stunGame.level.traps = { { x = 4, y = 6, effect = "stun", revealed = false } }
  stunGame:movePlayer(1, 0)
  eq(Status.has(stunGame.player, Status.STUN), true, "a stun trap stuns the stepper")
  eq(stunGame.level.traps[1].revealed, true, "a sprung stun trap becomes revealed too")
end

function tests.gameSpringTrapConfuseEffectAppliesToAnyVictimNotJustThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 10, 6, 1)
  game.level.entities = { rat }
  local trap = { x = 10, y = 6, effect = "confuse", revealed = false }
  game:springTrap(trap, rat)
  eq(Status.has(rat, Status.CONFUSE), true, "a confuse trap sprung on a monster confuses that monster")
  eq(Status.has(game.player, Status.CONFUSE), false, "the player is untouched by a trap sprung on someone else")
end

function tests.gameSpringTrapBlindEffectAppliesToAnyVictimNotJustThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 10, 6, 1)
  game.level.entities = { rat }
  local trap = { x = 10, y = 6, effect = "blind", revealed = false }
  game:springTrap(trap, rat)
  eq(Status.has(rat, Status.BLIND), true, "a blind trap sprung on a monster blinds that monster")
  eq(Status.has(game.player, Status.BLIND), false, "the player is untouched by a trap sprung on someone else")
end

function tests.gameSpringTrapStunEffectAppliesToAnyVictimNotJustThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 10, 6, 1)
  game.level.entities = { rat }
  local trap = { x = 10, y = 6, effect = "stun", revealed = false }
  game:springTrap(trap, rat)
  eq(Status.has(rat, Status.STUN), true, "a stun trap sprung on a monster stuns that monster")
  eq(Status.has(game.player, Status.STUN), false, "the player is untouched by a trap sprung on someone else")
end

function tests.useItemOnAKitPlantsAHiddenTrapOnThePlayersTile()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Items.kit("dart") }
  ok(game:useItem(1), "using a trap kit succeeds")
  eq(#game.player.inventory, 0, "the kit leaves the inventory once planted")
  local trap = game.level:trapAt(5, 5)
  ok(trap ~= nil, "a trap is planted on the player's tile")
  eq(trap.effect, "dart", "the planted trap matches the kit's effect")
  eq(trap.revealed, false, "a freshly planted trap starts hidden")
  eq(game.level.map:get(5, 5), Tiles.FLOOR, "a hidden trap does not change the tile's glyph")
end

function tests.plantingATrapWhereOneAlreadyExistsFails()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.traps = { { x = 5, y = 5, effect = "poison", revealed = false } }
  game.player.inventory = { Items.kit("dart") }
  ok(not game:useItem(1), "planting a trap on an occupied tile fails")
  eq(#game.player.inventory, 1, "a failed planting leaves the kit in the inventory")
end

function tests.aMonsterSteppingOntoAPlayerSetTrapSpringsIt()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.traps = { { x = 6, y = 6, effect = "dart", revealed = false, placedByPlayer = true } }
  local orc = Monsters.create(Monsters.byKey.orc, 1, 7, 6, 1)
  game.level.entities = { orc }
  local hpBefore = orc.hp
  game:stepMonsterToward(orc, game.player.x, game.player.y)
  eq(orc.x, 6, "the orc steps onto the trapped cell while closing on the player")
  ok(orc.hp < hpBefore, "stepping onto a player-set dart trap wounds the monster")
  eq(game.level.traps[1].revealed, true, "the sprung trap becomes revealed")
end

function tests.checkTrapForSkipsAndLeavesUndetectedForALevitatingMonster()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.traps = { { x = 6, y = 6, effect = "dart", revealed = false } }
  local orc = Monsters.create(Monsters.byKey.orc, 1, 7, 6, 1)
  Status.apply(orc, Status.LEVITATE, 20, 1)
  game.level.entities = { orc }
  local hpBefore = orc.hp
  game:stepMonsterToward(orc, game.player.x, game.player.y)
  eq(orc.x, 6, "the levitating orc still steps onto the trapped cell while closing on the player")
  eq(orc.hp, hpBefore, "a levitating monster drifting over a trap takes no damage from it")
  eq(game.level.traps[1].revealed, false, "the trap it floated over is never revealed")
end

function tests.movePlayerSkipsTheInlineTrapTriggerForALevitatingPlayer()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.traps = { { x = 6, y = 5, effect = "dart", revealed = false } }
  Status.apply(game.player, Status.LEVITATE, 20, 1)
  local hpBefore = game.player.hp
  game:movePlayer(1, 0)
  eq(game.player.x, 6, "the levitating player still moves onto the trapped cell")
  eq(game.player.hp, hpBefore, "a levitating player takes no damage from the trap")
  eq(game.level.traps[1].revealed, false, "the trap the player floated over stays hidden")
end

function tests.aLethalTrapKillsAWeakMonsterAndCreditsThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.traps = { { x = 6, y = 6, effect = "dart", revealed = false } }
  local rat = Monsters.create(Monsters.byKey.rat, 1, 7, 6, 1)
  rat.hp, rat.maxHp = 1, 1
  game.level.entities = { rat }
  local xpBefore = game.player.xp
  game:stepMonsterToward(rat, game.player.x, game.player.y)
  ok(not rat:isAlive(), "a dart trap can finish off a weak monster")
  ok(game.player.xp > xpBefore, "the player is credited xp for a trap kill")
  eq(#game.level.entities, 0, "the fallen monster is swept from the level")
end

function tests.aTeleportTrapRelocatesTheMonsterThatSpringsIt()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.traps = { { x = 6, y = 6, effect = "teleport", revealed = false } }
  local orc = Monsters.create(Monsters.byKey.orc, 1, 7, 6, 1)
  game.level.entities = { orc }
  game:stepMonsterToward(orc, game.player.x, game.player.y)
  ok(not (orc.x == 6 and orc.y == 6), "a teleport trap relocates the monster off the trapped cell")
end

function tests.kitsStayOffTheEntranceFloor()
  for seed = 1, 5 do
    local level = Builder.build(1, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      ok(ground.item.kind ~= Items.KIT, "no trap kit appears on the entrance floor")
    end
  end
end

function tests.plantedTrapFieldsSurviveSerialization()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Items.kit("poison") }
  game:useItem(1)
  local restoredLevel = Level.fromData(game.level:toData())
  eq(#restoredLevel.traps, 1, "the planted trap survives a level round trip")
  eq(restoredLevel.traps[1].effect, "poison", "the planted trap's effect survives a round trip")
  eq(restoredLevel.traps[1].placedByPlayer, true, "the planted trap's origin flag survives a round trip")
end

function tests.disarmSweepDetectsAHiddenTrapWithinOneStepEventuallyAcrossAHandfulOfSeeds()
  local detected = false
  for seed = 1, 100 do
    local level = { traps = { { x = 5, y = 5, effect = "dart", revealed = false } } }
    if #Disarm.sweep(level, Rng.new(seed), 5, 6) > 0 then detected = true break end
  end
  ok(detected, "an adjacent hidden trap is eventually detected across a handful of seeds")
end

function tests.disarmSweepNeverDetectsATrapTwoStepsAway()
  for seed = 1, 200 do
    local level = { traps = { { x = 5, y = 5, effect = "dart", revealed = false } } }
    eq(#Disarm.sweep(level, Rng.new(seed), 7, 7), 0,
      "a trap two steps away is never detected regardless of the roll")
  end
end

function tests.disarmSweepNeverRedetectsAnAlreadyDetectedOrRevealedTrap()
  local level = { traps = {
    { x = 5, y = 5, effect = "dart", revealed = false, detected = true },
    { x = 5, y = 6, effect = "dart", revealed = true },
  } }
  for seed = 1, 50 do
    eq(#Disarm.sweep(level, Rng.new(seed), 5, 5), 0,
      "neither an already-detected nor an already-sprung trap is swept again")
  end
end

function tests.disarmOddsForClimbWithLevelButNeverReachTheDenominator()
  local num1, den1 = Disarm.oddsFor({ level = 1 })
  eq(num1, Disarm.DISARM_BASE_NUMERATOR, "a fresh level-one player rolls the catalog's base odds")
  local num2, den2 = Disarm.oddsFor({ level = 100 })
  eq(den2, den1, "the denominator never changes with level")
  ok(num2 < den2, "even an extremely high level never reaches a guaranteed disarm")
  eq(num2, Disarm.DISARM_BASE_DENOMINATOR - 1, "the numerator caps a single point shy of the denominator")
end

function tests.disarmAttemptOnSuccessRemovesTheTrapAndPaysSalvage()
  local succeeded = false
  for seed = 1, 300 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local trap = { x = 4, y = 6, effect = "dart", revealed = false, detected = true }
    game.level.traps = { trap }
    local essenceBefore = game.player.essence
    local success, line = Disarm.attempt(game, trap)
    if success then
      eq(#game.level.traps, 0, "a successfully disarmed trap is removed from the level")
      ok(game.player.essence > essenceBefore, "a successful disarm pays out salvage essence")
      ok(contains(line, "disarm"), "the success is reported")
      succeeded = true
      break
    end
  end
  ok(succeeded, "disarming eventually succeeds across a handful of seeds")
end

function tests.disarmAttemptOnFailureSpringsTheTrapOnThePlayer()
  local failed = false
  for seed = 1, 300 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local trap = { x = 4, y = 6, effect = "dart", revealed = false, detected = true }
    game.level.traps = { trap }
    local hpBefore = game.player.hp
    local success = Disarm.attempt(game, trap)
    if not success then
      eq(trap.revealed, true, "a failed disarm springs the trap, revealing it")
      ok(game.player.hp < hpBefore, "a failed disarm's spring wounds the player exactly like a footstep would")
      failed = true
      break
    end
  end
  ok(failed, "disarming eventually fails across a handful of seeds")
end

function tests.gameDisarmTrapRefusesAnUndetectedOrAlreadySprungTrap()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local undetected = { x = 4, y = 6, effect = "dart", revealed = false }
  game.level.traps = { undetected }
  eq(game:disarmTrap(undetected), false, "an undetected trap refuses disarming outright")
  eq(#game.level.traps, 1, "the untouched trap is still there")

  local sprung = { x = 5, y = 6, effect = "dart", revealed = true, detected = true }
  eq(game:disarmTrap(sprung), false, "an already-sprung trap refuses disarming outright")
end

function tests.gameDisarmTrapSucceedsOrSpringsExactlyLikeDisarmAttempt()
  local sawSuccess, sawFailure = false, false
  for seed = 1, 300 do
    if sawSuccess and sawFailure then break end
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local trap = { x = 4, y = 6, effect = "dart", revealed = false, detected = true }
    game.level.traps = { trap }
    local hpBefore = game.player.hp
    if game:disarmTrap(trap) then
      eq(#game.level.traps, 0, "a successful disarm through the game wrapper removes the trap")
      sawSuccess = true
    else
      eq(trap.revealed, true, "a failed disarm through the game wrapper springs the trap")
      ok(game.player.hp <= hpBefore, "a failed disarm through the game wrapper can wound the player")
      sawFailure = true
    end
  end
  ok(sawSuccess, "the game wrapper eventually succeeds across a handful of seeds")
  ok(sawFailure, "the game wrapper eventually fails across a handful of seeds")
end

function tests.gameEndPlayerTurnEventuallyDetectsAnAdjacentTrapAcrossAHandfulOfSeeds()
  local noticed = false
  for seed = 1, 100 do
    local game = stagedGame(1, arena(21, 11), 3, 6)
    game.rng = Rng.new(seed)
    game.level.traps = { { x = 4, y = 6, effect = "dart", revealed = false } }
    game:endPlayerTurn()
    if game.level.traps[1].detected then
      local reported = false
      for _, line in ipairs(game.log:recent(6)) do
        if contains(line, "notice") then reported = true end
      end
      ok(reported, "a freshly detected trap is reported somewhere in the turn's log lines")
      noticed = true
      break
    end
  end
  ok(noticed, "an adjacent hidden trap is eventually detected during a normal turn across a handful of seeds")
end

function tests.trapDetectedFieldSurvivesSerialization()
  local game = Game.new(3)
  game.level.traps = { { x = 1, y = 1, effect = "dart", revealed = false, detected = true } }
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.level.traps[1].detected, true, "a trap's detected flag survives a save/load round trip")
end

return tests
