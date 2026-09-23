local helpers = require("helpers")
local Items = require("items")
local Monsters = require("monsters")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.rangedShotHitsAtRangeAndConsumesAmmo()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  game.level.entities = { orc }
  game.player.bow = Items.bow("short bow", 2, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 2)
  local expected = game.player.baseAttack + 2 - orc:effectiveDefense()
  local success = game:fireAt(orc)
  eq(success, true, "firing at a target within range and line of sight succeeds")
  eq(orc.hp, orc.maxHp - expected, "the shot deals baseAttack plus bow power minus target defense")
  local stack
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.AMMO then stack = item end
  end
  eq(stack.count, 1, "firing consumes one arrow from the stack")
  local landed = game.level:itemsAt(orc.x, orc.y)
  eq(#landed, 1, "the spent arrow lands where the target stood")
  eq(landed[1].item.kind, Items.AMMO, "the landed item is a spent arrow")
end

function tests.rangedShotKillGrantsXp()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 9, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.player.bow = Items.bow("long bow", 3, 7)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 1)
  local xpBefore = game.player.xp
  game:fireAt(rat)
  eq(#game.level.entities, 0, "a lethal shot sweeps the monster from the level")
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "a ranged kill grants xp")
end

function tests.rangedFailsWithoutAmmo()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 9, 6, 1)
  game.level.entities = { rat }
  game.player.bow = Items.bow("short bow", 2, 6)
  local success = game:fireAt(rat)
  eq(success, false, "firing without arrows fails")
  eq(rat.hp, rat.maxHp, "a failed shot deals no damage")
end

function tests.rangedFailsOutOfRange()
  local game = stagedGame(4, arena(21, 11), 2, 2)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 19, 9, 1)
  game.level.entities = { rat }
  game.player.bow = Items.bow("short bow", 2, 3)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 3)
  local success = game:fireAt(rat)
  eq(success, false, "firing beyond the bow's range fails")
  local stack
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.AMMO then stack = item end
  end
  eq(stack.count, 3, "a failed shot does not consume ammunition")
end

function tests.ammoStacksOnPickup()
  local game = stagedGame(4, arena(21, 11), 3, 3)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 2)
  game.level.floorItems[#game.level.floorItems + 1] = { x = 3, y = 3, item = Items.ammo("arrow", 5) }
  game:pickupHere()
  local stacks, total = 0, 0
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.AMMO then
      stacks = stacks + 1
      total = item.count
    end
  end
  eq(stacks, 1, "picking up matching ammo merges into a single stack")
  eq(total, 7, "the merged stack sums both counts")
end

function tests.rangedFireDealsNoBowBonusOnceTheBowIsBroken()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.bow = Items.bow("shortbow", 5, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 10)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  orc.hp, orc.maxHp = 999, 999

  game:fireAt(orc)
  local pristineDamage = 999 - orc.hp

  orc.hp = 999
  game.player.bow.durability = 0
  game:fireAt(orc)
  local brokenDamage = 999 - orc.hp

  ok(brokenDamage < pristineDamage, "a broken bow deals strictly less damage than a working one")
  eq(brokenDamage, pristineDamage - 5, "the broken bow's missing power matches its catalog power exactly")
end

return tests
