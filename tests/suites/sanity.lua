local helpers = require("helpers")
local Rng = require("rng")
local Entity = require("entity")
local Items = require("items")
local Monsters = require("monsters")
local Game = require("game")
local Atmosphere = require("atmosphere")
local Stealth = require("stealth")
local Curses = require("curses")
local Sanity = require("sanity")

local ok, eq, contains, arena, stagedGame, arenaDark = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame, helpers.arenaDark

local tests = helpers.suite()

function tests.sanityCurrentDefaultsToMaxForAFreshEntity()
  eq(Sanity.current({}), Sanity.MAX, "an entity with no sanity field reads as fully composed")
end

function tests.sanityTierOfClassifiesEachBandAtItsBoundaries()
  eq(Sanity.tierOf({ sanity = 100 }), Sanity.COMPOSED, "a full meter is composed")
  eq(Sanity.tierOf({ sanity = 61 }), Sanity.COMPOSED, "just above the shaken ceiling is still composed")
  eq(Sanity.tierOf({ sanity = 60 }), Sanity.SHAKEN, "the shaken ceiling itself reads as shaken")
  eq(Sanity.tierOf({ sanity = 31 }), Sanity.SHAKEN, "just above the terrified ceiling is still shaken")
  eq(Sanity.tierOf({ sanity = 30 }), Sanity.TERRIFIED, "the terrified ceiling itself reads as terrified")
  eq(Sanity.tierOf({ sanity = 1 }), Sanity.TERRIFIED, "one point above zero is still terrified, never broken")
  eq(Sanity.tierOf({ sanity = 0 }), Sanity.BROKEN, "zero itself is broken")
end

function tests.sanityAdjustClampsToTheZeroAndMaxBounds()
  local entity = { sanity = 95 }
  eq(Sanity.adjust(entity, 30), Sanity.MAX, "adjusting past the ceiling clamps to max")
  eq(Sanity.adjust(entity, -1000), 0, "adjusting far past the floor clamps to zero")
  eq(Sanity.adjust(entity, 5), 5, "an ordinary adjustment lands exactly where expected")
end

function tests.sanityAttackAndDefensePenaltiesEscalateByTier()
  eq(Sanity.attackPenalty({ sanity = 100 }), 0, "a composed mind carries no attack penalty")
  eq(Sanity.attackPenalty({ sanity = 60 }), -1, "shaken costs a point of attack")
  eq(Sanity.attackPenalty({ sanity = 30 }), -3, "terrified costs three points of attack")
  eq(Sanity.attackPenalty({ sanity = 0 }), -5, "broken costs five points of attack")
  eq(Sanity.defensePenalty({ sanity = 100 }), 0, "a composed mind carries no defense penalty")
  eq(Sanity.defensePenalty({ sanity = 60 }), -1, "shaken costs a point of defense")
  eq(Sanity.defensePenalty({ sanity = 30 }), -2, "terrified costs two points of defense")
  eq(Sanity.defensePenalty({ sanity = 0 }), -4, "broken costs four points of defense")
end

function tests.entityEffectiveAttackAndDefenseFoldInTheSanityPenalty()
  local entity = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 4 })
  eq(entity:effectiveAttack(), 6, "a fresh entity with no sanity field carries no penalty")
  entity.sanity = 0
  eq(entity:effectiveAttack(), 1, "a broken mind's attack penalty is live in effectiveAttack")
  eq(entity:effectiveDefense(), 0, "a broken mind's defense penalty is live in effectiveDefense")
end

function tests.sanityDarknessDreadFiresOnlyOnADarkFloorWithASpentTorch()
  local dark = stagedGame(1, arenaDark(21, 11), 3, 6)
  dark.player.light.fuel = 0
  eq(Sanity.darknessDread(dark), Sanity.DARKNESS_DREAD, "a dark floor with a spent torch dreads the mind")
  dark.player.light.fuel = 50
  eq(Sanity.darknessDread(dark), 0, "a lit torch on a dark floor holds the dread off entirely")
  local lit = stagedGame(1, arena(21, 11), 3, 6)
  lit.player.light.fuel = 0
  eq(Sanity.darknessDread(lit), 0, "an ordinary floor never dreads the mind regardless of torch fuel")
end

function tests.sanityCorpseDreadCountsOnlyCorpsesAdjacentToThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.corpses = { { x = 2, y = 5 } }
  eq(Sanity.corpseDread(game), Sanity.CORPSE_DREAD_PER, "one adjacent corpse contributes its fixed share")
  game.level.corpses[#game.level.corpses + 1] = { x = 10, y = 6 }
  eq(Sanity.corpseDread(game), Sanity.CORPSE_DREAD_PER, "a corpse well outside arm's reach adds nothing")
end

function tests.sanityCorpseDreadCapsAtItsFixedCeiling()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.corpses = {
    { x = 2, y = 5 }, { x = 2, y = 6 }, { x = 2, y = 7 }, { x = 3, y = 5 }, { x = 3, y = 7 },
  }
  eq(Sanity.corpseDread(game), Sanity.CORPSE_DREAD_CAP, "five adjacent corpses still cap at the fixed ceiling")
end

function tests.sanityUndeadDreadCountsOnlyVisibleUndeadAndCapsAtItsCeiling()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local zombie = Monsters.create(Monsters.byKey.zombie, 1, 4, 6, 1)
  game.level.entities = { zombie }
  eq(Sanity.undeadDread(game), Sanity.UNDEAD_DREAD_PER, "one visible undead contributes its fixed share")
  game.visible = {}
  eq(Sanity.undeadDread(game), 0, "an undead outside the player's sight adds nothing")
  game:computeVisible()
  local orc = Monsters.create(Monsters.byKey.orc, 2, 5, 6, 1)
  game.level.entities[#game.level.entities + 1] = orc
  eq(Sanity.undeadDread(game), Sanity.UNDEAD_DREAD_PER, "a visible living monster never counts as undead dread")
  for i = 3, 6 do
    game.level.entities[#game.level.entities + 1] = Monsters.create(Monsters.byKey.zombie, i, 6, 6, 1)
  end
  eq(Sanity.undeadDread(game), Sanity.UNDEAD_DREAD_CAP, "a crowd of visible undead still caps at the fixed ceiling")
end

function tests.sanityCurseDreadFiresOnlyForARevealedCurse()
  local player = { ring = Curses.afflict(Items.ring("ring of power", 0, 0), Curses.pool.ring[1]) }
  eq(Sanity.curseDread(player), 0, "a curse still hidden behind an ordinary appearance dreads nothing")
  Curses.reveal(player.ring)
  eq(Sanity.curseDread(player), Sanity.CURSE_DREAD, "a revealed curse gnaws at the mind")
end

function tests.sanityWeatherDreadFiresOnlyForInfestedWeather()
  eq(Sanity.weatherDread(Atmosphere.INFESTED), Sanity.WEATHER_DREAD, "an infested floor dreads the mind")
  eq(Sanity.weatherDread(Atmosphere.FOGGY), 0, "a merely foggy floor is not itself dreadful")
  eq(Sanity.weatherDread(nil), 0, "a clear floor carries no weather dread")
end

function tests.sanityTotalDreadSumsEverySourceAtOnce()
  local dark = stagedGame(1, arenaDark(21, 11), 3, 6)
  dark.player.light.fuel = 0
  dark.level.weather = Atmosphere.INFESTED
  dark.level.corpses = { { x = 2, y = 5 } }
  eq(Sanity.totalDread(dark), Sanity.DARKNESS_DREAD + Sanity.WEATHER_DREAD + Sanity.CORPSE_DREAD_PER,
    "every currently-active dread source is summed at once")
end

function tests.sanityTickAppliesDreadAndLogsOnlyOnATierCrossing()
  local game = stagedGame(1, arenaDark(21, 11), 3, 6)
  game.player.light.fuel = 0
  game.player.sanity = 63
  eq(Sanity.tick(game), nil, "a dread turn that stays within its tier reports no line")
  eq(game.player.sanity, 61, "the dread was still deducted even without a tier crossing")
  eq(Sanity.tick(game), "your nerves begin to fray", "crossing down into shaken is announced")
  eq(game.player.sanity, 59, "the meter keeps draining turn over turn")
end

function tests.sanityTickAnnouncesReachingTerrifiedAndBroken()
  local game = stagedGame(1, arenaDark(21, 11), 3, 6)
  game.player.light.fuel = 0
  game.player.sanity = 32
  eq(Sanity.tick(game), "dread claws at the edges of your sanity", "crossing down into terrified is announced")
  game.player.sanity = 2
  eq(Sanity.tick(game), "your mind gives way to raw terror", "crossing down into broken is announced")
  eq(game.player.sanity, 0, "broken is a floor, not a negative value")
end

function tests.sanityTickRecoversAndAnnouncesClimbingBackOutOfBroken()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.sanity = 0
  eq(Sanity.tick(game), "your nerves start to steady",
    "recovering out of broken is announced as steadying, never as fresh dread")
  eq(game.player.sanity, 1, "a calm turn only ever recovers its small fixed amount")
end

function tests.sanityTickAnnouncesFullyRegainingComposure()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.sanity = 60
  eq(Sanity.tick(game), "your mind is your own again", "climbing back above the shaken ceiling is announced")
end

function tests.sanityTickNeverClimbsPastTheMaxOrReportsAPhantomCrossing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.sanity = 100
  eq(Sanity.tick(game), nil, "an already-composed mind with nothing to recover reports no line")
  eq(game.player.sanity, 100, "recovery never climbs the meter past its own maximum")
end

function tests.sanityRollPanicNeverFiresAboveBroken()
  local entity = { sanity = 1 }
  for seed = 1, 50 do
    ok(not Sanity.rollPanic(Rng.new(seed), entity), "terrified never risks losing the turn to panic")
  end
end

function tests.sanityRollPanicRollsAgainstItsFixedChanceOnceBroken()
  local entity = { sanity = 0 }
  local sawPanic, sawComposure = false, false
  for seed = 1, 50 do
    if Sanity.rollPanic(Rng.new(seed), entity) then sawPanic = true else sawComposure = true end
  end
  ok(sawPanic, "broken panics on at least some rolls across a handful of seeds")
  ok(sawComposure, "broken does not panic on every single roll")
end

function tests.sanityRollScreamNeverFiresAboveTerrified()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.sanity = 31
  for seed = 1, 50 do
    game.rng = Rng.new(seed)
    ok(not Sanity.rollScream(game.rng, game), "merely shaken never risks an involuntary scream")
  end
end

function tests.sanityRollScreamAlertsEveryDormantMonsterWithinItsRadius()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.sanity = 0
  local zombie = Monsters.create(Monsters.byKey.zombie, 1, 5, 6, 1)
  zombie.awareness = Stealth.DORMANT
  game.level.entities = { zombie }
  local triggered = false
  for seed = 1, 80 do
    game.rng = Rng.new(seed)
    if Sanity.rollScream(game.rng, game) then triggered = true break end
  end
  ok(triggered, "a broken mind eventually screams across a handful of seeds")
  eq(zombie.awareness, Stealth.HUNTING, "the scream startles a nearby dormant monster fully awake")
  eq(zombie.lastKnownX, game.player.x, "the alerted monster now knows exactly where the scream came from")
end

function tests.sanityFieldSurvivesSerialization()
  local game = Game.new(3)
  game.player.sanity = 37
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.sanity, 37, "the player's sanity survives a save/load round trip")
end

function tests.gameEndPlayerTurnTicksSanityAndTheLogReportsATierCrossing()
  local game = stagedGame(1, arenaDark(21, 11), 3, 6)
  game.player.light.fuel = 0
  game.player.sanity = 63
  game:endPlayerTurn()
  eq(game.player.sanity, 61, "ending a turn on a dark, torchless floor drains the fixed darkness dread")
  game:endPlayerTurn()
  ok(contains(game.log:last(), "fray"), "crossing into shaken is reported in the message log")
  eq(game.player:effectiveAttack(), game.player.attack - 1, "the fresh shaken penalty is already live in effectiveAttack")
end

function tests.gameAutoStepSkipsThePlayerTurnWhenPanicFires()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.sanity = 0
  local px, py = game.player.x, game.player.y
  local sawPanic = false
  for seed = 1, 80 do
    game.rng = Rng.new(seed)
    game.player.x, game.player.y = px, py
    game.player.sanity = 0
    game:autoStep()
    if contains(table.concat(game.log:recent(3), " "), "terror seizes you") then sawPanic = true break end
  end
  ok(sawPanic, "a broken mind eventually loses a whole turn to panic across a handful of seeds")
  eq(game.player.x, px, "a panicked turn never moves the player")
  eq(game.player.y, py, "a panicked turn never moves the player")
end

function tests.gameUseItemPotionOfClarityRestoresSanity()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.sanity = 40
  game.player.inventory = { Items.potionOf("clarity", 30) }
  ok(game:useItem(1), "drinking the potion of clarity succeeds")
  eq(game.player.sanity, 70, "clarity restores its fixed power to the drinker's sanity")
  ok(contains(game.log:last(), "steadies"), "the log reports the mind steadying")
end

return tests
