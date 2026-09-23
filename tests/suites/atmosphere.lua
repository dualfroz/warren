local helpers = require("helpers")
local Rng = require("rng")
local Level = require("level")
local Builder = require("builder")
local Atmosphere = require("atmosphere")

local eq, arena, stagedGame, arenaDark = helpers.eq, helpers.arena, helpers.stagedGame, helpers.arenaDark

local tests = helpers.suite()

function tests.atmosphereHooksAreZeroForAnyConditionTheyDoNotGovern()
  eq(Atmosphere.sightPenalty(Atmosphere.CONSECRATED), 0, "consecrated ground carries no sight penalty")
  eq(Atmosphere.regenBonus(Atmosphere.FOGGY), 0, "fog carries no regen bonus")
  eq(Atmosphere.monsterAttackBonus(Atmosphere.FOGGY), 0, "fog carries no monster attack bonus")
  eq(Atmosphere.sightPenalty(nil), 0, "a clear floor (no weather) carries no sight penalty")
end

function tests.atmosphereFoggyShrinksSightRadiusButNeverBelowOne()
  eq(Atmosphere.sightPenalty(Atmosphere.FOGGY), 2, "fog carries a fixed sight penalty")
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local clear = game:effectiveRadius()
  game.level.weather = Atmosphere.FOGGY
  eq(game:effectiveRadius(), clear - 2, "fog shaves its fixed penalty off the floor's own sight radius")

  local darkGame = stagedGame(1, arenaDark(21, 11), 3, 6)
  darkGame.player.light.fuel = 0
  darkGame.level.weather = Atmosphere.FOGGY
  eq(darkGame:effectiveRadius(), 1, "fog on an already-dark, torchless floor floors out at a minimum radius of one")
end

function tests.atmosphereConsecratedRegeneratesThePlayerEachTurn()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.weather = Atmosphere.CONSECRATED
  game.player.hp = game.player.maxHp - 10
  local before = game.player.hp
  game:hungerTorchTick()
  eq(game.player.hp, before + 1, "consecrated ground regenerates its fixed amount each turn")
end

function tests.atmosphereConsecratedNeverRegeneratesPastMaxHp()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.weather = Atmosphere.CONSECRATED
  game.player.hp = game.player.maxHp
  game:hungerTorchTick()
  eq(game.player.hp, game.player.maxHp, "consecrated regen never lifts hp past its maximum")
end

function tests.weatherNeverAppearsOnTheEntranceFloor()
  for seed = 1, 20 do
    local level = Builder.build(1, Rng.new(seed), {})
    eq(level.weather, nil, "no weather condition is ever drawn for the entrance floor")
  end
end

function tests.weatherFieldSurvivesSerialization()
  local level = arena(21, 11)
  level.weather = Atmosphere.FOGGY
  local restored = Level.fromData(level:toData())
  eq(restored.weather, Atmosphere.FOGGY, "a floor's weather survives a round trip")
end

return tests
