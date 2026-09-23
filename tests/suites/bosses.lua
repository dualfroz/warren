local helpers = require("helpers")
local Rng = require("rng")
local Status = require("status")
local Monsters = require("monsters")
local Level = require("level")
local Builder = require("builder")
local Crafting = require("crafting")
local Artifacts = require("artifacts")
local Bosses = require("bosses")
local Resistances = require("resistances")
local Phases = require("phases")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.bossCreateBuildsAFreshUnenragedBoss()
  local warlord = Bosses.create(Bosses.byKey.warlord, 9, 4, 6)
  eq(warlord.isBoss, true, "a created boss is flagged isBoss")
  eq(warlord.bossKey, "warlord", "a created boss remembers its catalog key")
  eq(warlord.enraged, false, "a freshly created boss has not yet enraged")
  eq(warlord.hp, warlord.maxHp, "a created boss starts at full hp")
  eq(warlord.species, "boss_warlord", "a created boss's species is namespaced away from Monsters.byKey")
end

function tests.bossAtFullHealthDoesNotEnrage()
  local warlord = Bosses.create(Bosses.byKey.warlord, 1, 1, 1)
  local before = warlord.attack
  local line = Bosses.tryEnrage(warlord)
  eq(line, nil, "a boss above its enrage threshold does not enrage")
  eq(warlord.enraged, false, "the boss is still marked as not enraged")
  eq(warlord.attack, before, "an unenraged boss keeps its base attack")
end

function tests.bossEnragesOncePastItsHalfHpThresholdAndOnlyOnce()
  local warlord = Bosses.create(Bosses.byKey.warlord, 1, 1, 1)
  local spec = Bosses.byKey.warlord
  warlord.hp = math.floor(warlord.maxHp * spec.enrageAt)
  local attackBefore, speedBefore = warlord.attack, warlord.speed
  local line = Bosses.tryEnrage(warlord)
  ok(line ~= nil, "a bloodied boss enrages and logs a line")
  eq(warlord.enraged, true, "the boss is now flagged enraged")
  eq(warlord.attack, attackBefore + spec.enrageAttack, "enraging adds the catalog's flat attack bonus")
  eq(warlord.baseAttack, attackBefore + spec.enrageAttack, "enraging also lifts the boss's base attack")
  eq(warlord.speed, speedBefore + spec.enrageSpeed, "enraging adds the catalog's flat speed bonus")
  local hpAfterFirst = warlord.hp
  local second = Bosses.tryEnrage(warlord)
  eq(second, nil, "an already-enraged boss does not enrage a second time")
  eq(warlord.attack, attackBefore + spec.enrageAttack, "a second call never stacks the attack bonus again")
  eq(warlord.hp, hpAfterFirst, "a second call grants no further heal")
end

function tests.bossLootMatchesItsCatalogEntry()
  local lich = Bosses.create(Bosses.byKey.lich, 1, 1, 1)
  local loot = Bosses.lootFor(lich)
  ok(loot ~= nil, "a boss with a valid bossKey drops its catalog loot")
  eq(loot.artifact, "lich_phylactery", "the dropped item is the boss's exact catalog artifact")
  eq(loot.unique, Artifacts.REGEN, "the boss loot carries its unique mechanic tag")
  local unknown = Bosses.create({ key = "ghost" }, 1, 1, 1)
  unknown.bossKey = "ghost"
  eq(Bosses.lootFor(unknown), nil, "a boss with no catalog entry drops nothing")
end

function tests.bossOnlyArtifactsAreExcludedFromTheRandomBuilderRoll()
  local bossOnlyKeys = { "warlords_cleaver", "lich_phylactery", "bone_queen_carapace" }
  for _, key in ipairs(bossOnlyKeys) do
    ok(Artifacts.byKey[key] ~= nil, key .. " is a real catalog entry")
    local inOrder = false
    for _, orderKey in ipairs(Artifacts.order) do
      if orderKey == key then inOrder = true end
    end
    ok(not inOrder, key .. " never appears in the builder's random artifact roll")
  end
end

function tests.bossesStayOffFloorsAboveDepthSix()
  for seed = 1, 5 do
    for depth = 1, 5 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, entity in ipairs(level.entities) do
        ok(not entity.isBoss, "no boss appears above depth 6")
      end
    end
  end
end

function tests.defeatingABossGrantsBossXpAndDropsItsGuaranteedArtifact()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local lich = Bosses.create(Bosses.byKey.lich, 1, 4, 6)
  lich.hp = 1
  game.level.entities = { lich }
  local levelBefore = game.player.level
  local essenceBefore = game.player.essence
  game:playerAttack(lich)
  ok(game.player.level > levelBefore, "a boss's xp reward is enough to level the player up")
  eq(game.player.essence, essenceBefore + Crafting.essenceFor(Bosses.xpFor(lich)),
    "felling a boss grants essence scaled to its catalog xp, not a plain monster's")
  local dropped
  for _, ground in ipairs(game.level.floorItems) do
    if ground.item.artifact == "lich_phylactery" then dropped = ground.item end
  end
  ok(dropped ~= nil, "the boss's guaranteed artifact lands on the floor where it died")
end

function tests.bossFieldsSurviveSerialization()
  local game = stagedGame(3, arena(21, 11), 5, 5)
  local warlord = Bosses.create(Bosses.byKey.warlord, 1, 6, 5)
  warlord.hp = math.floor(warlord.maxHp * Bosses.byKey.warlord.enrageAt)
  Bosses.tryEnrage(warlord)
  game.level.entities = { warlord }
  local restoredLevel = Level.fromData(game.level:toData())
  eq(#restoredLevel.entities, 1, "the boss survives a level round trip")
  eq(restoredLevel.entities[1].isBoss, true, "the boss's isBoss flag survives a round trip")
  eq(restoredLevel.entities[1].bossKey, "warlord", "the boss's catalog key survives a round trip")
  eq(restoredLevel.entities[1].enraged, true, "the boss's enraged flag survives a round trip")
end

function tests.gameAwardKillTracksKillsAndBossKillsForMetaStats()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game:playerAttack(rat)
  eq(game.stats.kills, 1, "felling a plain monster counts toward the kill tally")
  eq(game.stats.bossKills, 0, "a plain monster does not count as a boss kill")

  local lich = Bosses.create(Bosses.byKey.lich, 2, 4, 6)
  lich.hp = 1
  game.level.entities = { lich }
  game:playerAttack(lich)
  eq(game.stats.kills, 2, "felling a boss also counts toward the plain kill tally")
  eq(game.stats.bossKills, 1, "felling a boss counts toward the boss-kill tally")
end

function tests.bossBreathDamageTypeMatchesTheMonsterAndCanBeShruggedOff()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local dragon = Monsters.create(Monsters.byKey.dragon, 1, 6, 6, 1)
  game.level.entities = { dragon }
  eq(Resistances.tierOf(dragon, Resistances.FIRE), Resistances.IMMUNE, "the bestiary dragon is immune to its own breath element")
  eq(Resistances.tierOf(dragon, Resistances.COLD), Resistances.WEAK, "the bestiary dragon is innately weak to cold")

  game.player.resist = { fire = Resistances.IMMUNE }
  local hpBefore = game.player.hp
  game:monsterShoot(dragon)
  eq(game.player.hp, hpBefore, "a fire-immune player takes no damage from dragon breath")
  eq(Status.has(game.player, Status.BURNING), false, "a fire-immune player never catches alight from the breath")
end

function tests.bossPhaseFieldsSurviveALevelSerializationRoundTrip()
  local game = stagedGame(3, arena(21, 11), 5, 5)
  local spec = Bosses.byKey.warlord
  local warlord = Bosses.create(spec, 1, 6, 5)
  warlord.enraged = true
  warlord.hp = math.floor(warlord.maxHp * spec.desperateAt)
  Phases.tick(game, warlord)
  game.level.entities = { warlord }

  local restoredLevel = Level.fromData(game.level:toData())
  local restored = restoredLevel.entities[1]
  eq(restored.desperate, true, "the boss's desperate flag survives a round trip")
  eq(restored.channeling, true, "the boss's channeling flag survives a round trip")
  eq(restored.defense, warlord.defense, "the boss's braced defense value survives a round trip")

  Phases.tick(game, restored)
  eq(restored.novaSpent, true, "a restored boss can still unleash and latch novaSpent")
end

return tests
