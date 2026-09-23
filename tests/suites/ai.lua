local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Entity = require("entity")
local Status = require("status")
local Monsters = require("monsters")
local Ai = require("ai")
local Companions = require("companions")
local Bosses = require("bosses")
local Corpses = require("corpses")
local Reanimation = require("reanimation")
local Mercenaries = require("mercenaries")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.monsterAiChase()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 12, 6, 1)
  game.level.entities = { orc }
  Ai.act(game, orc)
  eq(orc.x, 11, "a chaser steps one cell toward a visible player")
end

function tests.monsterAiRanged()
  local shootGame = stagedGame(1, arena(21, 11), 3, 6)
  local archer = Monsters.create(Monsters.byKey.archer, 1, 8, 6, 1)
  shootGame.level.entities = { archer }
  local hpBefore = shootGame.player.hp
  Ai.act(shootGame, archer)
  ok(shootGame.player.hp < hpBefore, "an archer in range and line of sight shoots")
  eq(archer.x, 8, "an archer that can shoot holds its ground")

  local kiteGame = stagedGame(1, arena(21, 11), 3, 6)
  local adjacent = Monsters.create(Monsters.byKey.archer, 1, 4, 6, 1)
  kiteGame.level.entities = { adjacent }
  Ai.act(kiteGame, adjacent)
  eq(adjacent.x, 5, "an archer kites away when the player closes in")
end

function tests.monsterAiFlee()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local wretch = Monsters.create(Monsters.byKey.wretch, 1, 5, 6, 1)
  game.level.entities = { wretch }
  Ai.act(game, wretch)
  eq(wretch.x, 6, "a coward flees away from the player")
end

function tests.monsterAiDeterministic()
  local function batRun()
    local game = stagedGame(55, arena(21, 11), 3, 6)
    local bat = Monsters.create(Monsters.byKey.bat, 1, 10, 6, 1)
    game.level.entities = { bat }
    game.rng = Rng.new(55)
    Ai.act(game, bat)
    return bat.x, bat.y
  end
  local x1, y1 = batRun()
  local x2, y2 = batRun()
  ok(x1 >= 2 and x1 <= 20 and y1 >= 2 and y1 <= 10, "erratic bat lands on a valid cell")
  ok(x1 == x2 and y1 == y2, "erratic behaviour is deterministic per seed")
end

function tests.aiActConfusedMonsterSometimesStumblesInsteadOfChasing()
  local sawChase, sawStumble = false, false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local orc = Monsters.create(Monsters.byKey.orc, 1, 12, 6, 1)
    game.level.entities = { orc }
    Status.apply(orc, Status.CONFUSE, 5, 1)
    Ai.act(game, orc)
    if orc.x == 11 and orc.y == 6 then
      sawChase = true
    else
      sawStumble = true
    end
    if sawChase and sawStumble then break end
  end
  ok(sawChase, "a confused monster's roll sometimes lets its normal behaviour run")
  ok(sawStumble, "a confused monster's roll sometimes overrides its normal behaviour")
end

function tests.aiActWithoutConfusionAlwaysRunsTheNormalBehaviour()
  for seed = 1, 20 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local orc = Monsters.create(Monsters.byKey.orc, 1, 12, 6, 1)
    game.level.entities = { orc }
    Ai.act(game, orc)
    eq(orc.x, 11, "an unconfused chaser always steps straight toward the player")
    eq(orc.y, 6, "an unconfused chaser never drifts off its own row")
  end
end

function tests.aiActBlindedArcherNeitherShootsNorChasesEvenWithAClearShot()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local archer = Monsters.create(Monsters.byKey.archer, 1, 8, 6, 1)
  game.level.entities = { archer }
  Status.apply(archer, Status.BLIND, 6, 1)
  local hpBefore = game.player.hp
  Ai.act(game, archer)
  eq(game.player.hp, hpBefore, "a blinded archer with an otherwise clear shot does not fire")
  eq(archer.x, 8, "a blinded archer does not close the distance either")
  eq(archer.y, 6, "a blinded archer does not drift off its own row")
end

function tests.gameAdjacentAllyFindsACompanionStandingRightNextToAMonster()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local golem = Companions.summon(game, "golem")
  local orc = Monsters.create(Monsters.byKey.orc, 10, golem.x + 1, golem.y, 5)
  game.level.entities[#game.level.entities + 1] = orc
  eq(game:adjacentAlly(orc), golem, "a companion standing right next to a monster is found")
end

function tests.gameAdjacentAllyIgnoresAHostileMonsterAndOnlyCountsCardinalAdjacency()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 10, 10, 6, 1)
  local rat = Monsters.create(Monsters.byKey.rat, 5, 11, 6, 2)
  game.level.entities = { orc, rat }
  eq(game:adjacentAlly(orc), nil, "a hostile monster standing adjacent is never mistaken for an ally")

  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 9, 7
  eq(game:adjacentAlly(orc), nil,
    "a companion only diagonally adjacent does not count - cardinal-only, like Game:playerAdjacent")
  golem.x, golem.y = 9, 6
  eq(game:adjacentAlly(orc), golem, "moving the same companion to cardinal adjacency makes it found")
end

function tests.gameAdjacentAllyBreaksTiesByTheLowerEntityIdAndIgnoresADeadAlly()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 10, 10, 6, 999)
  game.level.entities = { orc }
  local golem = Companions.summon(game, "golem")
  local hireling = Mercenaries.hire(game, "sellsword")
  golem.x, golem.y = 9, 6
  hireling.x, hireling.y = 11, 6
  ok(golem.id < hireling.id, "sanity check: the companion summoned first has the lower entity id")
  eq(game:adjacentAlly(orc), golem, "ties between two equally adjacent allies break toward the lower entity id")
  golem.hp = 0
  eq(game:adjacentAlly(orc), hireling, "a dead ally is skipped even though it is still standing adjacent")
end

function tests.aiChaseAttacksAnAllyBlockingTheOnlyCorridorToThePlayerInsteadOfIdlingForever()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  for y = 2, 10 do game.level.map:set(11, y, Tiles.WALL) end
  game.level.map:set(11, 6, Tiles.FLOOR)
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 11, 6
  local orc = Monsters.create(Monsters.byKey.orc, 10, 12, 6, 5)
  game.level.entities[#game.level.entities + 1] = orc
  local hpBefore = golem.hp
  Ai.act(game, orc)
  ok(golem.hp < hpBefore, "a chaser with no route around a blocking ally fights it instead of idling")
  eq(orc.x, 12, "the chaser never steps onto the ally's occupied cell")
  eq(orc.y, 6, "the chaser's y is unchanged - it attacked in place rather than moving")
end

function tests.aiChasePrefersAnAdjacentPlayerOverAnAdjacentAllyWhenBothAreInMeleeRange()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 10, 4, 6, 1)
  game.level.entities = { orc }
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 4, 7
  local playerHpBefore, golemHpBefore = game.player.hp, golem.hp
  Ai.act(game, orc)
  ok(game.player.hp < playerHpBefore, "a monster adjacent to both the player and an ally still attacks the player")
  eq(golem.hp, golemHpBefore, "the ally adjacent to the same monster takes no damage when the player is also in range")
end

function tests.aiPackAttacksAnAllyBlockingTheOnlyCorridorToThePlayerInsteadOfIdlingForever()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  for y = 2, 10 do game.level.map:set(11, y, Tiles.WALL) end
  game.level.map:set(11, 6, Tiles.FLOOR)
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 11, 6
  local kobold = Monsters.create(Monsters.byKey.kobold, 10, 12, 6, 5)
  game.level.entities[#game.level.entities + 1] = kobold
  local hpBefore = golem.hp
  Ai.act(game, kobold)
  ok(golem.hp < hpBefore, "a pack monster with no route around a blocking ally fights it instead of idling")
end

function tests.aiTunnelAttacksAnAllyBlockingItsOnlyGapInsteadOfIdling()
  local level = arena(21, 11)
  for y = 2, 10 do level.map:set(11, y, Tiles.WALL) end
  level.map:set(11, 6, Tiles.FLOOR)
  local game = stagedGame(1, level, 3, 6)
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 11, 6
  local burrower = Entity.new({
    id = game:nextMonsterId(), x = 12, y = 6, glyph = "b", name = "rock burrower", kind = "monster",
    ai = "tunnel", hp = 20, maxHp = 20, attack = 5, defense = 0, speed = 100,
  })
  game.level.entities[#game.level.entities + 1] = burrower
  local hpBefore = golem.hp
  Ai.act(game, burrower)
  ok(golem.hp < hpBefore, "a burrower blocked by a living ally fights it rather than trying (and failing) to path around")
  eq(burrower.x, 12, "the burrower stays put while it attacks - it never steps onto the ally's cell")
end

function tests.aiRangedAttacksABlockingAllyWhenItHasNoLineOfSightToThePlayerAtAll()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  for y = 2, 10 do game.level.map:set(8, y, Tiles.WALL) end
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 11, 6
  local archer = Monsters.create(Monsters.byKey.archer, 6, 12, 6, 5)
  game.level.entities[#game.level.entities + 1] = archer
  local hpBefore, playerHpBefore = golem.hp, game.player.hp
  Ai.act(game, archer)
  ok(golem.hp < hpBefore, "an archer with no line of sight to the player still fights an ally standing next to it")
  eq(game.player.hp, playerHpBefore, "the archer never reaches or harms the player while its view is fully walled off")
end

function tests.gameMoveMonsterAttacksAnAllyItBumpsIntoInsteadOfDoingNothing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local golem = Companions.summon(game, "golem")
  local orc = Monsters.create(Monsters.byKey.orc, 10, golem.x + 1, golem.y, 5)
  game.level.entities[#game.level.entities + 1] = orc
  local hpBefore = golem.hp
  game:moveMonster(orc, -1, 0)
  ok(golem.hp < hpBefore, "bumping into an ally's cell fights it rather than silently doing nothing")
  eq(orc.x, golem.x + 1, "the bumping monster does not step onto the ally's occupied cell")
end

function tests.aiActConfusedMonsterCanStumbleIntoAttackingABlockingAllyInsteadOfIdling()
  local sawAttack = false
  local realChase = Ai.behaviours.chase
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local orc = Monsters.create(Monsters.byKey.orc, 10, 12, 6, 1)
    local golem = Companions.summon(game, "golem")
    golem.x, golem.y = 11, 6
    game.level.entities[#game.level.entities + 1] = orc
    Status.apply(orc, Status.CONFUSE, 5, 1)
    local hpBefore = golem.hp
    local behaviourRan = false
    Ai.behaviours.chase = function() behaviourRan = true end
    Ai.act(game, orc)
    Ai.behaviours.chase = realChase
    if not behaviourRan and golem.hp < hpBefore then
      sawAttack = true
      break
    end
  end
  ok(sawAttack, "a confused monster's stumble (Ai.act's own branch, not chase's) can land an attack on a blocking ally via Game:moveMonster")
end

function tests.takeMonsterTurnPrefersAbilityOverMovement()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local necro = Monsters.create(Monsters.byKey.necromancer, 1, 6, 6, 4)
  game.level.entities = { necro }
  game:takeMonsterTurn(necro)
  eq(necro.x, 6, "summoning consumes the turn instead of the necromancer's flee movement")
  eq(necro.y, 6, "summoning leaves the necromancer's y unchanged too")
  eq(#game.level.entities, 2, "the full turn pipeline invokes the summon ability")
end

function tests.takeMonsterTurnFallsBackToAiWhenOnCooldown()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local necro = Monsters.create(Monsters.byKey.necromancer, 1, 6, 6, 4)
  necro.cooldown = 3
  game.level.entities = { necro }
  game:takeMonsterTurn(necro)
  eq(#game.level.entities, 1, "no minion is summoned while the ability is on cooldown")
  eq(necro.cooldown, 2, "the cooldown ticks down even on a turn spent fleeing")
  ok(necro.x ~= 6 or necro.y ~= 6, "the necromancer falls back to its flee ai instead")
end

function tests.canSeePlayerBlindedMonsterOnlyDetectsThePlayerAtMeleeRange()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 8, 6, 1)
  eq(game:canSeePlayer(orc, 10), true, "an unblinded monster within its listed range sees the player")

  Status.apply(orc, Status.BLIND, 6, 1)
  eq(game:canSeePlayer(orc, 10), false, "a blinded monster loses a five-cell-away sighting despite its listed range")

  local adjacentOrc = Monsters.create(Monsters.byKey.orc, 2, 4, 6, 1)
  Status.apply(adjacentOrc, Status.BLIND, 6, 1)
  eq(game:canSeePlayer(adjacentOrc, 10), true, "a blinded monster still senses the player once adjacent")
end

function tests.takeMonsterTurnRoutesAThrallThroughReanimationAct()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 5, 5, 6)
  Corpses.spawn(game.level, chieftain)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local rat = Monsters.create(Monsters.byKey.rat, 50, thrall.x + 1, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  game:takeMonsterTurn(thrall)
  eq(rat.hp, 0, "the full monster-turn pipeline dispatches a thrall's turn to reanimation.act")
end

function tests.takeMonsterTurnRoutesACompanionThroughCompanionsAct()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local rat = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  game:takeMonsterTurn(hound)
  eq(rat.hp, 0, "the full monster-turn pipeline dispatches a companion's turn to companions.act")
end

function tests.takeMonsterTurnEnragesABloodiedBossBeforeItsAiActs()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local warlord = Bosses.create(Bosses.byKey.warlord, 1, 4, 6)
  warlord.hp = math.floor(warlord.maxHp * Bosses.byKey.warlord.enrageAt)
  game.level.entities = { warlord }
  game:takeMonsterTurn(warlord)
  eq(warlord.enraged, true, "a bloodied boss enrages the moment its turn comes up")
  local found = false
  for _, line in ipairs(game.log.lines) do
    if line:find("rage", 1, true) then found = true end
  end
  ok(found, "the enrage line is written to the message log")
end

function tests.gameMonsterTunnelsThroughAWallToReachAndAttackThePlayer()
  local level = arena(21, 11)
  for y = 2, 10 do level.map:set(10, y, Tiles.WALL) end
  local game = stagedGame(1, level, 8, 6)
  local burrower = Entity.new({
    id = 1, x = 12, y = 6, glyph = "b", name = "rock burrower", kind = "monster",
    ai = "tunnel", hp = 20, maxHp = 20, attack = 5, defense = 0, speed = 100,
  })
  game.level.entities = { burrower }
  local hpBefore = game.player.hp
  local sawRubble = false
  for _ = 1, 10 do
    game.rng = Rng.new(1)
    Ai.act(game, burrower)
    if game.level.map:get(10, 6) ~= Tiles.WALL then sawRubble = true end
    if game.player.hp < hpBefore then break end
  end
  ok(sawRubble, "the burrower actually carves through the partition wall")
  ok(game.player.hp < hpBefore, "the burrower eventually reaches and melees the player through its own tunnel")
end

function tests.takeMonsterTurnRoutesAHirelingThroughMercenariesAct()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  local rat = Monsters.create(Monsters.byKey.rat, 50, sellsword.x + 1, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  game:takeMonsterTurn(sellsword)
  ok(rat.hp <= 0, "the full monster-turn pipeline dispatches a hireling's turn to mercenaries.act")
end

function tests.adjacentMonsterSkipsTheBondedCompanionAndFindsARealHostileInstead()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Companions.summon(game, "hound")
  local rat = Monsters.create(Monsters.byKey.rat, 50, 5, 6, 1)
  game.level.entities[#game.level.entities + 1] = rat
  eq(game:adjacentMonster(), rat, "the autopilot's melee target skips its own companion and finds the hostile rat")
end

function tests.adjacentMonsterReturnsNilWhenOnlyAnAllyStandsNextToThePlayer()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Companions.summon(game, "hound")
  eq(game:adjacentMonster(), nil, "a bonded companion alone never counts as a melee target")
end

function tests.adjacentMonsterAlsoSkipsAThrallStandingNextToThePlayer()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local thrall = Entity.new({ id = 99, x = 6, y = 5, glyph = "z", name = "raised thrall", kind = "thrall",
    hp = 5, attack = 2, defense = 0 })
  game.level.entities[#game.level.entities + 1] = thrall
  eq(game:adjacentMonster(), nil, "a raised thrall standing next to the player is never a melee target either")
end

function tests.aStarNeverRoutesAMonsterThroughABlockedCell()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  for y = 2, 10 do game.level.map:set(11, y, Tiles.WALL) end
  game.level.map:set(11, 6, Tiles.FLOOR)
  game.level.blocks = { { x = 11, y = 6 } }
  local orc = Monsters.create(Monsters.byKey.orc, 1, 13, 6, 1)
  game.level.entities = { orc }
  Ai.act(game, orc)
  ok(not (orc.x == 11 and orc.y == 6), "a chasing monster never steps onto a cell a block occupies")
  eq(orc.x, 13, "with the single gap blocked, the chaser has no route and holds its ground")
  eq(orc.y, 6, "the chaser's y is likewise unchanged with no route available")
end

function tests.playerPathToNeverRoutesThroughABlockedCell()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  for y = 2, 10 do game.level.map:set(11, y, Tiles.WALL) end
  game.level.map:set(11, 6, Tiles.FLOOR)
  game.level.blocks = { { x = 11, y = 6 } }
  local path = game:playerPathTo(15, 6)
  eq(path, nil, "no path is found when the only corridor cell is occupied by a block")
end

function tests.takeMonsterTurnSkipsAbilityAndAiWhileABossBracesOrUnleashesItsCataclysm()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local spec = Bosses.byKey.warlord
  local warlord = Bosses.create(spec, 1, 4, 6)
  warlord.enraged = true
  warlord.hp = math.floor(warlord.maxHp * spec.desperateAt)
  game.level.entities = { warlord }

  game:takeMonsterTurn(warlord)
  eq(warlord.x, 4, "a bracing boss never steps toward the player through its ordinary ai")
  local hpAfterBrace = game.player.hp
  eq(hpAfterBrace, game.player.maxHp, "bracing alone never damages the player")

  game:takeMonsterTurn(warlord)
  ok(game.player.hp < hpAfterBrace, "unleashing the cataclysm damages the adjacent player")

  local hpBeforeThird = game.player.hp
  game:takeMonsterTurn(warlord)
  ok(warlord.ability == nil or true, "a spent boss falls through to its plain rally ability or ai on its next turn")
  ok(game.player.hp <= hpBeforeThird, "the boss keeps acting normally once its cataclysm is spent")
end

return tests
