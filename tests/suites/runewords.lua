local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Monsters = require("monsters")
local Builder = require("builder")
local Game = require("game")
local Runewords = require("runewords")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.runewordsSocketAppendsToTheChainInOrderAndCapsAtMaxRunes()
  local sword = Items.weapon("sword", 4)
  ok(Runewords.socket(sword, Runewords.rune("sol")), "socketing a rune into a bare weapon succeeds")
  ok(Runewords.socket(sword, Runewords.rune("ith")), "a second rune joins the same chain")
  eq(table.concat(sword.runes, "-"), "sol-ith", "the chain records runes in the order they were socketed")
  ok(Runewords.socket(sword, Runewords.rune("tal")), "a third rune still fits under the cap")
  local success, reason = Runewords.socket(sword, Runewords.rune("ral"))
  eq(success, false, "a fourth rune overflows the chain")
  eq(reason, "the rune chain is full", "socket explains why a full chain refuses another rune")
end

function tests.runewordsSocketRefusesAnythingThatIsNotWeaponOrArmor()
  local potion = Items.potion(10)
  local success, reason = Runewords.socket(potion, Runewords.rune("sol"))
  eq(success, false, "a potion cannot hold a rune chain")
  eq(reason, "cannot hold runes", "socket explains why a non-gear item refuses a rune")
end

function tests.runewordsActiveWordMatchesOnlyAnExactChain()
  local sword = Items.weapon("sword", 4)
  eq(Runewords.activeWord(sword), nil, "a bare weapon forms no runeword")
  Runewords.socket(sword, Runewords.rune("sol"))
  eq(Runewords.activeWord(sword), nil, "a single rune alone matches no cataloged word")
  Runewords.socket(sword, Runewords.rune("ith"))
  local word = Runewords.activeWord(sword)
  ok(word ~= nil, "sol then ith completes the Zenith runeword")
  eq(word.name, "Zenith", "the matched word is the cataloged Zenith")
  Runewords.socket(sword, Runewords.rune("tal"))
  eq(Runewords.activeWord(sword), nil, "a third rune growing past Zenith's length breaks its match")
end

function tests.runewordsAttackAndDefenseBonusReadTheWielderSGearLive()
  local player = { weapon = Items.weapon("sword", 4), armor = Items.armor("chain mail", 2) }
  eq(Runewords.attackBonus(player), 0, "no bonus applies before any runeword completes")
  eq(Runewords.defenseBonus(player), 0, "no defense bonus applies before any runeword completes")
  Runewords.socket(player.weapon, Runewords.rune("sol"))
  Runewords.socket(player.weapon, Runewords.rune("ith"))
  eq(Runewords.attackBonus(player), 3, "a completed Zenith on the weapon grants its flat attack bonus")
  Runewords.socket(player.armor, Runewords.rune("tal"))
  Runewords.socket(player.armor, Runewords.rune("ral"))
  eq(Runewords.defenseBonus(player), 3, "a completed Bastion on the armor grants its flat defense bonus")
  eq(Runewords.attackBonus(player), 3, "the armor's runeword does not leak an attack bonus")
end

function tests.gameSocketRuneAppliesItsRunewordBonusInActualCombat()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.defense, orc.baseDefense, orc.hp, orc.maxHp = 0, 0, 40, 40
  game.level.entities = { orc }
  local before = orc.hp
  game:playerAttack(orc)
  local plainDamage = before - orc.hp

  local game2 = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Items.weapon("sword", 4), game2.player)
  local orc2 = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc2.defense, orc2.baseDefense, orc2.hp, orc2.maxHp = 0, 0, 40, 40
  game2.level.entities = { orc2 }
  game2.player.inventory = { Runewords.rune("sol"), Runewords.rune("ith") }
  ok(game2:socketRune("weapon", 1), "socketing the first rune into the equipped weapon succeeds")
  ok(game2:socketRune("weapon", 1), "socketing the second rune completes the runeword")
  eq(#game2.player.inventory, 0, "both runes leave the inventory once socketed")
  ok(contains(game2.log:last(), "Zenith"), "completing a runeword is announced by name")
  local before2 = orc2.hp
  game2:playerAttack(orc2)
  local runewordDamage = before2 - orc2.hp
  ok(runewordDamage > plainDamage, "a completed Zenith runeword deals more damage than the bare weapon")
  eq(runewordDamage - plainDamage, 3, "the extra damage matches Zenith's exact flat attack bonus")
end

function tests.gameSocketRuneFailsOnAnUnknownTargetOrANonRuneItem()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  game.player.inventory = { Items.potion(10) }
  eq(game:socketRune("weapon", 1), false, "socketing a non-rune item fails")
  game.player.inventory = { Runewords.rune("sol") }
  eq(game:socketRune("armor", 1), false, "socketing into gear the player has not equipped fails")
  eq(#game.player.inventory, 1, "a failed socket attempt leaves the rune in inventory")
end

function tests.runesStayOffTheShallowestTwoFloors()
  for seed = 1, 6 do
    for depth = 1, 2 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, ground in ipairs(level.floorItems) do
        ok(ground.item.kind ~= Items.RUNE, "no rune appears on the shallowest two floors")
      end
    end
  end
end

function tests.runeChainFieldsSurviveSerialization()
  local game = Game.new(3)
  local sword = Items.weapon("sword", 4)
  Items.equipWeapon(sword, game.player)
  Runewords.socket(sword, Runewords.rune("sol"))
  Runewords.socket(sword, Runewords.rune("ith"))
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(table.concat(restored.player.weapon.runes, "-"), "sol-ith", "a weapon's rune chain survives a save/load round trip")
  ok(Runewords.activeWord(restored.player.weapon) ~= nil, "the restored chain still forms its runeword")
end

return tests
