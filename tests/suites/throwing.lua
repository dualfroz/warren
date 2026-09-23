local helpers = require("helpers")
local Items = require("items")
local Affixes = require("affixes")
local Status = require("status")
local Monsters = require("monsters")
local Hazards = require("hazards")
local Resistances = require("resistances")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.throwWeaponHitsAndLands()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  local dagger = Items.weapon("dagger", 2)
  game.player.inventory[#game.player.inventory + 1] = dagger
  local index = #game.player.inventory
  local before = #game.player.inventory
  local success = game:throwAt(index, rat)
  eq(success, true, "a weapon throw with a clear line succeeds")
  eq(#game.player.inventory, before - 1, "the thrown weapon leaves the inventory")
  eq(rat.hp, rat.maxHp - dagger.power * 2, "a thrown weapon deals double its melee power")
  local landed = game.level:itemsAt(rat.x, rat.y)
  eq(#landed, 1, "the thrown weapon lands on the ground at the target")
  eq(landed[1].item, dagger, "the landed item is the same weapon that was thrown")
end

function tests.throwWeaponKillGrantsXp()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.weapon("battle axe", 5)
  local xpBefore = game.player.xp
  game:throwAt(#game.player.inventory, rat)
  eq(#game.level.entities, 0, "a lethal throw sweeps the monster from the level")
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "a thrown-weapon kill grants xp")
end

function tests.throwPotionAppliesHostileEffect()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.potionOf("poison", 3)
  local success = game:throwAt(#game.player.inventory, rat)
  eq(success, true, "a potion throw with a clear line succeeds")
  eq(Status.has(rat, Status.POISON), true, "a thrown poison potion poisons the target instead of the thrower")
  eq(Status.has(game.player, Status.POISON), false, "the thrower is untouched by their own thrown potion")
  eq(Hazards.at(game.level, rat.x, rat.y, Hazards.GAS) ~= nil, true,
    "a shattered poison potion leaves a lingering cloud of fumes")
end

function tests.throwConfusePotionAppliesTheStatusToTheTargetNotTheThrower()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.potionOf("confuse")
  local success = game:throwAt(#game.player.inventory, rat)
  eq(success, true, "a confuse potion throw with a clear line succeeds")
  eq(Status.has(rat, Status.CONFUSE), true, "a thrown confuse potion confuses the target instead of the thrower")
  eq(Status.has(game.player, Status.CONFUSE), false, "the thrower is untouched by their own thrown potion")
end

function tests.throwBlindPotionAppliesTheStatusToTheTargetNotTheThrower()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.potionOf("blind")
  local success = game:throwAt(#game.player.inventory, rat)
  eq(success, true, "a blind potion throw with a clear line succeeds")
  eq(Status.has(rat, Status.BLIND), true, "a thrown blind potion blinds the target instead of the thrower")
  eq(Status.has(game.player, Status.BLIND), false, "the thrower is untouched by their own thrown potion")
end

function tests.throwLevitatePotionAppliesTheStatusToTheTargetNotTheThrower()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.potionOf("levitate")
  local success = game:throwAt(#game.player.inventory, rat)
  eq(success, true, "a levitation potion throw with a clear line succeeds")
  eq(Status.has(rat, Status.LEVITATE), true, "a thrown levitation potion lifts the target instead of the thrower")
  eq(Status.has(game.player, Status.LEVITATE), false, "the thrower is untouched by their own thrown potion")
end

function tests.throwOutOfRangeFails()
  local game = stagedGame(4, arena(21, 11), 2, 2)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 19, 9, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.weapon("dagger", 2)
  local index = #game.player.inventory
  local before = #game.player.inventory
  local success = game:throwAt(index, rat)
  eq(success, false, "a throw beyond range fails")
  eq(#game.player.inventory, before, "a failed throw does not consume the item")
  eq(rat.hp, rat.maxHp, "a failed throw deals no damage")
end

function tests.throwingAndRangedDamageRespectResistance()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local flamingDagger = Affixes.decorate(Items.weapon("dagger", 3), Affixes.weapon[3])
  game.player.inventory[#game.player.inventory + 1] = flamingDagger
  local salamander = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  salamander.hp, salamander.maxHp = 40, 40
  salamander.resist = { fire = Resistances.IMMUNE }
  game.level.entities = { salamander }
  local success = game:throwAt(#game.player.inventory, salamander)
  ok(success, "the throw itself still leaves the thrower's hand")
  eq(salamander.hp, 40, "a fire-immune target takes no damage from a thrown flaming weapon")

  local rangedGame = stagedGame(1, arena(21, 11), 3, 6)
  rangedGame.player.bow = Items.bow("longbow", 3, 6)
  rangedGame.player.inventory[#rangedGame.player.inventory + 1] = Items.ammo("arrow", 5)
  local armored = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  armored.hp, armored.maxHp = 40, 40
  armored.resist = { physical = Resistances.RESIST }
  rangedGame.level.entities = { armored }
  rangedGame:fireAt(armored)
  eq(armored.hp, 37, "physical resistance halves the arrow's already-defense-reduced damage")
end

return tests
