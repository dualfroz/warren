local helpers = require("helpers")
local Entity = require("entity")
local Items = require("items")
local Monsters = require("monsters")
local Game = require("game")
local Proficiency = require("proficiency")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.proficiencyKeyForReadsFistsWhenUnarmedAndTheWeaponsNameOnceEquipped()
  eq(Proficiency.keyFor({}), Proficiency.UNARMED, "an entity with no weapon field masters bare fists")
  eq(Proficiency.keyFor({ weapon = { name = "sword" } }), "sword", "an equipped weapon is keyed by its own name")
end

function tests.proficiencyOnMeleeHitAccumulatesAndReturnsOnlyOnARankCrossing()
  local entity = {}
  for i = 1, Proficiency.RANKS[1].hits - 1 do
    local key = Proficiency.onMeleeHit(entity)
    eq(key, nil, "no rank crossed yet on hit " .. i)
  end
  local key, bonus = Proficiency.onMeleeHit(entity)
  eq(key, Proficiency.UNARMED, "the rank-crossing hit reports the mastered key")
  eq(bonus, Proficiency.RANKS[1].bonus, "the rank-crossing hit reports that rank's own bonus")
  local nextKey = Proficiency.onMeleeHit(entity)
  eq(nextKey, nil, "the very next hit past a rank reports no further milestone")
end

function tests.proficiencyAttackBonusReadsTheHighestRankCrossedForTheCurrentKeyAlone()
  local entity = { weapon = { name = "sword" } }
  for _ = 1, Proficiency.RANKS[1].hits do Proficiency.onMeleeHit(entity) end
  eq(Proficiency.attackBonus(entity), Proficiency.RANKS[1].bonus, "mastery with the equipped weapon applies")
  entity.weapon = { name = "mace" }
  eq(Proficiency.attackBonus(entity), 0, "switching to an unmastered weapon drops the bonus entirely")
  entity.weapon = { name = "sword" }
  eq(Proficiency.attackBonus(entity), Proficiency.RANKS[1].bonus,
    "re-equipping the mastered weapon picks its bonus straight back up")
end

function tests.entityEffectiveAttackFoldsInProficiencyAlongsideMomentumAndSanity()
  local entity = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 2 })
  eq(entity:effectiveAttack(), 6, "a fresh entity carries no mastery bonus")
  for _ = 1, Proficiency.RANKS[1].hits do Proficiency.onMeleeHit(entity) end
  eq(entity:effectiveAttack(), 6 + Proficiency.RANKS[1].bonus, "a mastered weapon's flat bonus lands on effective attack")
end

function tests.gamePlayerAttackAccumulatesProficiencyAndLogsOnlyOnARankCrossing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 999, 999
  game.level.entities = { orc }
  for _ = 1, Proficiency.RANKS[1].hits - 1 do
    game:playerAttack(orc)
  end
  ok(not contains(game.log:last(), "skilled"), "no milestone logged before the rank is actually crossed")
  game:playerAttack(orc)
  ok(contains(game.log:last(), "skilled"), "crossing a mastery rank is announced as the very last log line")
  eq(game.player.proficiency[Proficiency.UNARMED], Proficiency.RANKS[1].hits,
    "an unarmed player's landed hits accumulate under the fists key")
end

function tests.proficiencyFieldSurvivesSerialization()
  local game = Game.new(3)
  for _ = 1, Proficiency.RANKS[1].hits do Proficiency.onMeleeHit(game.player) end
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.proficiency[Proficiency.UNARMED], Proficiency.RANKS[1].hits,
    "the player's accumulated mastery survives a save/load round trip")
end

function tests.proficiencyOnHitWithAndBonusForTrackAnExplicitKeyIndependentOfKeyFor()
  local entity = { weapon = { name = "sword" } }
  for _ = 1, Proficiency.RANKS[1].hits do Proficiency.onHitWith(entity, "short bow") end
  eq(Proficiency.bonusFor(entity, "short bow"), Proficiency.RANKS[1].bonus,
    "an explicit key masters independently of whatever keyFor would report")
  eq(Proficiency.attackBonus(entity), 0,
    "the equipped melee weapon's own mastery is untouched by an explicit-key bow's own hits")
end

function tests.gameFireAtAccumulatesBowSpecificProficiencySeparateFromMelee()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  orc.hp, orc.maxHp = 999, 999
  game.level.entities = { orc }
  game.player.bow = Items.bow("short bow", 2, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", Proficiency.RANKS[1].hits + 1)
  for i = 1, Proficiency.RANKS[1].hits - 1 do
    game:fireAt(orc)
    ok(not contains(game.log:last(), "skilled"), "no milestone logged before the rank is actually crossed")
  end
  game:fireAt(orc)
  ok(contains(game.log:last(), "skilled"), "crossing a bow mastery rank is announced as the shot's own last line")
  eq(game.player.proficiency["short bow"], Proficiency.RANKS[1].hits, "bow hits accumulate under the bow's own name")
  eq(game.player.proficiency[Proficiency.UNARMED], nil, "firing a bow never touches the unarmed melee key")
end

return tests
