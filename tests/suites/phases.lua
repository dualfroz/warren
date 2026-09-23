local helpers = require("helpers")
local Entity = require("entity")
local Monsters = require("monsters")
local Bosses = require("bosses")
local Phases = require("phases")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.phasesTickIsANoOpForAPlainMonsterOrABossStillAboveItsDesperateThreshold()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 10, 6, 1)
  local line, consumed = Phases.tick(game, orc)
  eq(line, nil, "a plain monster never enters a desperation phase")
  eq(consumed, false, "a plain monster's turn is never consumed by Phases")

  local warlord = Bosses.create(Bosses.byKey.warlord, 2, 5, 6)
  line, consumed = Phases.tick(game, warlord)
  eq(line, nil, "a boss above its desperateAt threshold does not brace")
  eq(consumed, false, "an untouched boss's turn is never consumed by Phases")
end

function tests.phasesTickBracesOnceABloodiedBossCrossesDesperateAtSpikingDefenseAndConsumingTheTurn()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local spec = Bosses.byKey.warlord
  local warlord = Bosses.create(spec, 1, 5, 6)
  warlord.enraged = true
  warlord.hp = math.floor(warlord.maxHp * spec.desperateAt)
  local defenseBefore = warlord.defense

  local line, consumed = Phases.tick(game, warlord)
  ok(line ~= nil and line:find("channel", 1, true) ~= nil, "a bloodied boss logs that it begins channeling")
  eq(consumed, true, "bracing consumes the boss's entire turn")
  eq(warlord.desperate, true, "the boss is now flagged desperate")
  eq(warlord.channeling, true, "the boss is now flagged channeling, awaiting its next turn to unleash")
  eq(warlord.defense, defenseBefore + spec.desperateDefenseBonus, "bracing spikes defense by the catalog's flat bonus")
  eq(warlord.baseDefense, spec.defense + spec.desperateDefenseBonus, "bracing also lifts the boss's base defense")
end

function tests.phasesTickUnleashesOnTheTurnAfterBracingHittingThePlayerAndRevertingDefense()
  local game = stagedGame(1, arena(21, 11), 4, 6)
  local spec = Bosses.byKey.lich
  local lich = Bosses.create(spec, 1, 5, 6)
  lich.enraged = true
  lich.hp = math.floor(lich.maxHp * spec.desperateAt)
  Phases.tick(game, lich)
  local defenseBraced = lich.defense
  local hpBefore = game.player.hp

  local line, consumed = Phases.tick(game, lich)
  eq(consumed, true, "unleashing also consumes the boss's entire turn")
  eq(lich.channeling, false, "unleashing clears the channeling flag")
  eq(lich.novaSpent, true, "unleashing latches novaSpent permanently")
  eq(lich.defense, defenseBraced - spec.desperateDefenseBonus, "unleashing reverts the braced defense spike")
  eq(lich.defense, spec.defense, "the reverted defense lands back on the boss's unmodified catalog value")
  eq(game.player.hp, hpBefore - spec.novaDamage, "the cataclysm deals the catalog's flat nova damage to the player")
  ok(line:find("cataclysm", 1, true) ~= nil, "the unleash line names the cataclysm")
end

function tests.phasesUnleashHitsCompanionsAndHirelingsInRadiusButLeavesAWildMonsterUntouched()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local spec = Bosses.byKey.bonequeen
  local queen = Bosses.create(spec, 1, 10, 6)
  queen.enraged = true
  queen.hp = math.floor(queen.maxHp * spec.desperateAt)
  local ally = Entity.new({
    id = 2, x = 11, y = 6, glyph = "d", name = "wolf", kind = "companion",
    hp = 10, maxHp = 10, attack = 2, defense = 0, speed = 100,
  })
  local hireling = Entity.new({
    id = 3, x = 9, y = 7, glyph = "@", name = "sellsword", kind = "hireling",
    hp = 10, maxHp = 10, attack = 2, defense = 0, speed = 100,
  })
  local bystander = Monsters.create(Monsters.byKey.rat, 4, 10, 5, 1)
  game.level.entities = { queen, ally, hireling, bystander }
  game.player.x, game.player.y = 20, 10

  Phases.tick(game, queen)
  Phases.tick(game, queen)

  eq(ally.hp, 10 - spec.novaDamage, "a companion within radius takes the cataclysm's nova damage")
  eq(hireling.hp, 10 - spec.novaDamage, "a hireling within radius takes the cataclysm's nova damage")
  eq(bystander.hp, bystander.maxHp, "a wild monster caught nearby is never a cataclysm target")
end

function tests.phasesUnleashHitsAReanimatedThrallInRadiusJustLikeACompanionOrHireling()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local spec = Bosses.byKey.bonequeen
  local queen = Bosses.create(spec, 1, 10, 6)
  queen.enraged = true
  queen.hp = math.floor(queen.maxHp * spec.desperateAt)
  local thrall = Entity.new({
    id = 2, x = 11, y = 6, glyph = "Z", name = "rat thrall", kind = "thrall",
    hp = 10, maxHp = 10, attack = 2, defense = 0, speed = 100,
  })
  game.level.entities = { queen, thrall }
  game.player.x, game.player.y = 20, 10

  Phases.tick(game, queen)
  Phases.tick(game, queen)

  eq(thrall.hp, 10 - spec.novaDamage,
    "a player-raised thrall is just as much the boss's cornered party as a companion or hireling")
end

function tests.phasesUnleashNamesEveryTargetAsANaturalList()
  local game = stagedGame(1, arena(21, 11), 9, 6)
  local spec = Bosses.byKey.bonequeen
  local queen = Bosses.create(spec, 1, 10, 6)
  queen.enraged = true
  queen.hp = math.floor(queen.maxHp * spec.desperateAt)
  local ally = Entity.new({
    id = 2, x = 11, y = 6, glyph = "d", name = "wolf", kind = "companion",
    hp = 10, maxHp = 10, attack = 2, defense = 0, speed = 100,
  })
  local hireling = Entity.new({
    id = 3, x = 10, y = 7, glyph = "@", name = "sellsword", kind = "hireling",
    hp = 10, maxHp = 10, attack = 2, defense = 0, speed = 100,
  })
  game.level.entities = { queen, ally, hireling }

  Phases.tick(game, queen)
  local line = Phases.tick(game, queen)
  eq(line, string.format("%s unleashes a cataclysm on you, wolf and sellsword for %d", queen.name, spec.novaDamage),
    "the cataclysm line reads as a, b and c")
end

function tests.phasesNovaFiresAtMostOncePerBossThenFallsBackToItsOrdinaryAbility()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local spec = Bosses.byKey.warlord
  local warlord = Bosses.create(spec, 1, 5, 6)
  warlord.enraged = true
  warlord.hp = math.floor(warlord.maxHp * spec.desperateAt)
  Phases.tick(game, warlord)
  Phases.tick(game, warlord)

  local line, consumed = Phases.tick(game, warlord)
  eq(line, nil, "a boss that already spent its cataclysm never braces again")
  eq(consumed, false, "Phases stops consuming turns once the cataclysm is spent")
end

return tests
