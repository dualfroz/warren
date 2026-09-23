local helpers = require("helpers")
local Items = require("items")
local Monsters = require("monsters")
local Game = require("game")
local Durability = require("durability")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.durabilityFreshWeaponStartsAtMaxAndIsNotBroken()
  local sword = Items.weapon("sword", 4)
  eq(sword.durability, Durability.MAX, "a freshly forged weapon starts at max durability")
  eq(sword.maxDurability, Durability.MAX, "a freshly forged weapon's max durability matches the catalog default")
  ok(not Durability.isBroken(sword), "a freshly forged weapon is not broken")
end

function tests.durabilityWearWeaponDecrementsAndBreaksAtZeroSubtractingItsPower()
  local hero = { attack = 5, inventory = {}, kind = "player", name = "you" }
  Items.equipWeapon(Items.weapon("sword", 4), hero)
  eq(hero.attack, 9, "the sword's power is baked into attack on equip")
  local broke
  for _ = 1, Durability.MAX - 1 do
    broke = Durability.wearWeapon(hero)
    ok(broke == nil, "the sword survives every hit before its last")
  end
  eq(hero.weapon.durability, 1, "one point of durability remains before the final hit")
  broke = Durability.wearWeapon(hero)
  ok(broke ~= nil, "the hit that empties durability reports a break")
  ok(contains(broke, "breaks apart"), "the break line names what happened")
  eq(hero.weapon.durability, 0, "durability floors at exactly zero")
  eq(hero.attack, 5, "the sword's power is pulled back out of attack the instant it breaks")
end

function tests.durabilityWearWeaponIsANoOpOnceAlreadyBroken()
  local item = Items.weapon("dagger", 2)
  item.durability = 0
  local hero = { weapon = item, attack = 10, kind = "player", name = "you" }
  eq(Durability.wearWeapon(hero), nil, "wearing an already broken weapon reports no further break")
  eq(item.durability, 0, "durability never drops below zero")
  eq(hero.attack, 10, "wearing an already-broken weapon never touches attack again")
end

function tests.durabilityWearArmorBreaksAndSubtractsItsPowerFromDefense()
  local hero = { defense = 1, inventory = {}, kind = "player", name = "you" }
  Items.equipArmor(Items.armor("plate", 3), hero)
  eq(hero.defense, 4, "the plate's power is baked into defense on equip")
  hero.armor.durability = 1
  local broke = Durability.wearArmor(hero)
  ok(contains(broke, "battered"), "the break line reports the armor giving out")
  eq(hero.defense, 1, "the armor's power is pulled back out of defense the instant it breaks")
end

function tests.durabilityWearBowBreaksWithoutTouchingAnyStatDirectly()
  local hero = { bow = Items.bow("shortbow", 3, 6), attack = 5, kind = "player", name = "you" }
  hero.bow.durability = 1
  local broke = Durability.wearBow(hero)
  ok(contains(broke, "snaps"), "the break line reports the bow giving out")
  eq(hero.bow.durability, 0, "durability floors at zero")
  eq(hero.attack, 5, "a bow's power was never baked into attack, so breaking it leaves attack untouched")
end

function tests.durabilityEffectivePowerIsZeroForABrokenItemAndFullOtherwise()
  local bow = Items.bow("shortbow", 3, 6)
  eq(Durability.effectivePower(bow), 3, "a pristine bow contributes its full power")
  bow.durability = 0
  eq(Durability.effectivePower(bow), 0, "a broken bow contributes nothing")
  eq(Durability.effectivePower(nil), 0, "no bow equipped contributes nothing")
end

function tests.durabilityRepairFailsWithoutEnoughGoldOrOnAPristineItem()
  local hero = { weapon = Items.weapon("sword", 4), gold = 0 }
  local success, reason = Durability.repair(hero, "weapon")
  eq(success, false, "a pristine weapon refuses repair")
  eq(reason, "already in perfect condition", "the refusal explains why")
  hero.weapon.durability = 10
  success, reason = Durability.repair(hero, "weapon")
  eq(success, false, "an empty purse refuses to cover the repair bill")
  eq(reason, "not enough gold", "the refusal explains why")
  success, reason = Durability.repair(hero, "bow")
  eq(success, false, "repairing an empty slot fails")
  eq(reason, "nothing equipped there", "the refusal explains why")
end

function tests.durabilityRepairRestoresFullDurabilityAndFoldsPowerBackInAfterABreak()
  local hero = { attack = 5, gold = 100, inventory = {}, kind = "player", name = "you" }
  Items.equipWeapon(Items.weapon("sword", 4), hero)
  hero.weapon.durability = 0
  hero.attack = hero.attack - 4
  local success, cost = Durability.repair(hero, "weapon")
  ok(success, "a full purse and a broken weapon repair successfully")
  eq(hero.weapon.durability, Durability.MAX, "repairing restores full durability")
  eq(cost, Durability.MAX * Durability.REPAIR_COST_PER_POINT, "repairing a fully broken item costs its full bill")
  eq(hero.gold, 100 - cost, "the repair bill is deducted from gold")
  eq(hero.attack, 9, "the weapon's power is folded back into attack once repaired")
end

function tests.durabilityRepairOnANotYetBrokenItemJustTopsUpDurabilityWithoutTouchingStats()
  local hero = { attack = 9, gold = 100 }
  hero.weapon = Items.weapon("sword", 4)
  hero.weapon.durability = 20
  local success, cost = Durability.repair(hero, "weapon")
  ok(success, "a merely dinged weapon still repairs")
  eq(hero.weapon.durability, Durability.MAX, "durability tops back up to max")
  eq(cost, (Durability.MAX - 20) * Durability.REPAIR_COST_PER_POINT, "the bill only covers the missing points")
  eq(hero.attack, 9, "attack is untouched since the weapon was never broken in the first place")
end

function tests.equipWeaponAddsOnlyEffectivePowerForAnAlreadyBrokenWeapon()
  local hero = { attack = 5, inventory = {} }
  local sword = Items.weapon("sword", 4)
  sword.durability = 0
  Items.equipWeapon(sword, hero)
  eq(hero.attack, 5, "equipping an already-broken weapon adds none of its power")
end

function tests.gamePlayerAttackWearsTheEquippedWeaponAndLogsWhenItBreaks()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Items.weapon("dagger", 2), game.player)
  game.player.weapon.durability = 1
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 999, 999
  game:playerAttack(orc)
  eq(game.player.weapon.durability, 0, "the weapon's last durability point is spent on this hit")
  local broke = false
  for _, line in ipairs(game.log:recent(6)) do
    if contains(line, "breaks apart") then broke = true end
  end
  ok(broke, "the weapon breaking is reported in the message log")
end

function tests.gameMonsterMeleeWearsThePlayersArmorAndLogsWhenItBreaks()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipArmor(Items.armor("plate", 3), game.player)
  game.player.armor.durability = 1
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  game:monsterMelee(orc)
  eq(game.player.armor.durability, 0, "the armor's last durability point is spent on this hit")
  local broke = false
  for _, line in ipairs(game.log:recent(6)) do
    if contains(line, "battered") then broke = true end
  end
  ok(broke, "the armor breaking is reported in the message log")
end

function tests.gameFireAtWearsTheEquippedBowAndLogsWhenItBreaks()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.bow = Items.bow("shortbow", 3, 6)
  game.player.bow.durability = 1
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 5)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  orc.hp, orc.maxHp = 999, 999
  game:fireAt(orc)
  eq(game.player.bow.durability, 0, "the bow's last durability point is spent on this shot")
  ok(contains(game.log:last(), "snaps"), "the bow snapping is the shot's own last log line")
end

function tests.gameBrokenEquippedSlotFindsTheFirstBrokenPieceInPriorityOrder()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  eq(game:brokenEquippedSlot(), nil, "a fresh player with no gear has nothing broken")
  Items.equipArmor(Items.armor("plate", 3), game.player)
  game.player.armor.durability = 0
  eq(game:brokenEquippedSlot(), "armor", "the only broken piece is found")
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  game.player.weapon.durability = 0
  eq(game:brokenEquippedSlot(), "weapon", "weapon takes priority over armor once both are broken")
end

function tests.gameRepairEquippedSpendsGoldAndLogsSuccess()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  game.player.weapon.durability = 0
  game.player.gold = 1000
  local before = game.player.gold
  local success = game:repairEquipped("weapon")
  ok(success, "a full purse repairs the broken weapon")
  eq(game.player.weapon.durability, Durability.MAX, "the weapon comes back to full durability")
  ok(game.player.gold < before, "gold is spent on the repair")
  ok(contains(game.log:last(), "repair"), "the repair is logged")
end

function tests.gameRepairEquippedFailsAndLogsWhenGoldIsShort()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  game.player.weapon.durability = 0
  game.player.gold = 0
  local success = game:repairEquipped("weapon")
  eq(success, false, "an empty purse cannot repair")
  eq(game.player.weapon.durability, 0, "the weapon stays broken")
  ok(contains(game.log:last(), "cannot repair"), "the failure is logged")
end

function tests.durabilityFieldsSurviveSerialization()
  local game = Game.new(3)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  game.player.weapon.durability = 7
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.weapon.durability, 7, "a weapon's own durability survives a save/load round trip")
  eq(restored.player.weapon.maxDurability, Durability.MAX, "a weapon's max durability survives a save/load round trip")
end

return tests
