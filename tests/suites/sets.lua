local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Monsters = require("monsters")
local Builder = require("builder")
local Game = require("game")
local Sets = require("sets")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.setsCreateBuildsTheCatalogedItemShape()
  local blade = Sets.create("ironclad", "weapon")
  eq(blade.kind, Items.WEAPON, "the ironclad weapon piece is a weapon")
  eq(blade.set, "ironclad", "the item remembers its set key")
  eq(blade.name, "Ironclad Greatsword", "the item takes the catalog's exact name")
  local ring = Sets.create("duskrunner", "ring")
  eq(ring.kind, Items.RING, "the duskrunner ring piece is a ring")
  eq(ring.set, "duskrunner", "a second set tags its own pieces with its own key")
  eq(Sets.create("nonexistent", "weapon"), nil, "an unknown set key builds nothing")
  eq(Sets.create("ironclad", "bow"), nil, "a slot ironclad does not define builds nothing")
end

function tests.setsAttackAndDefenseBonusEscalateAsMorePiecesAreEquipped()
  local player = { weapon = Sets.create("ironclad", "weapon") }
  eq(Sets.attackBonus(player), 0, "a single piece grants no bonus below the 2-piece threshold")
  eq(Sets.defenseBonus(player), 0, "a single piece grants no defense bonus either")
  player.armor = Sets.create("ironclad", "armor")
  eq(Sets.attackBonus(player), 1, "two matching pieces grant the 2-piece attack bonus")
  eq(Sets.defenseBonus(player), 1, "two matching pieces grant the 2-piece defense bonus")
  eq(Sets.regenAmount(player), 0, "the 2-piece tier grants no regen")
  player.ring = Sets.create("ironclad", "ring")
  eq(Sets.attackBonus(player), 2, "the full 3-piece bonus replaces the 2-piece total rather than adding to it")
  eq(Sets.defenseBonus(player), 3, "the full set's defense bonus also replaces rather than stacks")
  eq(Sets.regenAmount(player), 1, "only the full set grants its regen bonus")
end

function tests.setsBonusDropsBackWhenAPieceIsUnequipped()
  local player = {
    weapon = Sets.create("ironclad", "weapon"),
    armor = Sets.create("ironclad", "armor"),
    ring = Sets.create("ironclad", "ring"),
  }
  eq(Sets.attackBonus(player), 2, "the full set starts active")
  player.ring = Items.ring("plain band", 0, 0)
  eq(Sets.attackBonus(player), 1, "losing a piece drops the bonus back to the 2-piece tier")
  player.armor = Items.armor("plain mail", 2)
  eq(Sets.attackBonus(player), 0, "a single remaining piece grants no bonus at all")
end

function tests.setsDoNotCrossTalkBetweenDifferentSets()
  local player = { weapon = Sets.create("ironclad", "weapon"), bow = Sets.create("duskrunner", "bow") }
  eq(Sets.attackBonus(player), 0, "one piece from each of two different sets completes neither")
end

function tests.gameEquippingASetPieceAppliesItsBonusInActualCombat()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.defense, orc.baseDefense, orc.hp, orc.maxHp = 0, 0, 40, 40
  game.level.entities = { orc }
  local before = orc.hp
  game:playerAttack(orc)
  local plainDamage = before - orc.hp

  local game2 = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Sets.create("ironclad", "weapon"), game2.player)
  Items.equipArmor(Sets.create("ironclad", "armor"), game2.player)
  local orc2 = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc2.defense, orc2.baseDefense, orc2.hp, orc2.maxHp = 0, 0, 40, 40
  game2.level.entities = { orc2 }
  local before2 = orc2.hp
  game2:playerAttack(orc2)
  local setDamage = before2 - orc2.hp
  eq(setDamage, plainDamage, "a 2-piece Ironclad bonus makes up for the set piece's own weaker power")
end

function tests.gameEquippingTheSecondSetPieceLogsTheSetAwakening()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.inventory = { Sets.create("ironclad", "weapon"), Sets.create("ironclad", "armor") }
  ok(game:useItem(1), "equipping the first ironclad piece succeeds")
  ok(not contains(game.log:last(), "awakens"), "a lone set piece does not announce a bonus")
  ok(game:useItem(1), "equipping the second ironclad piece succeeds")
  ok(contains(game.log:last(), "Ironclad") and contains(game.log:last(), "awakens"),
    "completing the 2-piece threshold announces the set by name")
end

function tests.setsRegenerationAppliesEachTurnAtTheFullIroncladSet()
  local game = Game.new(1)
  Items.equipWeapon(Sets.create("ironclad", "weapon"), game.player)
  Items.equipArmor(Sets.create("ironclad", "armor"), game.player)
  Items.equipRing(Sets.create("ironclad", "ring"), game.player)
  game.player.hp = game.player.maxHp - 10
  local before = game.player.hp
  game:hungerTorchTick()
  eq(game.player.hp, before + 1, "the full ironclad set regenerates its fixed amount each turn")
end

function tests.setPiecesStayOffTheShallowestTwoFloors()
  for seed = 1, 6 do
    for depth = 1, 2 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, ground in ipairs(level.floorItems) do
        ok(not ground.item.set, "no set piece appears on depth 1 or 2")
      end
    end
  end
end

function tests.setFieldsSurviveSerialization()
  local game = Game.new(3)
  Items.equipWeapon(Sets.create("ironclad", "weapon"), game.player)
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.weapon.set, "ironclad", "an equipped set piece's set key survives a save/load round trip")
end

function tests.gamePickupTracksSetPiecesFoundForMetaStats()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.floorItems = { { x = 5, y = 5, item = Sets.create("ironclad", "ring") } }
  game:pickupHere()
  eq(game.stats.setPiecesFound, 1, "picking up a set piece counts toward set pieces found")
  ok(game.player.ring == nil, "picking up a set piece only stashes it in inventory, it is not auto-equipped")
end

return tests
