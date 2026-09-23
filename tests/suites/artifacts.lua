local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Monsters = require("monsters")
local Builder = require("builder")
local Game = require("game")
local Artifacts = require("artifacts")
local Resistances = require("resistances")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.artifactsCreateBuildsTheCatalogedItemShape()
  local blade = Artifacts.create("bloodfang")
  eq(blade.kind, Items.WEAPON, "bloodfang is a weapon-slot artifact")
  eq(blade.unique, Artifacts.LIFESTEAL, "bloodfang carries the lifesteal tag")
  eq(blade.artifact, "bloodfang", "the item remembers its catalog key")
  local ring = Artifacts.create("ring_of_the_tide")
  eq(ring.kind, Items.RING, "ring of the tide is a ring-slot artifact")
  eq(ring.unique, Artifacts.REGEN, "ring of the tide carries the regen tag")
  eq(Artifacts.create("nonexistent"), nil, "an unknown catalog key builds nothing")
end

function tests.lifestealWeaponHealsThePlayerOnAHit()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Artifacts.create("bloodfang"), game.player)
  game.player.hp = game.player.maxHp - 10
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 30, 30
  game.level.entities = { orc }
  local before = game.player.hp
  game:playerAttack(orc)
  ok(game.player.hp > before, "bloodfang heals the player for a share of the damage it deals")
end

function tests.thornedArmorReflectsDamageBackAtAMeleeAttacker()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipArmor(Artifacts.create("aegis_of_embers"), game.player)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  game.level.entities = { orc }
  local before = orc.hp
  game:monsterMelee(orc)
  ok(orc.hp < before, "aegis of embers burns the monster that hits its wearer")
end

function tests.thornedArmorCanKillAWeakAttacker()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipArmor(Artifacts.create("aegis_of_embers"), game.player)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp, rat.maxHp = 1, 1
  game.level.entities = { rat }
  local xpBefore = game.player.xp
  game:monsterMelee(rat)
  ok(not rat:isAlive(), "a thorn burn can finish off a weak attacker")
  ok(game.player.xp > xpBefore, "the player is credited xp for a thorn kill")
end

function tests.thornedArmorRespectsAFireImmuneAttacker()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipArmor(Artifacts.create("aegis_of_embers"), game.player)
  local dragon = Monsters.create(Monsters.byKey.dragon, 1, 4, 6, 1)
  game.level.entities = { dragon }
  local before = dragon.hp
  game:monsterMelee(dragon)
  eq(dragon.hp, before, "a fire-immune dragon takes zero thorns reflect from a fire-flavoured artifact")
end

function tests.thornedArmorIsHalvedAgainstAFireResistantAttacker()
  local function reflectDealt(resistant)
    local game = stagedGame(1, arena(21, 11), 3, 6)
    Items.equipArmor(Artifacts.create("aegis_of_embers"), game.player)
    local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
    orc.hp, orc.maxHp = 100, 100
    if resistant then orc.resist = { fire = Resistances.RESIST } end
    game.level.entities = { orc }
    game:monsterMelee(orc)
    return 100 - orc.hp
  end
  local plain = reflectDealt(false)
  local resisted = reflectDealt(true)
  ok(resisted < plain, "a fire-resistant attacker takes measurably less thorns reflect than an unresisted one")
  eq(resisted, math.floor(plain / 2), "fire resistance halves the thorns reflect, the same mitigation Resistances.apply gives every other fire source")
end

function tests.ringOfTheTideRegeneratesHpEachTurn()
  local game = Game.new(1)
  Items.equipRing(Artifacts.create("ring_of_the_tide"), game.player)
  game.player.hp = game.player.maxHp - 10
  local before = game.player.hp
  game:hungerTorchTick()
  eq(game.player.hp, before + 2, "ring of the tide regenerates its fixed amount each turn")
end

function tests.piercingBowIgnoresPartOfTargetDefense()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.baseAttack = 5
  Items.equipBow(Artifacts.create("gale_bow"), game.player)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 5)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.defense, orc.baseDefense, orc.hp, orc.maxHp = 6, 6, 40, 40
  game.level.entities = { orc }
  game:fireAt(orc)
  eq(orc.hp, 35, "a piercing bow's shot ignores a flat share of the target's defense")
end

function tests.artifactsStayOffFloorsAboveDepthFive()
  for seed = 1, 4 do
    for depth = 1, 4 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, ground in ipairs(level.floorItems) do
        ok(not ground.item.artifact, "no artifact appears above depth 5")
      end
    end
  end
end

function tests.artifactFieldsSurviveSerialization()
  local game = Game.new(3)
  Items.equipWeapon(Artifacts.create("bloodfang"), game.player)
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.weapon.artifact, "bloodfang", "an equipped artifact's catalog key survives a save/load round trip")
  eq(restored.player.weapon.unique, Artifacts.LIFESTEAL, "an equipped artifact's unique tag survives a save/load round trip")
  eq(restored.player.weapon.value, 0.5, "an equipped artifact's tuning value survives a save/load round trip")
end

function tests.gamePickupTracksArtifactsFoundForMetaStats()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.floorItems = { { x = 5, y = 5, item = Artifacts.create("bloodfang") } }
  game:pickupHere()
  eq(game.stats.artifactsFound, 1, "picking up an artifact counts toward artifacts found")
  ok(game.player.weapon == nil, "picking up an artifact only stashes it in inventory, it is not auto-equipped")
end

return tests
