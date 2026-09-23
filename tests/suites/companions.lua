local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Status = require("status")
local Monsters = require("monsters")
local Level = require("level")
local Builder = require("builder")
local Companions = require("companions")
local Stealth = require("stealth")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.companionSummonPlacesItAdjacentToThePlayer()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  ok(hound ~= nil, "summoning a valid species succeeds next to the player")
  eq(hound.kind, "companion", "a summoned companion is tagged with the companion kind")
  eq(math.max(math.abs(hound.x - 5), math.abs(hound.y - 5)), 1, "the companion lands adjacent to the player")
  eq(#game.level.entities, 1, "the companion joins the level's entity list")
end

function tests.companionSummonRejectsAnUnknownSpecies()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  eq(Companions.summon(game, "wyrm"), nil, "an unknown species key summons nothing")
  eq(#game.level.entities, 0, "no entity is added for an unknown species")
end

function tests.companionSummonReplacesAnEarlierBond()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local first = Companions.summon(game, "hound")
  local second = Companions.summon(game, "golem")
  ok(not first:isAlive(), "bonding a new companion retires the earlier one")
  ok(second:isAlive(), "the freshly bonded companion is alive")
  local alive = 0
  for _, e in ipairs(game.level.entities) do
    if e.kind == "companion" and e:isAlive() then alive = alive + 1 end
  end
  eq(alive, 1, "only one companion is ever alive at a time")
end

function tests.companionAttacksAdjacentHostileMonsterAndCanKillIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local rat = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local xpBefore = game.player.xp
  Companions.act(game, hound)
  eq(rat.hp, 0, "a hound's hit kills the weak rat standing next to it")
  ok(game.player.xp > xpBefore, "the player is credited xp for its companion's kill")
end

function tests.companionAttacksADiagonallyAdjacentHostileMonsterJustLikeACardinalOne()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local rat = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y + 1, 1)
  game.level.entities[#game.level.entities + 1] = rat
  Companions.act(game, hound)
  eq(rat.hp, 0, "a hound's hit kills a weak rat standing diagonally next to it, not just cardinally")
end

function tests.companionAdvancesOnAVisibleMonsterItCannotYetReach()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local orc = Monsters.create(Monsters.byKey.orc, 50, hound.x + 5, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX = hound.x
  Companions.act(game, hound)
  ok(hound.x > startX, "the companion closes the distance to a monster it can see but not reach")
end

function tests.companionIgnoresAMonsterBeyondItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local hound = Companions.summon(game, "hound")
  local orc = Monsters.create(Monsters.byKey.orc, 50, 19, 9, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX, startY = hound.x, hound.y
  Companions.act(game, hound)
  eq(hound.x, startX, "a monster far outside sight range does not pull the companion off course (x)")
  eq(hound.y, startY, "a monster far outside sight range does not pull the companion off course (y)")
end

function tests.companionActBlindedCompanionOnlyDetectsAnAdjacentHostileNotOneWithinItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local farOrc = Monsters.create(Monsters.byKey.orc, 50, hound.x + 5, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = farOrc
  Status.apply(hound, Status.BLIND, 6, 1)
  local startX = hound.x
  Companions.act(game, hound)
  eq(hound.x, startX, "a blinded companion loses a sighting well within its listed sight radius")

  local rat = Monsters.create(Monsters.byKey.rat, 51, hound.x + 1, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local ratHpBefore = rat.hp
  Companions.act(game, hound)
  ok(rat.hp < ratHpBefore, "a blinded companion still fights a hostile once it stands adjacent")
end

function tests.companionActAttackingAnAdjacentMonsterEmitsNoiseThatCanStirADormantBystander()
  local stirred = false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local hound = Companions.summon(game, "hound")
    local target = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y, 1)
    local bystander = Monsters.create(Monsters.byKey.orc, 51, hound.x + 4, hound.y, 1)
    bystander.awareness = Stealth.DORMANT
    game.level.entities[#game.level.entities + 1] = target
    game.level.entities[#game.level.entities + 1] = bystander
    Companions.act(game, hound)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a companion's own melee is exactly as loud as the player's or a hostile monster's")
end

function tests.companionFollowsThePlayerWhenNoMonsterIsVisible()
  local game = stagedGame(1, arena(21, 11), 10, 5)
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 3, 5
  local startDist = math.abs(golem.x - game.player.x)
  Companions.act(game, golem)
  ok(math.abs(golem.x - game.player.x) < startDist, "a companion with no monster in sight closes in on the player")
end

function tests.companionActConfusedCompanionSometimesStumblesInsteadOfFightingAnAdjacentHostile()
  local sawAttack, sawStumble = false, false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local golem = Companions.summon(game, "golem")
    local rat = Monsters.create(Monsters.byKey.rat, 50, golem.x + 1, golem.y, 1)
    game.level.entities[#game.level.entities + 1] = rat
    Status.apply(golem, Status.CONFUSE, 5, 1)
    local hpBefore = rat.hp
    Companions.act(game, golem)
    if rat.hp < hpBefore then
      sawAttack = true
    else
      sawStumble = true
    end
    if sawAttack and sawStumble then break end
  end
  ok(sawAttack, "a confused companion's roll sometimes lets it fight an adjacent hostile as normal")
  ok(sawStumble, "a confused companion's roll sometimes overrides even a point-blank attack")
end

function tests.companionActConfusedCompanionNeverAttacksThePlayerEvenIfTheStumbleAimsAtItsCell()
  local sawMoved = false
  for seed = 1, 300 do
    local game = stagedGame(seed, arena(21, 11), 5, 5)
    local golem = Companions.summon(game, "golem")
    Status.apply(golem, Status.CONFUSE, 5, 1)
    local hpBefore = game.player.hp
    Companions.act(game, golem)
    eq(game.player.hp, hpBefore, "a confused companion never attacks the player even when its stumble aims at their cell")
    ok(not (golem.x == game.player.x and golem.y == game.player.y),
      "a confused companion's stumble is blocked, not allowed to share the player's own cell")
    if golem.x ~= 6 or golem.y ~= 5 then sawMoved = true end
  end
  ok(sawMoved, "the confused companion's stumble roll actually moves it somewhere across many seeds")
end

function tests.hearthSpriteMendsThePlayerWhenIdle()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.hp = game.player.maxHp - 5
  local sprite = Companions.summon(game, "sprite")
  local before = game.player.hp
  Companions.act(game, sprite)
  eq(game.player.hp, before + Companions.byKey.sprite.heal, "a hearth sprite mends its bonded player each idle turn")
end

function tests.useItemOnACharmBondsACompanionAndConsumesIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Items.charm("hound") }
  ok(game:useItem(1), "using a charm succeeds")
  eq(#game.player.inventory, 0, "the charm leaves the inventory once bonded")
  eq(#game.level.entities, 1, "the bonded hound is added to the level")
  eq(game.level.entities[1].species, "hound", "the bonded companion matches the charm's species")
end

function tests.aFallenCompanionIsLoggedAndSweptWithoutAwardingXp()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  hound.hp = 1
  Status.apply(hound, Status.POISON, 1, 5)
  local xpBefore = game.player.xp
  game:takeMonsterTurn(hound)
  eq(#game.level.entities, 0, "a companion that dies to its own status tick is swept from the level")
  eq(game.player.xp, xpBefore, "a fallen companion grants the player no xp")
  ok(contains(game.log:last(), "falls"), "a fallen companion's death is logged")
end

function tests.charmsStayOffTheShallowestFloors()
  for seed = 1, 5 do
    for depth = 1, 2 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, ground in ipairs(level.floorItems) do
        ok(ground.item.kind ~= Items.CHARM, "no charm appears above depth 3")
      end
    end
  end
end

function tests.companionFieldsSurviveSerialization()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Companions.summon(game, "sprite")
  local restoredLevel = Level.fromData(game.level:toData())
  eq(#restoredLevel.entities, 1, "the companion survives a level round trip")
  eq(restoredLevel.entities[1].kind, "companion", "the companion's kind survives a round trip")
  eq(restoredLevel.entities[1].species, "sprite", "the companion's species survives a round trip")
end

function tests.companionGainXpBelowFirstThresholdBanksXpWithoutEvolving()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 5)
  eq(hound.companionXp, 5, "xp below the first threshold still accumulates")
  eq(hound.companionLevel, 1, "a companion under its first threshold stays at level 1")
  eq(hound.name, "hunting hound", "an unevolved companion keeps its base name")
  eq(hound.attack, 4, "an unevolved companion keeps its base attack")
end

function tests.companionGainXpAtFirstThresholdEvolvesRenamesAndGrowsStats()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 12)
  eq(hound.companionLevel, 2, "reaching the first threshold advances the companion to level 2")
  eq(hound.name, "warhound", "the first evolution renames the companion")
  eq(hound.maxHp, 20, "the first evolution's hp bonus raises max hp")
  eq(hound.hp, 20, "the first evolution's hp bonus also heals the same amount")
  eq(hound.attack, 6, "the first evolution's attack bonus is applied")
  eq(hound.defense, 1, "the first evolution's defense bonus is applied")
  ok(contains(game.log:last(), "evolves"), "an evolution is logged")
end

function tests.companionGainXpCrossingBothThresholdsAtOnceAppliesBothStagesCumulatively()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 40)
  eq(hound.companionLevel, 3, "a single large xp grant can vault past an intermediate threshold")
  eq(hound.name, "dire hound", "the companion carries the highest stage's name, not the first")
  eq(hound.maxHp, 30, "both stages' hp bonuses stack (14 base + 6 + 10)")
  eq(hound.attack, 9, "both stages' attack bonuses stack (4 base + 2 + 3)")
  eq(hound.defense, 2, "both stages' defense bonuses stack (0 base + 1 + 1)")
end

function tests.companionGainXpNeverReappliesAnAlreadyCrossedStage()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 12)
  Companions.gainXp(game, hound, 1)
  eq(hound.companionXp, 13, "further xp below the next threshold keeps accumulating")
  eq(hound.companionLevel, 2, "a companion does not advance again before its next threshold")
  eq(hound.attack, 6, "an already-crossed stage's bonus is never applied a second time")
end

function tests.companionGainXpAtMaxLevelJustBanksFurtherXpWithNoFurtherEvolution()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 40)
  Companions.gainXp(game, hound, 100)
  eq(hound.companionXp, 140, "xp keeps accumulating past the last stage")
  eq(hound.companionLevel, 3, "a fully evolved companion caps out at its last stage")
  eq(hound.attack, 9, "stats hold steady once every stage has already been crossed")
end

function tests.companionGainXpIgnoresAZeroOrNegativeAmount()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 0)
  Companions.gainXp(game, hound, -5)
  eq(hound.companionXp, 0, "a zero or negative grant leaves companion xp untouched")
end

function tests.companionActCreditsItsOwnKillWithXpOnTopOfThePlayers()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local rat = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local xpBefore = game.player.xp
  Companions.act(game, hound)
  eq(rat.hp, 0, "the hound's hit still kills the rat")
  eq(hound.companionXp, Monsters.xpFor(rat), "the companion banks the felled monster's own xp value")
  ok(game.player.xp > xpBefore, "the player is still separately credited xp for the companion's kill")
end

function tests.companionEvolutionBoostsAHearthSpriteHealingOnTopOfItsStaticRate()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.hp = game.player.maxHp - 10
  local sprite = Companions.summon(game, "sprite")
  Companions.gainXp(game, sprite, 10)
  eq(sprite.name, "kindled sprite", "the sprite's first evolution renames it")
  local before = game.player.hp
  Companions.act(game, sprite)
  eq(game.player.hp, before + Companions.byKey.sprite.heal + 1,
    "an evolved sprite heals its species rate plus its own evolution bonus")
end

function tests.companionLevelXpAndHealBonusSurviveSerialization()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sprite = Companions.summon(game, "sprite")
  Companions.gainXp(game, sprite, 10)
  local restoredLevel = Level.fromData(game.level:toData())
  local restored = restoredLevel.entities[1]
  eq(restored.companionLevel, 2, "the companion's level survives a round trip")
  eq(restored.companionXp, 10, "the companion's banked xp survives a round trip")
  eq(restored.companionHealBonus, 1, "the companion's evolved heal bonus survives a round trip")
  eq(restored.name, "kindled sprite", "the companion's evolved name survives a round trip")
end

function tests.movePlayerSwapsPlacesWithItsOwnCompanionInsteadOfAttackingIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local hpBefore = hound.hp
  game:movePlayer(1, 0)
  eq(game.player.x, 6, "the player steps onto the cell its companion just vacated")
  eq(game.player.y, 5, "the player's row is unchanged by the swap")
  eq(hound.x, 5, "the companion is displaced onto the player's old cell")
  eq(hound.y, 5, "the companion's row is unchanged by the swap")
  eq(hound.hp, hpBefore, "swapping past a companion never damages it")
  ok(contains(game.log:last(), "swap"), "swapping past an ally is logged")
end

return tests
