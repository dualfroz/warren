local helpers = require("helpers")
local Monsters = require("monsters")
local Progression = require("progression")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.progressionLeveling()
  local player = {
    level = 1, xp = 0, xpNext = Progression.xpToNext(1),
    hp = 20, maxHp = 20, attack = 5, baseAttack = 5, defense = 1, baseDefense = 1,
  }
  local lines = Progression.grantXp(player, 5)
  eq(#lines, 0, "an xp gain under the threshold produces no level-up")
  eq(player.xp, 5, "xp accumulates")

  lines = Progression.grantXp(player, 100)
  eq(player.level > 1, true, "a large xp gain levels the player up")
  eq(#lines, player.level - 1, "one log line is produced per level gained")
  eq(player.maxHp > 20, true, "leveling raises max hp")
  eq(player.hp, player.maxHp, "leveling tops up hp by the same amount as the max hp gain")
  eq(player.attack > 5, true, "leveling raises attack")
  ok(player.xp < player.xpNext, "leftover xp after leveling stays below the new threshold")
end

function tests.progressionMonsterKillGrantsXp()
  local game = stagedGame(9, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  local xpBefore = game.player.xp
  game:playerAttack(rat)
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "felling a monster in melee grants its xp")
  eq(#game.level.entities, 0, "the dead monster is swept from the level")
end

return tests
