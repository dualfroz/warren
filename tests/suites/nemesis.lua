local helpers = require("helpers")
local Entity = require("entity")
local Monsters = require("monsters")
local Level = require("level")
local Game = require("game")
local Bosses = require("bosses")
local Stealth = require("stealth")
local Mimics = require("mimics")
local Graves = require("graves")
local Nemesis = require("nemesis")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.nemesisIsEligibleRequiresAHuntingHostileAndExcludesEverySpecialCase()
  local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 5, 1)
  ok(not Nemesis.isEligible(orc), "a monster that has not noticed the player yet is not eligible")
  orc.awareness = Stealth.HUNTING
  ok(Nemesis.isEligible(orc), "a hunting monster under a self-directed ai is eligible")

  local wretch = Monsters.create(Monsters.byKey.wretch, 2, 5, 5, 1)
  wretch.awareness = Stealth.HUNTING
  ok(not Nemesis.isEligible(wretch), "a permanent flee species never gives chase down a stairwell")

  local shopkeeper = Monsters.create(Monsters.byKey.shopkeeper, 3, 5, 5, 4)
  shopkeeper.awareness = Stealth.HUNTING
  ok(not Nemesis.isEligible(shopkeeper), "the shopkeeper's vend ai is never eligible")

  local boss = Bosses.create(Bosses.byKey.lich, 4, 5, 5)
  boss.awareness = Stealth.HUNTING
  ok(not Nemesis.isEligible(boss), "a boss already has its own escalation path")

  local elite = Monsters.create(Monsters.byKey.orc, 5, 5, 5, 3)
  elite.awareness, elite.elite = Stealth.HUNTING, true
  ok(not Nemesis.isEligible(elite), "an elite already has its own escalation path")

  local mimic = Mimics.reveal(6, 5, 5, 3)
  mimic.awareness = Stealth.HUNTING
  ok(not Nemesis.isEligible(mimic), "a revealed mimic already has its own escalation path")

  local shade = Graves.reveal(7, 5, 5, {})
  shade.awareness = Stealth.HUNTING
  ok(not Nemesis.isEligible(shade), "a grave shade already has its own escalation path")

  local dead = Monsters.create(Monsters.byKey.rat, 8, 5, 5, 1)
  dead.awareness, dead.hp = Stealth.HUNTING, 0
  ok(not Nemesis.isEligible(dead), "a dead monster cannot give chase")

  local already = Monsters.create(Monsters.byKey.rat, 9, 5, 5, 1)
  already.awareness, already.nemesis = Stealth.HUNTING, true
  ok(not Nemesis.isEligible(already), "an existing nemesis cannot spawn a second one")
end

function tests.nemesisPickHunterReturnsTheNearestEligibleHunterBreakingTiesByListOrder()
  local player = Entity.new({ x = 5, y = 5, glyph = "@", name = "you", kind = "player", hp = 20, attack = 5, defense = 1 })
  local level = arena(21, 11)
  local far = Monsters.create(Monsters.byKey.orc, 1, 15, 5, 1)
  far.awareness = Stealth.HUNTING
  local dormant = Monsters.create(Monsters.byKey.orc, 2, 6, 5, 1)
  local near = Monsters.create(Monsters.byKey.orc, 3, 7, 5, 1)
  near.awareness = Stealth.HUNTING
  level.entities = { far, dormant, near }
  eq(Nemesis.pickHunter(level, player), near, "the nearest eligible hunter wins over a dormant closer monster and a farther one")

  local tie = Monsters.create(Monsters.byKey.orc, 4, 3, 5, 1)
  tie.awareness = Stealth.HUNTING
  level.entities = { near, tie }
  eq(Nemesis.pickHunter(level, player), near, "an equidistant tie is broken by earlier list order")

  level.entities = { dormant }
  eq(Nemesis.pickHunter(level, player), nil, "no eligible hunter on the floor returns nil")
end

function tests.nemesisBeginFromCapturesSpeciesAndHpFractionAtGrudgeOne()
  local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 5, 1)
  orc.hp = orc.maxHp // 2
  local pursuit = Nemesis.beginFrom(orc)
  eq(pursuit.species, "orc", "the pursuit remembers which species is following")
  eq(pursuit.grudge, 1, "a freshly begun pursuit starts at grudge one")
  eq(pursuit.hpFraction, 0.5, "the pursuit captures the hunter's hp fraction at the moment it gave chase")
end

function tests.nemesisEscalateRaisesGrudgeAndHealsTowardFullBothCapped()
  local pursuit = { species = "orc", grudge = 1, hpFraction = 0.3 }
  Nemesis.escalate(pursuit)
  eq(pursuit.grudge, 2, "escalating raises the grudge by one")
  eq(pursuit.hpFraction, 0.5, "escalating heals the pursuit's carried hp fraction")
  for _ = 1, 10 do Nemesis.escalate(pursuit) end
  eq(pursuit.grudge, Nemesis.MAX_GRUDGE, "grudge never climbs past its cap")
  eq(pursuit.hpFraction, 1, "hp fraction never heals past full")
end

function tests.nemesisSpawnScalesHpAndAttackWithGrudgeAndAppliesTheCarriedHpFraction()
  local base = Monsters.create(Monsters.byKey.orc, 1, 5, 5, 1)
  local weak = Nemesis.spawn({ species = "orc", grudge = 1, hpFraction = 0.5 }, 2, 5, 5, 1)
  eq(weak.maxHp, base.maxHp + Nemesis.bonusHp(1), "a grudge-one nemesis carries a small hp bonus over the plain species")
  eq(weak.hp, math.floor(weak.maxHp * 0.5), "the spawned nemesis's hp reflects its carried hp fraction")
  eq(weak.attack, base.attack + Nemesis.bonusAttack(1), "a grudge-one nemesis carries a small attack bonus")
  ok(weak.nemesis, "the spawned entity is flagged as a nemesis")
  eq(weak.nemesisGrudge, 1, "the spawned entity remembers its own grudge tier")
  eq(weak.species, "orc", "the spawned nemesis keeps the species key its xp/faction lookups depend on")

  local fierce = Nemesis.spawn({ species = "orc", grudge = 4, hpFraction = 1 }, 3, 5, 5, 1)
  ok(fierce.maxHp > weak.maxHp, "a higher grudge nemesis carries a larger hp bonus")
  ok(fierce.attack > weak.attack, "a higher grudge nemesis carries a larger attack bonus")

  local sliver = Nemesis.spawn({ species = "orc", grudge = 1, hpFraction = 0.001 }, 4, 5, 5, 1)
  ok(sliver.hp >= 1, "a nemesis spawned from a nearly-dead fraction never rounds down to zero hp")
end

function tests.nemesisNameForEscalatesThroughEachEpithetAndClampsAtTheLast()
  eq(Nemesis.nameFor("orc", 1), "orc, " .. Nemesis.EPITHETS[1], "grudge one uses the first epithet")
  eq(Nemesis.nameFor("orc", #Nemesis.EPITHETS), "orc, " .. Nemesis.EPITHETS[#Nemesis.EPITHETS],
    "grudge at the epithet count uses the last epithet")
  eq(Nemesis.nameFor("orc", Nemesis.MAX_GRUDGE + 5), "orc, " .. Nemesis.EPITHETS[#Nemesis.EPITHETS],
    "grudge beyond the epithet list clamps to the last epithet rather than indexing past it")
end

function tests.nemesisXpBonusAndBountyGoldScaleWithGrudge()
  ok(Nemesis.xpBonus(2) > Nemesis.xpBonus(1), "a higher grudge pays a bigger xp bonus")
  ok(Nemesis.bountyGold(2) > Nemesis.bountyGold(1), "a higher grudge pays a bigger bounty")
  eq(Nemesis.bountyGold(1), 10, "grudge one's bounty matches the catalog base")
end

function tests.gameDescendCanRollANewNemesisFromAHuntingMonsterLeftOnTheDepartingFloor()
  local game = stagedGame(3, arena(21, 11), 2, 2)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 10, 6, 1)
  orc.awareness = Stealth.HUNTING
  game.level.entities = { orc }
  game.player.x, game.player.y = game.level.downX, game.level.downY
  game:descend()
  ok(game.nemesis ~= nil, "this seed's departure roll gives the hunting orc a chance to follow")
  eq(game.nemesis.species, "orc", "the nemesis descriptor remembers which species followed")
  local found
  for _, entity in ipairs(game.level.entities) do
    if entity.nemesis then found = entity end
  end
  ok(found ~= nil, "the nemesis is actually placed onto the floor just reached")
  eq(found.nemesisGrudge, 1, "a freshly emerged nemesis starts at grudge one")
end

function tests.gameDescendNeverRollsANewNemesisFromAMonsterThatIsNotActuallyHunting()
  for seed = 1, 30 do
    local game = stagedGame(seed, arena(21, 11), 2, 2)
    local orc = Monsters.create(Monsters.byKey.orc, 1, 10, 6, 1)
    game.level.entities = { orc }
    game.player.x, game.player.y = game.level.downX, game.level.downY
    game:descend()
    ok(game.nemesis == nil, "a dormant monster never gives chase no matter the seed")
  end
end

function tests.gameNemesisFollowsAcrossMultipleDescentsEscalatingItsGrudgeEachTime()
  local game = stagedGame(1, arena(21, 11), 2, 2)
  game.nemesis = { species = "orc", grudge = 1, hpFraction = 1 }
  local hunter = Nemesis.spawn(game.nemesis, game:nextMonsterId(), 10, 6, 1)
  game.level.entities = { hunter }
  game.player.x, game.player.y = game.level.downX, game.level.downY

  game:descend()
  eq(game.nemesis.grudge, 2, "following once past the first stairwell raises the grudge to two")
  local first
  for _, entity in ipairs(game.level.entities) do if entity.nemesis then first = entity end end
  ok(first ~= nil, "the escalated nemesis is placed on the second floor")
  eq(first.nemesisGrudge, 2, "the respawned nemesis carries the escalated grudge")

  game.player.x, game.player.y = game.level.downX, game.level.downY
  game:descend()
  eq(game.nemesis.grudge, 3, "following a second time raises the grudge again")
  local second
  for _, entity in ipairs(game.level.entities) do if entity.nemesis then second = entity end end
  ok(second ~= nil, "the nemesis follows onto the third floor too")
  local nemesisCount = 0
  for _, entity in ipairs(game.level.entities) do
    if entity.nemesis then nemesisCount = nemesisCount + 1 end
  end
  eq(nemesisCount, 1, "exactly one nemesis is ever on a floor at a time, never a duplicate")
end

function tests.gameAscendCarriesAnActiveNemesisAlongButNeverRollsANewOne()
  local game = stagedGame(1, arena(21, 11), 2, 2)
  game.player.x, game.player.y = game.level.downX, game.level.downY
  game:descend()
  eq(game.depth, 2, "the game is now on the second floor")
  eq(game.nemesis, nil, "no nemesis was following yet")

  for seed = 1, 20 do
    local ascendGame = stagedGame(seed, arena(21, 11), 2, 2)
    ascendGame.player.x, ascendGame.player.y = ascendGame.level.downX, ascendGame.level.downY
    ascendGame:descend()
    local orc = Monsters.create(Monsters.byKey.orc, 99, 10, 6, ascendGame.depth)
    orc.awareness = Stealth.HUNTING
    ascendGame.level.entities = { orc }
    ascendGame.player.x, ascendGame.player.y = ascendGame.level.upX, ascendGame.level.upY
    ascendGame:ascend()
    ok(ascendGame.nemesis == nil, "climbing back up never manufactures a brand new nemesis")
  end

  local followGame = stagedGame(1, arena(21, 11), 2, 2)
  followGame.player.x, followGame.player.y = followGame.level.downX, followGame.level.downY
  followGame:descend()
  followGame.nemesis = { species = "orc", grudge = 2, hpFraction = 1 }
  local hunter = Nemesis.spawn(followGame.nemesis, followGame:nextMonsterId(), 10, 6, followGame.depth)
  followGame.level.entities = { hunter }
  followGame.player.x, followGame.player.y = followGame.level.upX, followGame.level.upY
  followGame:ascend()
  eq(followGame.nemesis.grudge, 3, "an already-active nemesis still follows the player back up the stairs")
  local found
  for _, entity in ipairs(followGame.level.entities) do if entity.nemesis then found = entity end end
  ok(found ~= nil, "the nemesis is placed on the floor just climbed back onto")
end

function tests.gameAwardKillOnANemesisGrantsBonusXpAndBountyGoldAndClearsTheHunt()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.nemesis = { species = "orc", grudge = 3, hpFraction = 1 }
  local hunter = Nemesis.spawn(game.nemesis, 1, 4, 6, 1)
  hunter.hp = 1
  game.level.entities = { hunter }
  local xpBefore, goldBefore = game.player.xp, game.player.gold
  game:playerAttack(hunter)
  ok(game.player.xp > xpBefore or game.player.level > 1, "felling the nemesis grants xp on top of its species reward")
  eq(game.player.gold, goldBefore + Nemesis.bountyGold(3), "felling the nemesis pays out its grudge-scaled bounty gold")
  eq(game.nemesis, nil, "the hunt is over once the nemesis is actually killed")
  ok(contains(table.concat(game.log:recent(5), " "), "hunt is over"), "the kill is logged as ending the hunt")
end

function tests.nemesisFieldsSurviveEntityAndGameSerialization()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.nemesis = { species = "orc", grudge = 3, hpFraction = 0.75 }
  local hunter = Nemesis.spawn(game.nemesis, 1, 6, 5, 1)
  game.level.entities = { hunter }

  local restoredLevel = Level.fromData(game.level:toData())
  eq(restoredLevel.entities[1].nemesis, true, "the nemesis flag survives a level round trip")
  eq(restoredLevel.entities[1].nemesisGrudge, 3, "the nemesis's grudge survives a level round trip")

  local restoredGame = Game.fromData(game:toData())
  eq(restoredGame.nemesis.species, "orc", "the pursuing nemesis descriptor survives a game round trip")
  eq(restoredGame.nemesis.grudge, 3, "the descriptor's grudge survives a game round trip")
  eq(restoredGame.nemesis.hpFraction, 0.75, "the descriptor's carried hp fraction survives a game round trip")
end

return tests
