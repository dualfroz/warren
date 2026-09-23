local helpers = require("helpers")
local Tiles = require("tiles")
local Monsters = require("monsters")
local Game = require("game")
local Resistances = require("resistances")
local Conductivity = require("conductivity")

local eq, arena, stagedGame = helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.conductivityIsWetReadsTheEntitysOwnWetField()
  eq(Conductivity.isWet({}), false, "an entity with no wet field at all reads as dry")
  eq(Conductivity.isWet({ wet = 0 }), false, "a wet counter already run down to zero reads as dry")
  eq(Conductivity.isWet({ wet = 1 }), true, "any positive wet counter reads as wet")
end

function tests.conductivityTickSoaksOnWaterAndDecaysOneStepAtATimeOffIt()
  local level = arena(21, 11)
  level.map:set(6, 6, Tiles.WATER)
  local entity = { x = 6, y = 6 }
  Conductivity.tick(level, entity)
  eq(entity.wet, Conductivity.SOAK_DURATION, "standing on water soaks an entity to the full duration")
  entity.x = 7
  for i = Conductivity.SOAK_DURATION - 1, 0, -1 do
    Conductivity.tick(level, entity)
    eq(entity.wet, i, "the soak counter decays by exactly one per turn spent off water")
  end
  eq(Conductivity.isWet(entity), false, "the counter bottoms out at zero rather than going negative")
end

function tests.conductivityTickReSoaksImmediatelyOnSteppingBackOntoWater()
  local level = arena(21, 11)
  level.map:set(6, 6, Tiles.WATER)
  local entity = { x = 6, y = 6, wet = 1 }
  Conductivity.tick(level, entity)
  eq(entity.wet, Conductivity.SOAK_DURATION,
    "stepping back onto water refreshes the counter to full rather than adding to it")
end

function tests.conductivityApplyFireDampensDamageOnlyOnceSoaked()
  eq(Conductivity.applyFire({}, 10), 10, "fire damage against a dry entity is untouched")
  eq(Conductivity.applyFire({ wet = 2 }, 10), 5,
    "fire damage against a soaked entity is halved on top of its resistance tier")
end

function tests.conductivityApplyLightningBonusesDamageOnlyOnceSoaked()
  eq(Conductivity.applyLightning({}, 10), 10, "lightning damage against a dry entity is untouched")
  eq(Conductivity.applyLightning({ wet = 2 }, 10), 15,
    "lightning damage against a soaked entity gets a 50 percent conductivity bonus")
end

function tests.conductivityNeverConjuresDamageOutOfAnImmuneResistance()
  eq(Conductivity.applyFire({ wet = 2, resist = { fire = Resistances.IMMUNE } }, 10), 0,
    "fire immunity still floors damage at zero even while soaked")
  eq(Conductivity.applyLightning({ wet = 2, resist = { lightning = Resistances.IMMUNE } }, 10), 0,
    "lightning immunity still floors damage at zero even while soaked")
end

function tests.conductivityResistsIgnitionOnlyWhileWet()
  eq(Conductivity.resistsIgnition({}), false, "a dry entity does not resist ignition")
  eq(Conductivity.resistsIgnition({ wet = 3 }), true, "a soaked entity resists catching fire")
end

function tests.gameConductivityTicksAMonsterEachTurnBasedOnTheTileUnderfoot()
  local level = arena(21, 11)
  level.map:set(6, 6, Tiles.WATER)
  local game = stagedGame(1, level, 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game:takeMonsterTurn(rat)
  eq(rat.wet, Conductivity.SOAK_DURATION, "a monster ending its turn on water is soaked to the full duration")
  rat.x, rat.y = 7, 6
  game:takeMonsterTurn(rat)
  eq(rat.wet, Conductivity.SOAK_DURATION - 1, "moving off water the following turn lets the soak counter decay by one")
end

function tests.gameConductivityTicksThePlayerEachAutoStepBasedOnTheTileUnderfoot()
  local level = arena(21, 11)
  level.map:set(3, 6, Tiles.WATER)
  local game = stagedGame(1, level, 3, 6)
  game:autoStep()
  eq(game.player.wet, Conductivity.SOAK_DURATION, "the player ending a turn on water is soaked to the full duration")
end

function tests.entityWetFieldSurvivesSerialization()
  local game = Game.new(3)
  game.player.wet = 2
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.wet, 2, "the player's soak counter survives a save/load round trip")
end

return tests
