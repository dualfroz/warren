local helpers = require("helpers")
local Tiles = require("tiles")
local Entity = require("entity")
local Status = require("status")
local Monsters = require("monsters")
local Companions = require("companions")
local Resistances = require("resistances")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.statusEffects()
  local victim = Entity.new({ x = 1, y = 1, glyph = "r", name = "rat", kind = "monster", hp = 10, maxHp = 10, attack = 2, defense = 0 })
  Status.apply(victim, Status.POISON, 3, 2)
  local lines = Status.tick(victim)
  eq(victim.hp, 8, "poison drains hp each tick")
  ok(#lines == 1, "poison tick emits a message")
  Status.tick(victim); Status.tick(victim)
  eq(Status.has(victim, Status.POISON), false, "poison expires after its duration")

  local hurt = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 5, maxHp = 10, attack = 1, defense = 0 })
  Status.apply(hurt, Status.REGEN, 2, 3)
  Status.tick(hurt)
  eq(hurt.hp, 8, "regeneration restores hp each tick")

  local warrior = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 10, attack = 5, defense = 1 })
  eq(warrior:effectiveAttack(), 5, "no status means base attack")
  Status.apply(warrior, Status.STRENGTH, 5, 3)
  eq(warrior:effectiveAttack(), 8, "strength raises effective attack")
  Status.apply(warrior, Status.HASTE, 5, 1)
  eq(warrior:effectiveSpeed(), 160, "haste raises effective speed")
  Status.apply(warrior, Status.STUN, 2, 1)
  eq(Status.skipsTurn(warrior), true, "stun makes an actor skip its turn")

  Status.apply(warrior, Status.STRENGTH, 99, 1)
  local strength
  for _, s in ipairs(warrior.statuses) do if s.kind == Status.STRENGTH then strength = s end end
  eq(strength.duration, 99, "re-applying a status refreshes to the longer duration")
end

function tests.gameMovePlayerConfusionEitherFollowsTheChosenDirectionOrStumblesElsewhere()
  local sawStraight, sawStumble = false, false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 10, 6)
    Status.apply(game.player, Status.CONFUSE, 5, 1)
    local consumesTurn = game:movePlayer(1, 0)
    ok(consumesTurn, "a confused player's attempted move always spends the turn on open floor")
    if game.player.x == 11 and game.player.y == 6 then
      sawStraight = true
    else
      sawStumble = true
    end
    if sawStraight and sawStumble then break end
  end
  ok(sawStraight, "confusion sometimes lets the chosen direction through untouched")
  ok(sawStumble, "confusion sometimes overrides the chosen direction")
end

function tests.gameMovePlayerConfusionStumbleIntoAWallStillSpendsTheTurn()
  local level = arena(21, 11)
  for _, cell in ipairs({ { 9, 5 }, { 10, 5 }, { 11, 5 }, { 9, 6 }, { 9, 7 }, { 10, 7 }, { 11, 7 } }) do
    level.map:set(cell[1], cell[2], Tiles.WALL)
  end
  local sawBlockedStumble = false
  for seed = 1, 500 do
    local game = stagedGame(seed, level, 10, 6)
    Status.apply(game.player, Status.CONFUSE, 5, 1)
    local consumesTurn = game:movePlayer(1, 0)
    ok(consumesTurn, "a confused move, straight or stumbled into this walled-off pocket, always spends the turn")
    if game.player.x == 10 and game.player.y == 6 then
      sawBlockedStumble = true
    end
  end
  ok(sawBlockedStumble, "at least one seed in range stumbled into a wall instead of moving east")
end

function tests.gameMovePlayerWithoutConfusionNeverStumbles()
  for seed = 1, 20 do
    local game = stagedGame(seed, arena(21, 11), 10, 6)
    game:movePlayer(1, 0)
    eq(game.player.x, 11, "an unconfused move always lands exactly where it was aimed")
    eq(game.player.y, 6, "an unconfused move never drifts off its own row")
  end
end

function tests.gameAllyActsConfusedReturnsFalseImmediatelyWithoutTheStatus()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local golem = Companions.summon(game, "golem")
  local rollsBefore = game.rng.state
  eq(game:allyActsConfused(golem), false, "an ally without Status.CONFUSE never triggers a stumble")
  eq(game.rng.state, rollsBefore, "checking an unconfused ally never advances the rng")
end

function tests.statusEffectKillGrantsXpAndLogsDeath()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 15, 9, 1)
  Status.apply(rat, Status.POISON, 1, 50)
  game.level.entities = { rat }
  local xpBefore = game.player.xp
  game:takeMonsterTurn(rat)
  eq(#game.level.entities, 0, "a monster that dies to its own status tick is swept from the level")
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "dying to a status effect still grants its xp")
  ok(contains(game.log:recent(4)[1] or "", "dies") or contains(game.log:recent(4)[2] or "", "dies")
    or contains(game.log:recent(4)[3] or "", "dies") or contains(game.log:recent(4)[4] or "", "dies"),
    "the status-effect kill is logged as a death")
end

function tests.statusPoisonAndBurningTicksRespectResistance()
  local immunePoison = Entity.new({ x = 1, y = 1, glyph = "z", name = "zombie", kind = "monster", hp = 10, maxHp = 10, attack = 2, defense = 0 })
  immunePoison.resist = { poison = Resistances.IMMUNE }
  Status.apply(immunePoison, Status.POISON, 3, 4)
  local lines = Status.tick(immunePoison)
  eq(immunePoison.hp, 10, "a poison-immune entity takes no damage from a poison tick")
  ok(contains(lines[1], "shrugs off"), "the immune tick logs a distinct shrug-off line")

  local frailToFire = Entity.new({ x = 1, y = 1, glyph = "T", name = "troll", kind = "monster", hp = 20, maxHp = 20, attack = 6, defense = 2 })
  frailToFire.resist = { fire = Resistances.WEAK }
  Status.apply(frailToFire, Status.BURNING, 3, 2)
  Status.tick(frailToFire)
  eq(frailToFire.hp, 17, "a fire-weak entity takes 1.5x the tick's potency, floored")
end

function tests.statusPoisonShrugAndRegenKnitMessagesAddressThePlayerInSecondPerson()
  local immunePlayer = Entity.new({
    x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 10, maxHp = 10, attack = 1, defense = 0,
  })
  immunePlayer.resist = { poison = Resistances.IMMUNE }
  Status.apply(immunePlayer, Status.POISON, 3, 4)
  eq(Status.tick(immunePlayer)[1], "you shrug off the poison",
    "an immune player shrugs off poison in second person, not 'you shrugs off the poison'")

  local hurtPlayer = Entity.new({
    x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 5, maxHp = 10, attack = 1, defense = 0,
  })
  Status.apply(hurtPlayer, Status.REGEN, 2, 3)
  eq(Status.tick(hurtPlayer)[1], "you knit flesh for 3",
    "a regenerating player knits flesh in second person, not 'you knits flesh for 3'")
end

function tests.statusApplyRefusesBurningOnlyWhileSoakedButOtherEffectsStillApply()
  local entity = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 2 })
  entity.wet = 2
  local result = Status.apply(entity, Status.BURNING, 3, 2)
  eq(result, nil, "applying burning to a soaked entity is refused outright")
  eq(Status.has(entity, Status.BURNING), false, "a refused burning application leaves no trace on the entity")
  Status.apply(entity, Status.POISON, 3, 2)
  eq(Status.has(entity, Status.POISON), true, "a soaked entity still catches every other status effect normally")
  entity.wet = 0
  Status.apply(entity, Status.BURNING, 3, 2)
  eq(Status.has(entity, Status.BURNING), true, "once dry again, the same entity catches fire normally")
end

function tests.statusRemoveStripsANamedStatusRegardlessOfItsRemainingDuration()
  local entity = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 2 })
  Status.apply(entity, Status.POISON, 99, 2)
  eq(Status.remove(entity, Status.POISON), true, "removing a status that is present reports success")
  eq(Status.has(entity, Status.POISON), false, "the removed status no longer reads as active")
  eq(Status.remove(entity, Status.POISON), false, "removing an already-absent status reports nothing to do")
  eq(Status.remove(entity, Status.CONFUSE), false, "removing a status that was never applied at all also reports nothing to do")
end

function tests.statusCureHostileLiftsEveryDebuffButLeavesBuffsUntouched()
  local entity = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 2 })
  Status.apply(entity, Status.POISON, 5, 2)
  Status.apply(entity, Status.CONFUSE, 6, 1)
  Status.apply(entity, Status.STUN, 2, 1)
  Status.apply(entity, Status.STRENGTH, 30, 3)
  Status.apply(entity, Status.SHIELD, 15, 1)
  local lifted = Status.cureHostile(entity)
  eq(#lifted, 3, "cureHostile reports exactly the three debuffs it lifted")
  eq(Status.has(entity, Status.POISON), false, "poison is gone after cureHostile")
  eq(Status.has(entity, Status.CONFUSE), false, "confuse is gone after cureHostile")
  eq(Status.has(entity, Status.STUN), false, "stun is gone after cureHostile")
  ok(Status.has(entity, Status.STRENGTH), "a buff like strength survives cureHostile untouched")
  ok(Status.has(entity, Status.SHIELD), "a buff like shield survives cureHostile untouched")
  eq(#Status.cureHostile(entity), 0, "calling cureHostile again with nothing hostile left returns an empty list")
end

function tests.everyStatusHasADisplayNounAndConfusionIsNoLongerAVerb()
  for kind, def in pairs(Status.defs) do
    ok(type(def.noun) == "string" and #def.noun > 0, "status " .. kind .. " has a display noun")
  end
  eq(Status.noun(Status.CONFUSE), "confusion", "confuse is shown as confusion")
  eq(Status.noun(Status.BLIND), "blindness", "blind is shown as blindness")
  eq(Status.noun(Status.WEAKEN), "weakness", "weaken is shown as weakness")
  eq(Status.noun(Status.REGEN), "regeneration", "regen is shown as regeneration")
  eq(Status.noun(Status.LEVITATE), "levitation", "levitate is shown as levitation")
  eq(Status.noun(Status.SLOW), "slowness", "slow is shown as slowness")
end

function tests.statusDescribeJoinsOneTwoAndThreeStatusesNaturally()
  eq(Status.describe({ Status.POISON }), "poison", "one status is just its noun")
  eq(Status.describe({ Status.POISON, Status.CONFUSE }), "poison and confusion", "two statuses are joined with and")
  eq(Status.describe({ Status.POISON, Status.CONFUSE, Status.BLIND }), "poison, confusion and blindness",
    "three statuses read as a, b and c")
  eq(Status.joinNaturally({ "a", "b", "c", "d" }), "a, b, c and d", "longer lists keep commas until the final and")
end

return tests
