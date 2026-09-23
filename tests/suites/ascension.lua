local helpers = require("helpers")
local Monsters = require("monsters")
local Game = require("game")
local Meta = require("meta")
local Events = require("events")
local Ascension = require("ascension")

local ok, eq, arena = helpers.ok, helpers.eq, helpers.arena

local tests = helpers.suite()

function tests.ascensionCatalogEntriesHaveUniqueKeysAndAtLeastOneEffectHook()
  local seen = {}
  for _, def in ipairs(Ascension.MUTATORS) do
    ok(not seen[def.key], def.key .. " appears only once in the catalog")
    seen[def.key] = true
    local hasHook = def.damageMultiplier or def.essenceMultiplier or def.sightPenalty or def.applyToPlayer
    ok(hasHook ~= nil, def.key .. " carries at least one actual gameplay effect")
  end
end

function tests.ascensionIsUnlockedRequiresMeetingBothDepthAndWinRequirements()
  local meta = Meta.new()
  meta.bestDepth = 2
  ok(Ascension.isUnlocked(meta, "famine"), "famine unlocks once best depth reaches 2")
  ok(not Ascension.isUnlocked(meta, "bloodbound"), "bloodbound still needs depth 3")
  ok(not Ascension.isUnlocked(meta, "glasscannon"), "glasscannon still needs a first win")
  meta.wins = 1
  ok(Ascension.isUnlocked(meta, "glasscannon"), "glasscannon unlocks once a win is banked")
  eq(Ascension.isUnlocked(meta, "madeupkey"), false, "an unknown key is never unlocked")
end

function tests.ascensionIsUnlockedWithNoMetaLocksEveryCatalogedMutator()
  for _, key in ipairs(Ascension.order) do
    ok(not Ascension.isUnlocked(nil, key), key .. " stays locked for a run started without a meta file")
  end
end

function tests.ascensionResolveDropsUnknownAndStillLockedKeys()
  local meta = Meta.new()
  meta.bestDepth = 2
  local active = Ascension.resolve(meta, { "famine", "bloodbound", "madeupkey" })
  eq(#active, 1, "only the one unlocked, known key survives resolution")
  eq(active[1], "famine", "famine is the survivor")
end

function tests.ascensionResolveDeduplicatesAndReordersToCatalogOrder()
  local meta = Meta.new()
  meta.bestDepth = 4
  local active = Ascension.resolve(meta, { "nightblind", "famine", "nightblind", "famine" })
  eq(#active, 2, "a key repeated in the request is not duplicated in the resolved list")
  eq(active[1], "famine", "the resolved order follows the catalog, not the request")
  eq(active[2], "nightblind", "the resolved order follows the catalog, not the request")
end

function tests.ascensionResolveWithNoRequestReturnsEmpty()
  eq(#Ascension.resolve(Meta.new(), nil), 0, "a nil request resolves to no active mutators")
  eq(#Ascension.resolve(Meta.new(), {}), 0, "an empty request resolves to no active mutators")
end

function tests.ascensionIsActiveTrueOnlyForKeysInTheActiveList()
  local active = { "famine", "frail" }
  ok(Ascension.isActive(active, "famine"), "famine is reported active")
  ok(not Ascension.isActive(active, "bloodbound"), "bloodbound is reported inactive")
  ok(not Ascension.isActive(nil, "famine"), "a nil active list reports every key inactive")
end

function tests.ascensionDamageMultiplierMultipliesAcrossActiveMutators()
  eq(Ascension.damageMultiplier(nil), 1, "no active mutators leaves damage unscaled")
  eq(Ascension.damageMultiplier({ "famine" }), 1, "a mutator with no damage hook leaves damage unscaled")
  eq(Ascension.damageMultiplier({ "bloodbound" }), 1.5, "bloodbound scales damage by its own fixed multiplier")
end

function tests.ascensionEssenceMultiplierAppliesFamineAlone()
  eq(Ascension.essenceMultiplier(nil), 1, "no active mutators leaves essence unscaled")
  eq(Ascension.essenceMultiplier({ "bloodbound" }), 1, "a mutator with no essence hook leaves essence unscaled")
  eq(Ascension.essenceMultiplier({ "famine" }), 0.5, "famine halves essence income")
end

function tests.ascensionSightPenaltySumsAcrossActiveMutators()
  eq(Ascension.sightPenalty(nil), 0, "no active mutators carries no sight penalty")
  eq(Ascension.sightPenalty({ "nightblind" }), 2, "nightblind carries its own fixed sight penalty")
end

function tests.ascensionRenownBonusPercentSumsRatherThanCompounds()
  eq(Ascension.renownBonusPercent(nil), 0, "no active mutators adds no renown bonus")
  eq(Ascension.renownBonusPercent({ "famine" }), 10, "famine alone adds its own fixed bonus")
  eq(Ascension.renownBonusPercent({ "famine", "nightblind" }), 20, "two mutators add their bonuses, not compound them")
end

function tests.ascensionApplyToPlayerHalvesMaxHpAndDoublesAttackForGlassCannon()
  local player = { maxHp = 30, hp = 30, baseAttack = 5, attack = 5, baseDefense = 1, defense = 1 }
  Ascension.applyToPlayer({ "glasscannon" }, player)
  eq(player.maxHp, 15, "glass cannon halves max hp")
  eq(player.hp, 15, "current hp is clamped down to the new max")
  eq(player.attack, 10, "glass cannon doubles attack")
  eq(player.baseAttack, 10, "glass cannon doubles base attack alongside the equipped total")
  eq(player.defense, 1, "glass cannon leaves defense untouched")
end

function tests.ascensionApplyToPlayerHalvesDefenseForFrail()
  local player = { maxHp = 30, hp = 30, baseAttack = 5, attack = 5, baseDefense = 3, defense = 3 }
  Ascension.applyToPlayer({ "frail" }, player)
  eq(player.defense, 1, "frail floors defense down by half")
  eq(player.baseDefense, 1, "frail floors base defense down by half")
  eq(player.attack, 5, "frail leaves attack untouched")
end

function tests.gameNewResolvesRequestedMutatorsAgainstMetaAndAppliesTheirDeltas()
  local meta = Meta.new()
  meta.bestDepth = 4
  meta.wins = 1
  local game = Game.new(5, { meta = meta, mutators = { "unknownkey", "glasscannon", "frail" } })
  eq(#game.ascension, 2, "only the two unlocked, known mutators survive resolution")
  eq(game.ascension[1], "frail", "active mutators are ordered by the catalog, not the request")
  eq(game.ascension[2], "glasscannon", "active mutators are ordered by the catalog, not the request")
  eq(game.player.maxHp, 15, "glasscannon halves the fresh player's max hp")
  eq(game.player.defense, 0, "frail halves the fresh player's base defense down from 1")
end

function tests.gameMonsterMeleeDamageStacksBloodboundWithBloodmoonMultiplicatively()
  local meta = Meta.new()
  meta.bestDepth = 3
  local game = Game.new(1, { meta = meta, mutators = { "bloodbound" } })
  game.level = arena(21, 11)
  game.player.x, game.player.y = 3, 6
  game:computeVisible()
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)

  local before = game.player.hp
  game.ascension = {}
  game:monsterMelee(orc)
  local plainDamage = before - game.player.hp

  game.player.hp = before
  game.ascension = { "bloodbound" }
  game:monsterMelee(orc)
  local bloodboundDamage = before - game.player.hp
  eq(bloodboundDamage, math.floor(plainDamage * 1.5), "bloodbound alone scales melee damage by its own multiplier")

  game.player.hp = before
  game.level.event = { key = Events.BLOODMOON, turnsLeft = 5 }
  game:monsterMelee(orc)
  local stacked = before - game.player.hp
  eq(stacked, math.floor(plainDamage * 1.5 * Events.BLOODMOON_MULTIPLIER),
    "bloodbound and bloodmoon stack multiplicatively on the same hit")
end

function tests.gameKillEssenceStacksFamineWithRichVeinsMultiplicatively()
  local meta = Meta.new()
  meta.bestDepth = 2
  local game = Game.new(1, { meta = meta, mutators = { "famine" } })
  game.level = arena(21, 11)
  game.player.x, game.player.y = 3, 6
  game:computeVisible()

  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.ascension = {}
  local before = game.player.essence
  game:playerAttack(rat)
  local plainEssence = game.player.essence - before

  local rat2 = Monsters.create(Monsters.byKey.rat, 2, 4, 6, 1)
  rat2.hp = 1
  game.level.entities = { rat2 }
  game.player.essence = before
  game.ascension = { "famine" }
  game:playerAttack(rat2)
  local famineEssence = game.player.essence - before
  eq(famineEssence, math.floor(plainEssence * 0.5), "famine alone halves essence earned from a kill")

  local rat3 = Monsters.create(Monsters.byKey.rat, 3, 4, 6, 1)
  rat3.hp = 1
  game.level.entities = { rat3 }
  game.player.essence = before
  game.level.event = { key = Events.RICHVEINS, turnsLeft = 5 }
  game:playerAttack(rat3)
  local stackedEssence = game.player.essence - before
  eq(stackedEssence, plainEssence,
    "famine's half and rich veins' double multiply to exactly cancel back to the plain amount")
end

function tests.gameEffectiveRadiusStacksNightblindWithHush()
  local meta = Meta.new()
  meta.bestDepth = 2
  local game = Game.new(1, { meta = meta, mutators = { "nightblind" } })
  game.ascension = {}
  local noAscension = game:effectiveRadius()
  game.ascension = { "nightblind" }
  eq(game:effectiveRadius(), noAscension - 2, "nightblind alone shrinks the effective sight radius by its own penalty")
  game.level.event = { key = Events.HUSH, turnsLeft = 5 }
  eq(game:effectiveRadius(), noAscension - 2 - Events.HUSH_SIGHT_PENALTY,
    "nightblind and hush both shrink the effective sight radius, summed together")
end

function tests.ascensionFieldSurvivesASaveLoadRoundTrip()
  local meta = Meta.new()
  meta.bestDepth = 3
  local game = Game.new(4, { meta = meta, mutators = { "bloodbound" } })
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(#restored.ascension, 1, "the active ascension mutator list survives a save/load round trip")
  eq(restored.ascension[1], "bloodbound", "the restored mutator key matches what was active")
end

return tests
