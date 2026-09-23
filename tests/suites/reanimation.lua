local helpers = require("helpers")
local Status = require("status")
local Monsters = require("monsters")
local Level = require("level")
local Stealth = require("stealth")
local Corpses = require("corpses")
local Reanimation = require("reanimation")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.reanimationRaiseCreatesAThrallAdjacentToThePlayerAndSpendsTheCorpseAndSanity()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  local corpse = game.level.corpses[1]
  local sanityBefore = game.player.sanity
  local thrall = Reanimation.raise(game, corpse)
  ok(thrall ~= nil, "raising a fresh corpse succeeds")
  eq(thrall.kind, "thrall", "a raised thrall is tagged with the thrall kind")
  eq(math.max(math.abs(thrall.x - 5), math.abs(thrall.y - 5)), 1, "the thrall rises adjacent to the player")
  eq(#game.level.corpses, 0, "raising the corpse consumes it")
  eq(game.player.sanity, sanityBefore - Reanimation.SANITY_COST, "raising a thrall costs a fixed bite of sanity")
end

function tests.reanimationRaiseRefusesARottenCorpseWithoutSpendingAnything()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  game.level.corpses[1].decay = Corpses.ROT_TURNS
  local sanityBefore = game.player.sanity
  local thrall, line = Reanimation.raise(game, game.level.corpses[1])
  eq(thrall, nil, "a rotten corpse cannot be raised")
  eq(#game.level.corpses, 1, "a refused raise leaves the corpse in place")
  eq(game.player.sanity, sanityBefore, "a refused raise spends no sanity")
  ok(contains(line, "rotted"), "the refusal explains the corpse has rotted too far")
end

function tests.reanimationRaiseRefusesWithoutEnoughSanityAndLeavesTheCorpseAlone()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  game.player.sanity = Reanimation.SANITY_COST - 1
  local thrall, line = Reanimation.raise(game, game.level.corpses[1])
  eq(thrall, nil, "raising fails when sanity is too low to pay the cost")
  eq(#game.level.corpses, 1, "a refused raise for lack of sanity leaves the corpse untouched")
  ok(contains(line, "mind"), "the refusal blames the player's own frail grip on their mind")
end

function tests.reanimationRaiseScalesThrallStatsDownFromTheOriginSpecies()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local troll = Monsters.create(Monsters.byKey.troll, 1, 5, 5, 5)
  Corpses.spawn(game.level, troll)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  eq(thrall.hp, math.floor(Monsters.byKey.troll.hp * Reanimation.HP_FRACTION),
    "a thrall's hp is a fixed fraction of the living species' own hp")
  eq(thrall.attack, Monsters.byKey.troll.attack - Reanimation.ATTACK_PENALTY,
    "a thrall's attack is blunted by a fixed amount from the living species")
  eq(thrall.defense, Monsters.byKey.troll.defense, "a thrall keeps the living species' own defense")
end

function tests.reanimationRaiseFallsBackToAPlainSkeletonForAnUnrecognisedSpecies()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.corpses[1] = { x = 5, y = 5, species = "unknown-thing", name = "unknown-thing", decay = Corpses.DECAY_TURNS }
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  ok(thrall ~= nil, "a corpse of an unrecognised species can still be raised")
  eq(thrall.hp, 8, "an unrecognised species falls back to a flat skeleton hp")
  eq(thrall.attack, 2, "an unrecognised species falls back to a flat skeleton attack")
end

function tests.reanimationRaiseRetiresAnEarlierThrallWhenRaisingAnother()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat1 = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat1)
  local first = Reanimation.raise(game, game.level.corpses[1])
  local rat2 = Monsters.create(Monsters.byKey.rat, 2, 6, 5, 1)
  Corpses.spawn(game.level, rat2)
  local second = Reanimation.raise(game, game.level.corpses[1])
  ok(not first:isAlive(), "raising a new thrall retires the earlier one")
  ok(second:isAlive(), "the freshly raised thrall is alive")
  local alive = 0
  for _, e in ipairs(game.level.entities) do
    if e.kind == "thrall" and e:isAlive() then alive = alive + 1 end
  end
  eq(alive, 1, "only one thrall is ever alive at a time")
end

function tests.reanimationActAttacksAnAdjacentHostileMonsterAndCanKillIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 5, 5, 6)
  Corpses.spawn(game.level, chieftain)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local rat = Monsters.create(Monsters.byKey.rat, 50, thrall.x + 1, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local xpBefore = game.player.xp
  Reanimation.act(game, thrall)
  eq(rat.hp, 0, "a thrall's hit kills the weak rat standing next to it")
  ok(game.player.xp > xpBefore, "the player is credited xp for its thrall's kill")
end

function tests.reanimationActAdvancesOnAVisibleMonsterItCannotYetReach()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local orc = Monsters.create(Monsters.byKey.orc, 50, thrall.x + 5, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX = thrall.x
  Reanimation.act(game, thrall)
  ok(thrall.x > startX, "the thrall closes the distance to a monster it can see but not reach")
end

function tests.reanimationActIgnoresAMonsterBeyondItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 3, 3, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local orc = Monsters.create(Monsters.byKey.orc, 50, 19, 9, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX, startY = thrall.x, thrall.y
  Reanimation.act(game, thrall)
  eq(thrall.x, startX, "a monster far outside sight range does not pull the thrall off course (x)")
  eq(thrall.y, startY, "a monster far outside sight range does not pull the thrall off course (y)")
end

function tests.reanimationActBlindedThrallOnlyDetectsAnAdjacentHostileNotOneWithinItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local farOrc = Monsters.create(Monsters.byKey.orc, 50, thrall.x + 5, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = farOrc
  Status.apply(thrall, Status.BLIND, 6, 1)
  local startX = thrall.x
  Reanimation.act(game, thrall)
  eq(thrall.x, startX, "a blinded thrall loses a sighting well within its listed sight radius")

  local rat = Monsters.create(Monsters.byKey.rat, 51, thrall.x + 1, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local ratHpBefore = rat.hp
  Reanimation.act(game, thrall)
  ok(rat.hp < ratHpBefore, "a blinded thrall still fights a hostile once it stands adjacent")
end

function tests.reanimationActAttackingAnAdjacentMonsterEmitsNoiseThatCanStirADormantBystander()
  local stirred = false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local corpseSource = Monsters.create(Monsters.byKey.rat, 40, game.player.x + 1, game.player.y, 1)
    Corpses.spawn(game.level, corpseSource)
    local thrall = Reanimation.raise(game, game.level.corpses[1])
    local target = Monsters.create(Monsters.byKey.rat, 50, thrall.x + 1, thrall.y, 1)
    local bystander = Monsters.create(Monsters.byKey.orc, 51, thrall.x + 4, thrall.y, 1)
    bystander.awareness = Stealth.DORMANT
    game.level.entities[#game.level.entities + 1] = target
    game.level.entities[#game.level.entities + 1] = bystander
    Reanimation.act(game, thrall)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a thrall's own melee is exactly as loud as any other ally's or the player's")
end

function tests.reanimationActFollowsThePlayerWhenNoMonsterIsVisible()
  local game = stagedGame(1, arena(21, 11), 10, 5)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 10, 5, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  thrall.x, thrall.y = 3, 5
  local startDist = math.abs(thrall.x - game.player.x)
  Reanimation.act(game, thrall)
  ok(math.abs(thrall.x - game.player.x) < startDist, "a thrall with no monster in sight closes in on the player")
end

function tests.reanimationActConfusedThrallSometimesStumblesInsteadOfFightingAnAdjacentHostile()
  local sawAttack, sawStumble = false, false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local rat0 = Monsters.create(Monsters.byKey.rat, 1, 3, 6, 1)
    Corpses.spawn(game.level, rat0)
    local thrall = Reanimation.raise(game, game.level.corpses[1])
    local rat = Monsters.create(Monsters.byKey.rat, 50, thrall.x + 1, thrall.y, 1)
    game.level.entities[#game.level.entities + 1] = rat
    Status.apply(thrall, Status.CONFUSE, 5, 1)
    local hpBefore = rat.hp
    Reanimation.act(game, thrall)
    if rat.hp < hpBefore then
      sawAttack = true
    else
      sawStumble = true
    end
    if sawAttack and sawStumble then break end
  end
  ok(sawAttack, "a confused thrall's roll sometimes lets it fight an adjacent hostile as normal")
  ok(sawStumble, "a confused thrall's roll sometimes overrides even a point-blank attack")
end

function tests.reanimationActCollapsesOnceItsBorrowedAnimationRunsOut()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  thrall.decay = 1
  game:takeMonsterTurn(thrall)
  eq(#game.level.entities, 0, "a thrall whose animation runs out is swept from the level")
  ok(contains(game.log:last(), "crumbles"), "a collapsing thrall's fate is logged")
end

function tests.gameRaiseCorpseSucceedsAndLogsTheCallAnswered()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  ok(game:raiseCorpse(), "raising the corpse underfoot succeeds")
  eq(#game.level.corpses, 0, "the corpse is gone after raising")
  local hasThrall = false
  for _, e in ipairs(game.level.entities) do
    if e.kind == "thrall" then hasThrall = true end
  end
  ok(hasThrall, "a thrall joins the level once raised through the game action")
  ok(contains(game.log:last(), "answers the call"), "a successful raise is logged")
end

function tests.gameRaiseCorpseFailsWithoutACorpseUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(not game:raiseCorpse(), "raising empty ground fails")
  ok(contains(game.log:last(), "nothing here"), "the failure is logged")
end

function tests.reanimationFieldsSurviveSerialization()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  thrall.decay = 17
  local restoredLevel = Level.fromData(game.level:toData())
  eq(#restoredLevel.entities, 1, "the thrall survives a level round trip")
  eq(restoredLevel.entities[1].kind, "thrall", "the thrall's kind survives a round trip")
  eq(restoredLevel.entities[1].decay, 17, "the thrall's remaining animation survives a round trip")
end

return tests
