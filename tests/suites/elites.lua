local helpers = require("helpers")
local Rng = require("rng")
local Entity = require("entity")
local Status = require("status")
local Monsters = require("monsters")
local Builder = require("builder")
local Bosses = require("bosses")
local Elites = require("elites")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.eliteNeverPromotesBelowMinDepth()
  for seed = 1, 40 do
    local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 5, 2)
    Elites.maybePromote(Rng.new(seed), orc, 2)
    ok(not orc.elite, "no promotion below depth 3 regardless of the roll")
  end
end

function tests.eliteEligibleExcludesBossesAndTheShopkeeper()
  local boss = Bosses.create(Bosses.byKey.warlord, 1, 5, 5)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 2, 6, 5, 4)
  local orc = Monsters.create(Monsters.byKey.orc, 3, 7, 5, 3)
  ok(not Elites.eligible(boss), "a boss is never eligible for elite promotion")
  ok(not Elites.eligible(keeper), "the shopkeeper is never eligible for elite promotion")
  ok(Elites.eligible(orc), "a plain bestiary spawn is eligible for elite promotion")
end

function tests.eliteArmoredAffixAddsFlatDefenseAndPrefixesTheName()
  local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 5, 3)
  local baseDefense = orc.defense
  Elites.maybePromote(Rng.new(8), orc, 3)
  eq(orc.eliteTier, "elite", "a single-affix promotion is a plain elite, not a champion")
  eq(orc.eliteAffixes[1], "armored", "seed 8 rolls the armored affix at depth 3")
  eq(orc.defense, baseDefense + 3, "armored adds its flat defense bonus")
  eq(orc.baseDefense, baseDefense + 3, "armored's bonus also lands on baseDefense")
  eq(orc.name, "armored orc", "the affix name prefixes the species name")
end

function tests.eliteChampionTierAtDeepDepthRollsTwoDistinctAffixes()
  local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 5, 7)
  Elites.maybePromote(Rng.new(9), orc, 7)
  eq(orc.eliteTier, "champion", "seed 9 at depth 7 rolls a champion")
  eq(#orc.eliteAffixes, 2, "a champion carries exactly two affixes")
  ok(orc.eliteAffixes[1] ~= orc.eliteAffixes[2], "a champion never doubles up on the same affix")
end

function tests.eliteFieldsSurviveSerialization()
  local orc = Monsters.create(Monsters.byKey.orc, 1, 5, 5, 3)
  Elites.maybePromote(Rng.new(2), orc, 3)
  local restored = Entity.fromData(orc:toData())
  eq(restored.elite, true, "the elite flag survives serialization")
  eq(restored.eliteTier, "elite", "the elite tier survives serialization")
  eq(restored.eliteAffixes[1], "swift", "the rolled affix list survives serialization")
  eq(restored.speed, orc.speed, "the swift affix's speed bonus survives serialization")
end

function tests.elitesNeverAppearOnTheShallowestTwoFloors()
  for seed = 1, 20 do
    for depth = 1, 2 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, e in ipairs(level.entities) do
        ok(not e.elite, "no elite appears above depth 3")
      end
    end
  end
end

function tests.eliteVampiricMonsterDrainsHpFromThePlayerOnAMeleeHit()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.elite, orc.eliteAffixes = true, { "vampiric" }
  orc.hp = orc.maxHp - 5
  game.level.entities = { orc }
  local before = orc.hp
  game:monsterMelee(orc)
  ok(orc.hp > before, "a vampiric elite heals on the melee hit it lands")
end

function tests.eliteChillingMonsterSlowsThePlayerOnAMeleeHit()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.elite, orc.eliteAffixes = true, { "chilling" }
  game.level.entities = { orc }
  ok(not Status.has(game.player, Status.SLOW), "the player starts unslowed")
  game:monsterMelee(orc)
  ok(Status.has(game.player, Status.SLOW), "a chilling elite's hit leaves the player slowed")
end

function tests.eliteVolatileMonsterExplodesOnDeathDamagingAnAdjacentPlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.elite, rat.eliteAffixes = true, { "volatile" }
  rat.hp = 0
  game.level.entities = { rat }
  local before = game.player.hp
  game:awardKill(rat)
  ok(game.player.hp < before, "a volatile elite's corpse bursts, damaging the adjacent player")
  ok(contains(table.concat(game.log:recent(10), " "), "bursts"), "the burst is logged")
end

function tests.eliteVolatileBurstNamesEveryScorchedVictimAsANaturalList()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.elite, rat.eliteAffixes = true, { "volatile" }
  local goblin = Monsters.create(Monsters.byKey.goblin, 2, 5, 6, 1)
  local orc = Monsters.create(Monsters.byKey.orc, 3, 4, 7, 1)
  game.level.entities = { rat, goblin, orc }
  local line = Elites.onDeath(game, rat)
  ok(line:match("^rat bursts, scorching you for %d+, goblin for %d+ and orc for %d+$") ~= nil,
    "the burst line reads as a, b and c: " .. line)
end

function tests.eliteVolatileMonsterDoesNotBurstAnythingBeyondItsBlastRadius()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 6, 1)
  rat.elite, rat.eliteAffixes = true, { "volatile" }
  rat.hp = 0
  game.level.entities = { rat }
  local before = game.player.hp
  game:awardKill(rat)
  eq(game.player.hp, before, "a volatile corpse two cells away leaves the player untouched")
end

function tests.eliteKillGrantsBonusXpOverThePlainSpeciesReward()
  local game = stagedGame(9, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 1
  rat.elite, rat.eliteTier, rat.eliteAffixes = true, "elite", { "brutal" }
  game.level.entities = { rat }
  local baseXp = Monsters.xpFor(rat)
  local bonus = Elites.xpBonus(rat, baseXp)
  ok(bonus > 0, "the elite bonus is a real, nonzero amount")
  local xpBefore = game.player.xp
  game:playerAttack(rat)
  eq(game.player.xp, xpBefore + baseXp + bonus, "felling an elite grants a bonus over its plain species xp")
end

return tests
