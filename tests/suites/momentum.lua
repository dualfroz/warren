local helpers = require("helpers")
local Rng = require("rng")
local Entity = require("entity")
local Monsters = require("monsters")
local Game = require("game")
local Momentum = require("momentum")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.momentumStacksReadsZeroForAFreshEntity()
  eq(Momentum.stacks({}), 0, "an entity with no combo field reads as zero stacks")
end

function tests.momentumOnMeleeHitBuildsAndCapsAtItsMaxStacks()
  local entity = {}
  for i = 1, Momentum.MAX_STACKS do
    Momentum.onMeleeHit(entity)
    eq(Momentum.stacks(entity), i, "stack " .. i .. " builds one at a time")
  end
  Momentum.onMeleeHit(entity)
  eq(Momentum.stacks(entity), Momentum.MAX_STACKS, "stacks never climb past the cap")
end

function tests.momentumOnDamagedSnapsTheStackBackToZero()
  local entity = { combo = 3 }
  Momentum.onDamaged(entity)
  eq(Momentum.stacks(entity), 0, "taking a hit clears the whole stack outright")
end

function tests.momentumAttackBonusScalesLinearlyWithStacks()
  local entity = {}
  eq(Momentum.attackBonus(entity), 0, "no stacks means no bonus")
  Momentum.onMeleeHit(entity)
  Momentum.onMeleeHit(entity)
  eq(Momentum.attackBonus(entity), 2 * Momentum.BONUS_PER_STACK, "the bonus scales with the current stack count")
end

function tests.entityEffectiveAttackFoldsInMomentumAlongsideStatusModifiers()
  local entity = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 2 })
  eq(entity:effectiveAttack(), 6, "a fresh entity's effective attack is just its base")
  Momentum.onMeleeHit(entity)
  Momentum.onMeleeHit(entity)
  eq(entity:effectiveAttack(), 8, "two momentum stacks add their flat bonus on top of base attack")
end

function tests.gamePlayerAttackBuildsMomentumAndItReadsLiveInEffectiveAttack()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 100, 100
  game.level.entities = { orc }
  eq(game.player:effectiveAttack(), game.player.attack, "a fresh player carries no momentum bonus")
  game:playerAttack(orc)
  eq(game.player.combo, 1, "a landed melee hit builds one stack")
  eq(game.player:effectiveAttack(), game.player.attack + 1,
    "the very next read of effectiveAttack already reflects the new stack")
end

function tests.gameMonsterMeleeSnapsMomentumBackToZero()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.combo = 4
  local orc = Monsters.create(Monsters.byKey.orc, 1, 2, 6, 1)
  game:monsterMelee(orc)
  eq(game.player.combo, 0, "getting hit by a monster's melee resets momentum to zero")
end

function tests.gameEvadedMonsterAttackNeverBreaksMomentum()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.skills = { evasion = true }
  local orc = Monsters.create(Monsters.byKey.orc, 1, 2, 6, 1)
  local sawEvasion = false
  for seed = 1, 40 do
    game.rng = Rng.new(seed)
    game.player.combo = 3
    game:monsterMelee(orc)
    if game.player.combo == 3 then sawEvasion = true break end
  end
  ok(sawEvasion, "an evaded attack never reaches Combat.attack, so momentum survives it")
end

function tests.momentumFieldSurvivesSerialization()
  local game = Game.new(3)
  game.player.combo = 4
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.combo, 4, "the player's momentum stack survives a save/load round trip")
end

return tests
