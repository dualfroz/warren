local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Status = require("status")
local Monsters = require("monsters")
local Hazards = require("hazards")
local Resistances = require("resistances")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.hazards()
  local level = arena(21, 11)

  local fire = Hazards.ignite(level, 5, 5, 3, 4)
  eq(fire.kind, Hazards.FIRE, "ignite drops a fire hazard")
  eq(Hazards.at(level, 5, 5, Hazards.FIRE), fire, "the hazard is found by its cell and kind")

  Hazards.ignite(level, 5, 5, 5, 1)
  eq(#level.hazards, 1, "re-igniting the same cell refreshes it instead of stacking a duplicate")
  eq(fire.duration, 5, "refreshing a hazard keeps the stronger of the two durations")
  eq(fire.potency, 4, "refreshing a hazard keeps the stronger of the two potencies")

  local victim = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local hpBefore = victim.hp
  local line = Hazards.afflict(level, victim)
  ok(contains(line, "flames"), "afflict describes a fire hazard as flames")
  eq(victim.hp, hpBefore - fire.potency, "standing in fire deals its potency in damage")
  eq(Status.has(victim, Status.BURNING), true, "fire afflict also lays down a burning status")

  local elsewhere = Monsters.create(Monsters.byKey.rat, 2, 9, 9, 1)
  eq(Hazards.afflict(level, elsewhere), nil, "afflict does nothing to an entity off any hazard cell")

  local gas = Hazards.spawnGas(level, 12, 8, 4, 2)
  eq(gas.kind, Hazards.GAS, "spawnGas drops a gas hazard")
  local choker = Monsters.create(Monsters.byKey.rat, 3, 12, 8, 1)
  local gasLine = Hazards.afflict(level, choker)
  ok(contains(gasLine, "fumes"), "afflict describes a gas hazard as fumes")
  eq(Status.has(choker, Status.POISON), true, "gas afflict lays down a poison status")

  local wet = arena(21, 11)
  wet.map:set(6, 6, Tiles.WATER)
  Hazards.ignite(wet, 6, 6, 3, 2)
  Hazards.step(wet, Rng.new(1))
  eq(Hazards.at(wet, 6, 6, Hazards.FIRE), nil,
    "fire sitting on water is doused on the very next environmental step")

  local fading = arena(21, 11)
  Hazards.spawn(fading, 15, 5, Hazards.FIRE, 1, 2)
  Hazards.step(fading, Rng.new(1))
  eq(Hazards.at(fading, 15, 5, Hazards.FIRE), nil, "a hazard is removed once its duration runs out")

  local spread = false
  for seed = 1, 200 do
    local field = arena(21, 11)
    Hazards.ignite(field, 10, 5, 3, 2)
    Hazards.step(field, Rng.new(seed))
    if Hazards.at(field, 11, 5) or Hazards.at(field, 9, 5)
      or Hazards.at(field, 10, 4) or Hazards.at(field, 10, 6) then
      spread = true
      break
    end
  end
  ok(spread, "fire eventually spreads into open neighbouring floor on some seed")

  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  Hazards.ignite(rendered.level, 5, 6, 3, 2)
  rendered:computeVisible()
  ok(contains(rendered:render(), "`"), "a fire hazard on a visible cell renders as its glyph")
end

function tests.hazardKillDuringMonsterTurnGrantsXp()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 15, 9, 1)
  rat.hp = 1
  Hazards.ignite(game.level, rat.x, rat.y, 3, 50)
  game.level.entities = { rat }
  local xpBefore = game.player.xp
  game:takeMonsterTurn(rat)
  eq(#game.level.entities, 0, "a monster that dies standing in fire is swept from the level")
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "dying to a hazard still grants its xp")
end

function tests.hazardStepRunsOncePerPlayerRound()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local px, py = game.player.x, game.player.y
  Hazards.ignite(game.level, px, py, 1, 3)
  local hpBefore = game.player.hp
  game:autoStep()
  eq(game.player.hp, hpBefore - 3, "the player takes hazard damage while standing in fire on their turn")
  eq(Hazards.at(game.level, px, py, Hazards.FIRE), nil,
    "the hazard's duration is spent by the environmental step at the end of the round")
end

function tests.hazardsAfflictAppliesTargetResistance()
  local level = arena(21, 11)
  Hazards.ignite(level, 5, 5, 3, 4)
  local salamander = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  salamander.resist = { fire = Resistances.RESIST }
  local hpBefore = salamander.hp
  Hazards.afflict(level, salamander)
  eq(salamander.hp, hpBefore - 2, "standing in fire as fire-resistant halves the usual potency")
end

function tests.hazardsAfflictDampensFireAndBlocksIgnitionForASoakedVictim()
  local level = arena(21, 11)
  Hazards.ignite(level, 5, 5, 3, 4)
  local victim = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  victim.wet = 2
  local hpBefore = victim.hp
  local line = Hazards.afflict(level, victim)
  eq(victim.hp, hpBefore - 2, "standing in fire while soaked only deals half the usual potency")
  ok(contains(line, "soaked"), "the afflict message calls out the victim's own soaked skin")
  eq(Status.has(victim, Status.BURNING), false, "a soaked victim standing in fire never actually catches alight")
end

return tests
