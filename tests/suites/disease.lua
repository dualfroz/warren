local helpers = require("helpers")
local Entity = require("entity")
local Items = require("items")
local Status = require("status")
local Monsters = require("monsters")
local Level = require("level")
local Companions = require("companions")
local Resistances = require("resistances")
local Disease = require("disease")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.gameTakeMonsterTurnTicksAnInfectedCompanionsDiseaseExactlyLikeThePlayersOwnEndOfTurnDoes()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  hound.hp, hound.maxHp = 1000, 1000
  Disease.infect(hound, Disease.PARASITES)
  local incubation = Disease.defs[Disease.PARASITES].incubation
  for _ = 1, incubation - 1 do
    game:takeMonsterTurn(hound)
    eq(hound.disease.stage, 0, "the companion's infection keeps quietly incubating turn by turn")
  end
  game:takeMonsterTurn(hound)
  eq(hound.disease.stage, 1, "the companion's infection erupts on schedule, exactly like the player's own would")
  ok(contains(game.log:last(), "breaks out in gut parasites"), "the eruption is logged with the companion's own name")
end

function tests.diseaseInfectSeedsIncubationAndRefusesToStackASecondInfection()
  local host = { name = "dummy", hp = 20 }
  ok(Disease.infect(host, Disease.PARASITES), "infecting a clean host succeeds")
  ok(Disease.isInfected(host), "the host now carries an infection")
  eq(host.disease.incubation, Disease.defs[Disease.PARASITES].incubation, "incubation starts at the affliction's own listed value")
  eq(host.disease.stage, 0, "a freshly seeded infection has not erupted yet")
  ok(not Disease.infect(host, Disease.ROT), "a second affliction cannot take hold while one is already active")
  eq(host.disease.key, Disease.PARASITES, "the original infection is left completely untouched by the refused attempt")
end

function tests.diseaseUnknownKeyNeverInfects()
  local host = { name = "dummy", hp = 20 }
  ok(not Disease.infect(host, "swamp fever"), "an unrecognised affliction key never takes hold")
  ok(not Disease.isInfected(host), "the host stays clean")
end

function tests.diseaseIsInfectedAndHasEruptedTrackIncubationVsActiveStageSeparately()
  local host = { name = "dummy", hp = 20 }
  Disease.infect(host, Disease.ROT)
  ok(Disease.isInfected(host), "an incubating host already counts as infected")
  ok(not Disease.hasErupted(host), "but has not yet erupted while incubation is still counting down")
  host.disease.stage = 1
  ok(Disease.hasErupted(host), "once staged past zero the infection counts as erupted")
end

function tests.diseaseTickCountsIncubationDownInSilenceThenErupts()
  local host = { name = "dummy", hp = 20 }
  Disease.infect(host, Disease.PARASITES)
  local incubation = Disease.defs[Disease.PARASITES].incubation
  for i = 1, incubation - 1 do
    local line = Disease.tick(host)
    eq(line, nil, "each turn still incubating produces no visible symptom")
    eq(host.disease.stage, 0, "the infection has not erupted yet at turn " .. i)
  end
  local eruptionLine = Disease.tick(host)
  ok(contains(eruptionLine, "breaks out"), "the turn incubation runs out, the eruption is reported")
  eq(host.disease.stage, 1, "the infection is now active at stage one")
end

function tests.diseaseTickMessagesAddressThePlayerInSecondPersonForEruptionDamageAndEscalation()
  local player = Entity.new({
    x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 1000, maxHp = 1000, attack = 1, defense = 0,
  })
  Disease.infect(player, Disease.PARASITES)
  local incubation = Disease.defs[Disease.PARASITES].incubation
  for _ = 1, incubation - 1 do Disease.tick(player) end
  eq(Disease.tick(player), "you break out in gut parasites",
    "eruption addresses the player in second person, not 'you breaks out in gut parasites'")
  eq(Disease.tick(player), "you are wracked by gut parasites for 1",
    "a damaging tick addresses the player in second person, not 'you is wracked by gut parasites for 1'")

  local stageTurns = Disease.defs[Disease.PARASITES].stageTurns
  for _ = 2, stageTurns - 1 do Disease.tick(player) end
  eq(Disease.tick(player), "your gut parasites worsen",
    "escalation addresses the player possessively with a plural verb, not \"your gut parasites worsens\"")
end

function tests.diseaseEscalationVerbAgreesWithTheDiseaseNameForEveryHost()
  local named = { name = "the rat", hp = 1000 }
  Disease.infect(named, Disease.PARASITES)
  named.disease.stage = 1
  named.disease.sinceStage = Disease.defs[Disease.PARASITES].stageTurns - 1
  eq(Disease.tick(named), "the rat's gut parasites worsen", "a plural disease takes a plural verb on a named host")
  local rotting = { name = "the rat", hp = 1000 }
  Disease.infect(rotting, Disease.ROT)
  rotting.disease.stage = 1
  rotting.disease.sinceStage = Disease.defs[Disease.ROT].stageTurns - 1
  eq(Disease.tick(rotting), "the rat's wound rot worsens", "a singular disease keeps the singular verb")
end

function tests.diseaseTickDealsStagePotencyThroughResistancesAndEscalatesOnItsFixedSchedule()
  local host = { name = "dummy", hp = 1000 }
  Disease.infect(host, Disease.ROT)
  host.disease.stage = 1
  host.disease.sinceStage = 0
  local def = Disease.defs[Disease.ROT]
  local hpBefore = host.hp
  Disease.tick(host)
  eq(host.hp, hpBefore - def.stagePotency[1], "a stage-one tick deals exactly that stage's listed potency")
  for _ = 2, def.stageTurns - 1 do
    Disease.tick(host)
  end
  eq(host.disease.stage, 1, "the stage holds steady right up until its full window has elapsed")
  local escalationLine = Disease.tick(host)
  ok(contains(escalationLine, "worsens"), "the tick that completes the window reports the escalation")
  eq(host.disease.stage, 2, "the infection has moved on to stage two")
  eq(host.disease.sinceStage, 0, "the new stage starts its own window fresh")
end

function tests.diseaseTickNeverEscalatesPastTheTopStage()
  local host = { name = "dummy", hp = 1000 }
  Disease.infect(host, Disease.PLAGUE)
  host.disease.stage = Disease.MAX_STAGE
  host.disease.sinceStage = 0
  local def = Disease.defs[Disease.PLAGUE]
  for _ = 1, def.stageTurns * 3 do
    Disease.tick(host)
  end
  eq(host.disease.stage, Disease.MAX_STAGE, "the top stage never escalates any further, however long it lingers")
end

function tests.diseaseAnImmuneHostTakesNoDamageButStillEscalatesOnSchedule()
  local host = { name = "dummy", hp = 1000, resist = { poison = Resistances.IMMUNE } }
  Disease.infect(host, Disease.ROT)
  host.disease.stage = 1
  host.disease.sinceStage = 0
  local def = Disease.defs[Disease.ROT]
  local hpBefore = host.hp
  for _ = 1, def.stageTurns - 1 do
    local line = Disease.tick(host)
    eq(line, nil, "an immune host takes no damage, so a plain tick has nothing to report")
  end
  eq(host.hp, hpBefore, "an immune host never loses hp to the infection at all")
  local escalationLine = Disease.tick(host)
  ok(contains(escalationLine, "worsens"), "immunity blocks the damage but not the clock - the stage still worsens on schedule")
end

function tests.diseaseCureLiftsAnInfectionAtAnyStageAndReportsFalseWhenThereWasNothingToLift()
  local host = { name = "dummy", hp = 20 }
  eq(Disease.cure(host), false, "curing a clean host reports nothing was lifted")
  Disease.infect(host, Disease.PARASITES)
  ok(Disease.cure(host), "curing an incubating infection succeeds")
  ok(not Disease.isInfected(host), "the host is clean again")
  Disease.infect(host, Disease.PLAGUE)
  host.disease.stage = 3
  ok(Disease.cure(host), "curing works exactly the same on a fully erupted top-stage infection")
  ok(not Disease.isInfected(host), "the host is clean again regardless of how far the infection had progressed")
end

function tests.diseaseStagePotencyIsZeroWhileIncubatingOrUninfected()
  local host = { name = "dummy", hp = 20 }
  eq(Disease.stagePotency(host), 0, "an uninfected host has no stage potency at all")
  Disease.infect(host, Disease.ROT)
  eq(Disease.stagePotency(host), 0, "a still-incubating infection has not erupted into any potency yet")
  host.disease.stage = 2
  eq(Disease.stagePotency(host), Disease.defs[Disease.ROT].stagePotency[2], "an erupted stage reports its own listed potency")
end

function tests.gameMonsterMeleeCanInfectThePlayerViaABiteCarryingSpeciesButNeverStacksASecondInfection()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  game.level.entities = { rat }
  game.player.hp = 10000
  game.player.maxHp = 10000
  local infected = false
  for _ = 1, 400 do
    game:monsterMelee(rat)
    if Disease.isInfected(game.player) then infected = true; break end
  end
  ok(infected, "enough bites from a parasite-carrying species eventually infect the player")
  eq(game.player.disease.key, Disease.PARASITES, "the player caught exactly the species' own carried affliction")
  local firstIncubation = game.player.disease.incubation
  for _ = 1, 50 do
    game:monsterMelee(rat)
  end
  ok(game.player.disease.incubation <= firstIncubation, "further bites while already sick never restart or stack a second infection")
end

function tests.gameMonsterMeleeNeverInfectsFromASpeciesWithNoBiteDisease()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 4, 6, 1)
  eq(goblin.biteDisease, nil, "a goblin carries no disease of its own to begin with")
  game.level.entities = { goblin }
  game.player.hp = 10000
  game.player.maxHp = 10000
  for _ = 1, 400 do
    game:monsterMelee(goblin)
  end
  ok(not Disease.isInfected(game.player), "four hundred goblin bites never infect anyone, since goblins carry nothing to catch")
end

function tests.gameEndPlayerTurnTicksThePlayersDiseaseAndLogsItsEruption()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Disease.infect(game.player, Disease.PARASITES)
  local incubation = Disease.defs[Disease.PARASITES].incubation
  for _ = 1, incubation - 1 do
    game:endPlayerTurn()
    eq(game.player.disease.stage, 0, "the infection keeps quietly incubating turn by turn")
  end
  game:endPlayerTurn()
  eq(game.player.disease.stage, 1, "the infection erupts on schedule as the player's own turns tick past")
  eq(game.log:last(), "you break out in gut parasites",
    "the eruption is reported in the message log with correct you-are-the-subject grammar, not the third-person 'breaks out' a named monster would get")
end

function tests.gameUseItemDrinkingACurePotionLiftsTheInfectionAndIdentifiesThePotion()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Disease.infect(game.player, Disease.ROT)
  game.player.inventory = { Items.potionOf("cure") }
  local used = game:useItem(1)
  eq(used, true, "drinking the potion succeeds")
  ok(not Disease.isInfected(game.player), "the cure potion lifts the infection entirely")
  ok(contains(game.log:last(), "cleansed"), "the log confirms the cure took effect")
  eq(#game.player.inventory, 0, "the spent potion leaves the inventory like any other")
end

function tests.gameUseItemDrinkingACurePotionAlsoLiftsHostileStatusesNotJustDisease()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Status.apply(game.player, Status.POISON, 5, 2)
  Status.apply(game.player, Status.CONFUSE, 6, 1)
  Status.apply(game.player, Status.STRENGTH, 30, 3)
  game.player.inventory = { Items.potionOf("cure") }
  local used = game:useItem(1)
  eq(used, true, "drinking the potion succeeds")
  ok(not Status.has(game.player, Status.POISON), "the cure potion lifts poison even with no disease present")
  ok(not Status.has(game.player, Status.CONFUSE), "the cure potion lifts confusion too")
  ok(Status.has(game.player, Status.STRENGTH), "the cure potion never touches a buff like strength")
  eq(game.log:last(), "your poison and confusion fade",
    "the log reports the lifted statuses with a plural verb when there was no disease to mention")
end

function tests.gameUseItemDrinkingACurePotionReportsBothDiseaseAndStatusesWhenBothArePresent()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Disease.infect(game.player, Disease.ROT)
  Status.apply(game.player, Status.POISON, 5, 2)
  game.player.inventory = { Items.potionOf("cure") }
  game:useItem(1)
  ok(not Disease.isInfected(game.player), "the infection is lifted alongside the status effect")
  ok(not Status.has(game.player, Status.POISON), "the status effect is lifted alongside the infection")
  ok(contains(game.log:last(), "cleansed away") and contains(game.log:last(), "fades"),
    "the single log line credits both the disease cure and the status cure")
end

function tests.gameUseItemDrinkingACurePotionWithNothingToCureIsHonestInTheLog()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.inventory = { Items.potionOf("cure") }
  local used = game:useItem(1)
  eq(used, true, "the potion is still consumed even when there is nothing to cleanse")
  ok(contains(game.log:last(), "nothing to cleanse"), "the log admits nothing was actually cured")
end

function tests.diseaseAndBiteDiseaseFieldsSurviveALevelSerializationRoundTrip()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 5, 1)
  Disease.infect(rat, Disease.PLAGUE)
  rat.disease.stage = 2
  game.level.entities = { rat }

  local restored = Level.fromData(game.level:toData())
  eq(restored.entities[1].biteDisease, Disease.PARASITES, "the species' own carried affliction survives a level round trip")
  eq(restored.entities[1].disease.key, Disease.PLAGUE, "the active infection's key survives a level round trip")
  eq(restored.entities[1].disease.stage, 2, "the active infection's progressed stage survives a level round trip")
end

return tests
