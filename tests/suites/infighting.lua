local helpers = require("helpers")
local Map = require("map")
local Entity = require("entity")
local Status = require("status")
local Monsters = require("monsters")
local Level = require("level")
local Stealth = require("stealth")
local Infighting = require("infighting")
local Disease = require("disease")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.infightingTargetPicksTheNearestVisibleRivalOverACloserNonRival()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 10, 6, 1)
  local orc = Monsters.create(Monsters.byKey.orc, 2, 12, 6, 1)
  local rat = Monsters.create(Monsters.byKey.rat, 3, 9, 6, 1)
  game.level.entities = { goblin, orc, rat }
  local target = Infighting.target(game, goblin)
  eq(target.id, orc.id, "the goblin's rival target is the orc, not the nearer but unrelated rat")
end

function tests.infightingTargetIgnoresARivalBeyondSightRange()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 3, 6, 1)
  local farOrc = Monsters.create(Monsters.byKey.orc, 2, 19, 6, 1)
  game.level.entities = { goblin, farOrc }
  ok(Infighting.target(game, goblin) == nil, "a rival far beyond sight range is not a target")
end

function tests.infightingTargetIgnoresARivalBehindAWallEvenWithinSightRange()
  local map = Map.new(21, 11)
  for y = 2, 9 do
    for x = 2, 9 do map:set(x, y, Map.FLOOR) end
    for x = 12, 19 do map:set(x, y, Map.FLOOR) end
  end
  local level = Level.new({
    depth = 1, generator = "arena", map = map,
    entities = {}, floorItems = {}, traps = {}, lights = {}, dark = false, explored = {},
    upX = 2, upY = 2, downX = 19, downY = 9,
  })
  local game = stagedGame(1, level, 2, 2)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 9, 5, 1)
  local orc = Monsters.create(Monsters.byKey.orc, 2, 12, 5, 1)
  game.level.entities = { goblin, orc }
  ok(Infighting.target(game, goblin) == nil,
    "a rival on the far side of a solid wall is not a target despite being close in raw distance")
end

function tests.infightingTargetIgnoresNonRivalsWithoutDiscord()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 10, 6, 1)
  local rat = Monsters.create(Monsters.byKey.rat, 2, 11, 6, 1)
  game.level.entities = { goblin, rat }
  ok(Infighting.target(game, goblin) == nil, "an unrelated species is never a target on its own")
end

function tests.infightingTargetUnderDiscordPicksNearestCreatureOfAnyKindIncludingACompanion()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 10, 6, 1)
  Status.apply(orc, Status.DISCORD, 5, 1)
  local companion = Entity.new({
    id = 2, x = 11, y = 6, glyph = "d", name = "wolf", kind = "companion",
    hp = 10, maxHp = 10, attack = 2, defense = 0, speed = 100,
  })
  local rat = Monsters.create(Monsters.byKey.rat, 3, 15, 6, 1)
  game.level.entities = { orc, companion, rat }
  local target = Infighting.target(game, orc)
  eq(target.id, companion.id,
    "a discorded monster attacks the nearest creature of any kind, even a companion, over a farther non-rival")
end

function tests.infightingTargetReturnsNilOnceDiscordHasExpired()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 10, 6, 1)
  local rat = Monsters.create(Monsters.byKey.rat, 2, 11, 6, 1)
  game.level.entities = { orc, rat }
  ok(Infighting.target(game, orc) == nil, "without discord an orc has no quarrel with a nearby rat")
end

function tests.infightingStrikeOnAPlainMonsterSpawnsACorpseButAwardsThePlayerNothing()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 10, 6, 1)
  local orc = Monsters.create(Monsters.byKey.orc, 2, 11, 6, 1)
  orc.hp, orc.maxHp = 1, 1
  game.level.entities = { goblin, orc }
  local xpBefore = game.player.xp
  local killsBefore = game.stats.kills
  Infighting.strike(game, goblin, orc)
  ok(not orc:isAlive(), "the orc dies to the goblin's blow")
  eq(game.player.xp, xpBefore, "the player earns no xp for a kill it did not land")
  eq(game.stats.kills, killsBefore, "the run's kill counter only tracks the player's own kills")
  eq(#game.level.corpses, 1, "the fallen orc still leaves a corpse behind for scavenging or reanimation")
  ok(contains(game.log:last(), "dies"), "the death is still logged")
end

function tests.infightingStrikeThatKillsACompanionRoutesThroughTheNormalAllyDeathMessage()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 10, 6, 1)
  local wolf = Entity.new({
    id = 2, x = 11, y = 6, glyph = "d", name = "wolf", kind = "companion",
    hp = 1, maxHp = 10, attack = 2, defense = 0, speed = 100,
  })
  game.level.entities = { orc, wolf }
  Infighting.strike(game, orc, wolf)
  ok(contains(game.log:last(), "falls"), "a companion killed by infighting dies with the same message as any other death")
end

function tests.infightingStrikeEmitsNoiseThatCanStirADormantBystanderNotInvolvedInTheFight()
  local stirred = false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 3)
    local goblin = Monsters.create(Monsters.byKey.goblin, 1, 10, 6, 1)
    local orc = Monsters.create(Monsters.byKey.orc, 2, 11, 6, 1)
    local bystander = Monsters.create(Monsters.byKey.rat, 3, 14, 6, 1)
    bystander.awareness = Stealth.DORMANT
    game.level.entities = { goblin, orc, bystander }
    Infighting.strike(game, goblin, orc)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "two monsters brawling among themselves are exactly as loud as any other fight")
end

function tests.infightingStrikeAppliesTheAttackersEliteLifestealAgainstAnyDefenderNotJustThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 10, 6, 1)
  orc.elite, orc.eliteAffixes = true, { "vampiric" }
  orc.hp = orc.maxHp - 5
  local wolf = Entity.new({
    id = 2, x = 11, y = 6, glyph = "d", name = "wolf", kind = "companion",
    hp = 20, maxHp = 20, attack = 2, defense = 0, speed = 100,
  })
  game.level.entities = { orc, wolf }
  local before = orc.hp
  Infighting.strike(game, orc, wolf)
  ok(orc.hp > before, "a vampiric elite heals on an infighting hit exactly as it does against the player")
  ok(contains(game.log:last(), "wolf"), "the drain message names the actual victim, not the player")
  ok(not contains(game.log:last(), "you"), "a wolf being drained is never described as draining \"you\"")
end

function tests.infightingStrikeAppliesTheAttackersEliteOnHitRiderAgainstAnyDefenderNotJustThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 10, 6, 1)
  orc.elite, orc.eliteAffixes = true, { "chilling" }
  local wolf = Entity.new({
    id = 2, x = 11, y = 6, glyph = "d", name = "wolf", kind = "hireling",
    hp = 20, maxHp = 20, attack = 2, defense = 0, speed = 100,
  })
  game.level.entities = { orc, wolf }
  ok(not Status.has(wolf, Status.SLOW), "the hireling starts unslowed")
  Infighting.strike(game, orc, wolf)
  ok(Status.has(wolf, Status.SLOW), "a chilling elite's infighting hit slows its actual victim, not just the player")
  ok(contains(game.log:last(), "wolf"), "the rider message names the actual victim, not the player")
end

function tests.infightingStrikeCanTransmitTheAttackersBiteDiseaseToAnyDefenderNotJustThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 10, 6, 1)
  eq(rat.biteDisease, Disease.PARASITES, "a rat carries parasites to begin with")
  local wolf = Entity.new({
    id = 2, x = 11, y = 6, glyph = "d", name = "wolf", kind = "companion",
    hp = 10000, maxHp = 10000, attack = 2, defense = 0, speed = 100,
  })
  game.level.entities = { rat, wolf }
  local infected = false
  for _ = 1, 400 do
    Infighting.strike(game, rat, wolf)
    if Disease.isInfected(wolf) then infected = true break end
  end
  ok(infected, "enough infighting bites from a parasite-carrying rival eventually infect a companion, not just the player")
  eq(wolf.disease.key, Disease.PARASITES, "the companion caught exactly the rat's own carried affliction")
  ok(contains(game.log:last(), "wolf"), "the infection message names the actual victim, not the player")
end

function tests.infightingTryActAttacksAnAdjacentRivalAndReturnsTrue()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 10, 6, 1)
  local orc = Monsters.create(Monsters.byKey.orc, 2, 11, 6, 1)
  game.level.entities = { goblin, orc }
  local hpBefore = orc.hp
  local acted = Infighting.tryAct(game, goblin)
  ok(acted, "infighting consumes the goblin's turn when an adjacent rival is present")
  ok(orc.hp < hpBefore, "the adjacent rival takes damage")
end

function tests.infightingTryActStepsTowardADistantRivalAndReturnsTrue()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 10, 6, 1)
  local orc = Monsters.create(Monsters.byKey.orc, 2, 14, 6, 1)
  game.level.entities = { goblin, orc }
  local acted = Infighting.tryAct(game, goblin)
  ok(acted, "infighting consumes the goblin's turn even while the rival is still distant")
  eq(goblin.x, 11, "the goblin steps one cell toward the distant rival instead of standing still")
end

function tests.infightingTryActReturnsFalseWithNoQualifyingTarget()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 10, 6, 1)
  local rat = Monsters.create(Monsters.byKey.rat, 2, 11, 6, 1)
  game.level.entities = { goblin, rat }
  ok(not Infighting.tryAct(game, goblin), "infighting yields the turn back to Ai.act when nothing qualifies")
end

function tests.gameTakeMonsterTurnLetsARivalFightInsteadOfChasingADistantPlayer()
  local game = stagedGame(1, arena(21, 11), 19, 9)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 10, 6, 1)
  local orc = Monsters.create(Monsters.byKey.orc, 2, 11, 6, 1)
  game.level.entities = { goblin, orc }
  local hpBefore = orc.hp
  game:takeMonsterTurn(goblin)
  ok(orc.hp < hpBefore, "a goblin that could chase a distant player instead fights the adjacent rival orc")
  eq(goblin.x, 10, "fighting the rival in place keeps the goblin from stepping toward the player")
end

return tests
