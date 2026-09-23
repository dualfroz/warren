local helpers = require("helpers")
local Entity = require("entity")
local Monsters = require("monsters")
local Bosses = require("bosses")
local Stealth = require("stealth")

local ok, eq, contains, arena, stagedGame, wallSplitArena = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame, helpers.wallSplitArena

local tests = helpers.suite()

function tests.stealthHandBuiltMonsterDefaultsToAlertWhenAwarenessIsUnset()
  local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 5, 1)
  eq(orc.awareness, nil, "a monster built directly carries no awareness field at all")
  ok(not Stealth.isUnaware(orc), "an unset awareness field is treated as already alert, not asleep")
  eq(Stealth.sneakMultiplier(orc), 1, "no sneak bonus applies against an already-alert target")
end

function tests.stealthBossesStartFullyAlertRatherThanDormant()
  local warlord = Bosses.create(Bosses.byKey.warlord, 1, 5, 5)
  ok(not Stealth.isUnaware(warlord), "a named boss is never asleep, unlike a wild monster")
  eq(warlord.awareness, Stealth.HUNTING, "a boss starts directly in the hunting state")
end

function tests.stealthSpawnedMinionsStartHuntingRatherThanDormant()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local minion = game:spawnMinion("zombie", 10, 6)
  eq(minion.awareness, Stealth.HUNTING, "a minion summoned or split mid-fight is already aware, never asleep")
end

function tests.stealthDormantMonsterWakesImmediatelyWhenThePlayerStandsNextToIt()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.awareness = Stealth.DORMANT
  game.level.entities = { orc }
  local hpBefore = game.player.hp
  game:takeMonsterTurn(orc)
  eq(orc.awareness, Stealth.HUNTING, "a monster right next to the player always notices it")
  ok(game.player.hp < hpBefore, "the freshly woken monster still gets to act on the very same turn")
end

function tests.stealthDormantMonsterBeyondItsWakeRadiusNeverStirs()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 19, 6, 1)
  orc.awareness = Stealth.DORMANT
  game.level.entities = { orc }
  for _ = 1, 10 do
    game:takeMonsterTurn(orc)
  end
  eq(orc.awareness, Stealth.DORMANT, "a monster far outside its wake radius stays asleep no matter how many turns pass")
  eq(orc.x, 19, "an asleep monster that never wakes does not move")
  eq(orc.y, 6, "an asleep monster that never wakes does not move either")
end

function tests.stealthDormantMonsterWithinRangeEventuallyWakesOnASuccessfulRoll()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  orc.awareness = Stealth.DORMANT
  game.level.entities = { orc }
  local woke = false
  for _ = 1, 20 do
    game:takeMonsterTurn(orc)
    if orc.awareness ~= Stealth.DORMANT then woke = true; break end
  end
  ok(woke, "a monster well within its wake radius eventually notices the player across enough turns")
end

function tests.stealthMeleeAttackOnADormantMonsterDealsATripledSneakBonus()
  local sneakGame = stagedGame(1, arena(21, 11), 3, 6)
  local sneakOrc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  sneakOrc.awareness = Stealth.DORMANT
  sneakGame.level.entities = { sneakOrc }
  local before = sneakOrc.hp
  sneakGame:playerAttack(sneakOrc)
  local sneakDamage = before - sneakOrc.hp
  eq(sneakOrc.awareness, Stealth.HUNTING, "landing the blow wakes the target immediately")
  ok(contains(table.concat(sneakGame.log:recent(6), "\n"), "unaware"), "the log calls out the sneak attack")

  local plainGame = stagedGame(1, arena(21, 11), 3, 6)
  local plainOrc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  plainGame.level.entities = { plainOrc }
  local plainBefore = plainOrc.hp
  plainGame:playerAttack(plainOrc)
  local plainDamage = plainBefore - plainOrc.hp
  eq(sneakDamage, plainDamage * 3, "a sneak attack deals exactly triple the damage of the same hit thrown while already noticed")
end

function tests.stealthHuntingMonsterLosesTrackAndSwitchesToSearching()
  local game = stagedGame(1, wallSplitArena(), 15, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 6, 1)
  orc.awareness = Stealth.HUNTING
  orc.lastKnownX, orc.lastKnownY = 8, 6
  game.level.entities = { orc }
  for _ = 1, Stealth.LOST_TURNS_LIMIT do
    game:takeMonsterTurn(orc)
  end
  eq(orc.awareness, Stealth.SEARCHING, "losing sight of the player for several turns in a row switches a hunter to searching")
  eq(orc.x, 6, "the newly searching monster immediately takes its first step toward the last known position")
  eq(orc.y, 6, "the search movement heads straight down the open corridor")
end

function tests.stealthSearchingMonsterReacquiresThePlayerAndReturnsToHunting()
  local game = stagedGame(1, wallSplitArena(), 15, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 6, 1)
  orc.awareness = Stealth.HUNTING
  orc.lastKnownX, orc.lastKnownY = 8, 6
  game.level.entities = { orc }
  for _ = 1, Stealth.LOST_TURNS_LIMIT do
    game:takeMonsterTurn(orc)
  end
  game.player.x, game.player.y = 7, 6
  game:takeMonsterTurn(orc)
  eq(orc.awareness, Stealth.HUNTING, "regaining line of sight during a search snaps the monster straight back to hunting")
  eq(orc.lastKnownX, 7, "hunting again refreshes the last-known position to where the player actually is")
end

function tests.stealthSearchingMonsterGivesUpAndReturnsToDormant()
  local game = stagedGame(1, wallSplitArena(), 15, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 6, 1)
  orc.awareness = Stealth.HUNTING
  orc.lastKnownX, orc.lastKnownY = 8, 6
  game.level.entities = { orc }
  for _ = 1, 15 do
    game:takeMonsterTurn(orc)
  end
  eq(orc.awareness, Stealth.DORMANT, "abandoning a fruitless search puts the monster back to sleep")
  eq(orc.lastKnownX, nil, "a monster back asleep no longer remembers where it last saw the player")
end

function tests.stealthAwarenessFieldsSurviveASaveLoadRoundTrip()
  local orc = Monsters.create(Monsters.byKey.orc, 5, 6, 6, 1)
  orc.awareness = Stealth.SEARCHING
  orc.lastKnownX, orc.lastKnownY = 12, 9
  orc.lostTurns = 2
  orc.searchTurns = 1
  local restored = Entity.fromData(orc:toData())
  eq(restored.awareness, Stealth.SEARCHING, "the awareness state survives a round trip")
  eq(restored.lastKnownX, 12, "the last-known x coordinate survives a round trip")
  eq(restored.lastKnownY, 9, "the last-known y coordinate survives a round trip")
  eq(restored.lostTurns, 2, "the lost-turn counter survives a round trip")
  eq(restored.searchTurns, 1, "the search-turn counter survives a round trip")
end

return tests
