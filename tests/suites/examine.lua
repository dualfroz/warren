local helpers = require("helpers")
local Items = require("items")
local Affixes = require("affixes")
local Shop = require("shop")
local Status = require("status")
local Monsters = require("monsters")
local Crafting = require("crafting")
local Artifacts = require("artifacts")
local Bosses = require("bosses")
local Factions = require("factions")
local Runewords = require("runewords")
local Stealth = require("stealth")
local Sets = require("sets")
local Curses = require("curses")
local Disease = require("disease")
local Examine = require("examine")

local ok, contains, arena, stagedGame = helpers.ok, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.examineItemDescribesAPlainWeaponsPowerAndDurability()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local weapon = Items.weapon("dagger", 3)
  local description = Examine.item(game.identify, weapon)
  ok(contains(description, "dagger"), "the report names the item")
  ok(contains(description, "power 3"), "the report states the weapon's power")
  ok(contains(description, "durability 30/30"), "a pristine weapon reports full durability")
  ok(contains(description, "worth " .. Shop.priceOf(weapon) .. " gold"), "the report prices the item")
end

function tests.examineItemFlagsABrokenWeaponAndAFullyTemperedBonus()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local weapon = Items.weapon("sword", 4)
  weapon.durability = 0
  weapon.temper = 2
  local description = Examine.item(game.identify, weapon)
  ok(contains(description, "(broken)"), "a broken weapon is flagged as broken")
  ok(contains(description, "tempered +2"), "the report states the temper level")
end

function tests.examineItemDescribesARingsFlatAttackAndDefenseBonus()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local ring = Items.ring("ring of the tide", 1, 2)
  ok(contains(Examine.item(game.identify, ring), "attack +1, defense +2"), "the report states the ring's flat bonuses")
end

function tests.examineItemCountsAPicksRemainingUsesWithTheRightNumber()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(contains(Examine.item(game.identify, Items.pick(nil, 1)), "1 use left"), "a last use is reported in the singular")
  ok(not contains(Examine.item(game.identify, Items.pick(nil, 1)), "1 uses left"), "a last use never reads as plural")
  ok(contains(Examine.item(game.identify, Items.pick(nil, 7)), "7 uses left"), "several uses stay plural")
end

function tests.examineItemDescribesAnAffixSocketedGemRunewordAndRevealedCurse()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local weapon = Items.weapon("sword", 4)
  Affixes.decorate(weapon, Affixes.weapon[3])
  Crafting.socket(game.player, weapon, Crafting.gem(Crafting.FROST, 1))
  Runewords.socket(weapon, Runewords.rune("sol"))
  Runewords.socket(weapon, Runewords.rune("ith"))
  Curses.afflict(weapon, Curses.pool.weapon[1])
  Curses.reveal(weapon)
  local description = Examine.item(game.identify, weapon)
  ok(contains(description, "affix: flaming"), "the report names the rolled affix")
  ok(contains(description, "on hit: burning, 3 turns, potency 2"), "the report states the affix's on-hit rider")
  ok(contains(description, "socketed: tier 1 frost gem"), "the report states the socketed gem")
  ok(contains(description, "runeword Zenith: attack +3"), "the report names the completed runeword and its bonus")
  ok(contains(description, "cursed (weakness)"), "a revealed curse is called out by name")
end

function tests.examineItemNamesAnArtifactsUniquePowerAndASetPiecesSetName()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local artifact = Artifacts.create("bloodfang")
  ok(contains(Examine.item(game.identify, artifact), "artifact power: lifesteal"), "the report names the artifact's unique power")
  local setPiece = Sets.create("ironclad", "weapon")
  ok(contains(Examine.item(game.identify, setPiece), "set piece: Ironclad"), "the report names the set the piece belongs to")
end

function tests.examineItemListsTheElementalResistanceAWornArtifactGrants()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local cinderplate = Artifacts.create("cinderplate")
  ok(contains(Examine.item(game.identify, cinderplate), "grants: fire resist"), "the report states the resistance the artifact grants")
end

function tests.examineItemShowsAPotionsDisguisedLabelWithoutLeakingItsIdentity()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local potion = Items.potionOf("poison")
  local description = Examine.item(game.identify, potion)
  ok(not contains(description, "potion of poison"), "an unidentified potion's true name stays hidden")
  ok(contains(description, "worth 6 gold"), "the report still prices the item off its real, hidden effect")
end

function tests.examineMonsterReportsHpAttackDefenseAndDefaultsToHuntingAwareness()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 5, 1)
  local description = Examine.monster(game.player, rat)
  ok(contains(description, rat.name), "the report names the monster")
  ok(contains(description, string.format("hp %d/%d", rat.hp, rat.maxHp)), "the report states current and max hp")
  ok(contains(description, "hunting you"), "a hand-built monster with no awareness field defaults to hunting")
end

function tests.examineMonsterReportsDormantAwarenessForAnUnwokenWildMonster()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 5, 1)
  rat.awareness = Stealth.DORMANT
  ok(contains(Examine.monster(game.player, rat), "asleep"), "a dormant monster reports as asleep")
end

function tests.examineMonsterReportsItsFactionAndTheCurrentReputationTier()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local kobold = Monsters.create(Monsters.byKey.kobold, 1, 8, 5, 1)
  Factions.adjust(game.player, Factions.GOBLINOID, 30)
  ok(contains(Examine.monster(game.player, kobold), "faction: goblinoid (friendly)"),
    "the report states the faction and its current reputation tier")
end

function tests.examineMonsterListsAnElitesTierAndEachAffixItRolled()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 8, 5, 1)
  orc.elite, orc.eliteTier, orc.eliteAffixes = true, "champion", { "brutal", "swift" }
  ok(contains(Examine.monster(game.player, orc), "champion: brutal, swift"),
    "the report names the elite tier and each affix it rolled")
end

function tests.examineMonsterFlagsAnEnragedAndDesperateBossTogether()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local warlord = Bosses.create(Bosses.byKey.warlord, 1, 8, 5)
  warlord.enraged, warlord.desperate = true, true
  ok(contains(Examine.monster(game.player, warlord), "boss, enraged, desperate"),
    "the report flags both boss phase tags together")
end

function tests.examineMonsterReportsANonNormalResistanceFromItsBaseProfile()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local troll = Monsters.create(Monsters.byKey.troll, 1, 8, 5, 1)
  ok(contains(Examine.monster(game.player, troll), "resistances: fire weak"),
    "the report states the troll's innate fire weakness")
end

function tests.examineMonsterListsActiveStatusEffectsWithRemainingDuration()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 5, 1)
  Status.apply(rat, Status.POISON, 4, 2)
  ok(contains(Examine.monster(game.player, rat), "afflicted: poison (4)"),
    "the report lists the active status and its remaining duration")
end

function tests.examineMonsterNamesSeveralStatusesAsNounsInANaturalList()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 8, 5, 1)
  Status.apply(rat, Status.CONFUSE, 3, 1)
  ok(contains(Examine.monster(game.player, rat), "afflicted: confusion (3)"),
    "a single status is reported by its noun")
  Status.apply(rat, Status.BLIND, 2, 1)
  ok(contains(Examine.monster(game.player, rat), "afflicted: confusion (3) and blindness (2)"),
    "two statuses are joined with and")
  Status.apply(rat, Status.POISON, 4, 2)
  ok(contains(Examine.monster(game.player, rat), "afflicted: confusion (3), blindness (2) and poison (4)"),
    "three statuses read as a, b and c")
end

function tests.examineMonsterReportsADiseaseCaughtThroughInfighting()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 8, 5, 1)
  ok(not contains(Examine.monster(game.player, orc), "diseased"), "a healthy monster's report mentions no disease")
  Disease.infect(orc, Disease.PLAGUE)
  ok(contains(Examine.monster(game.player, orc), "diseased: black plague (incubating)"),
    "an incubating infection shows up in a monster's examine report")
  orc.disease.stage = 1
  ok(contains(Examine.monster(game.player, orc), "diseased: black plague (stage 1)"),
    "an erupted infection reports its current stage in a monster's examine report")
end

return tests
