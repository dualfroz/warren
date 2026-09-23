local helpers = require("helpers")
local Rng = require("rng")
local Entity = require("entity")
local Builder = require("builder")
local Crafting = require("crafting")
local Mimics = require("mimics")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.mimicsFloorItemBuildsADisguisedLootShape()
  local item = Mimics.floorItem(Rng.new(1))
  eq(item.kind, "mimic", "a mimic's floor item is its own kind, not a real item kind")
  eq(item.mimic, true, "a mimic's floor item is tagged so pickupHere knows to unmask it")
  local matched
  for _, disguise in ipairs(Mimics.DISGUISES) do
    if disguise.name == item.name and disguise.glyph == item.glyph then matched = true end
  end
  ok(matched, "the rolled disguise's name and glyph both come from the catalog")
end

function tests.mimicsRevealBuildsAHostileMonsterScaledByDepth()
  local shallow = Mimics.reveal(1, 4, 6, 1)
  eq(shallow.kind, "monster", "a revealed mimic is a genuine monster entity")
  eq(shallow.glyph, "M", "a revealed mimic shows its own glyph, not a disguise")
  eq(shallow.mimic, true, "a revealed mimic stays tagged as a mimic")
  eq(shallow.hp, 12, "a depth-1 mimic has its base hp with no bonus")
  local deep = Mimics.reveal(2, 4, 6, 5)
  eq(deep.hp, 16, "a mimic's hp scales with depth the same way Monsters.create scales a wild species")
end

function tests.gamePickupHereRevealsAMimicAndAmbushesThePlayer()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.defense, game.player.baseDefense = 0, 0
  game.level.floorItems = { { x = 5, y = 5, item = Mimics.floorItem(Rng.new(1)) } }
  local hpBefore = game.player.hp
  game:pickupHere()
  eq(#game.level.floorItems, 0, "the disguised item leaves the floor the instant it is disturbed")
  eq(#game.level.entities, 1, "a revealed mimic joins the level as a real hostile monster")
  eq(game.level.entities[1].mimic, true, "the spawned monster is tagged as a mimic")
  eq(game.player.hp, hpBefore - 5, "the mimic lands one free ambush hit for its full attack")
  ok(contains(game.log:last(), "damage"), "the ambush hit is logged")
end

function tests.gameKillingARevealedMimicGrantsItsFixedEssenceReward()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local mimic = Mimics.reveal(1, 4, 6, 1)
  mimic.hp = 1
  game.level.entities = { mimic }
  local essenceBefore = game.player.essence
  game:playerAttack(mimic)
  eq(game.player.essence, essenceBefore + Crafting.essenceFor(Mimics.xpFor()),
    "felling a mimic grants essence scaled to its own fixed xp reward, not a plain monster's")
end

function tests.mimicsNeverAppearOnTheEntranceFloor()
  for seed = 1, 6 do
    local level = Builder.build(1, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      ok(not ground.item.mimic, "no mimic appears on the entrance floor")
    end
  end
end

function tests.mimicFieldSurvivesSerialization()
  local mimic = Mimics.reveal(1, 4, 6, 1)
  local restored = Entity.fromData(mimic:toData())
  eq(restored.mimic, true, "a revealed mimic's tag survives a save/load round trip")
  eq(restored.glyph, "M", "a revealed mimic's glyph survives a save/load round trip too")
end

function tests.gameMimicAmbushAlsoBreaksMomentum()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.combo = 2
  game.level.floorItems = { { x = 5, y = 5, item = Mimics.floorItem(Rng.new(1)) } }
  game:pickupHere()
  eq(game.player.combo, 0, "a mimic's ambush hit also breaks momentum")
end

return tests
