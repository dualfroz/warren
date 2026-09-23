local helpers = require("helpers")
local Items = require("items")
local Game = require("game")
local Meta = require("meta")
local Compendium = require("compendium")
local Curses = require("curses")
local Morgue = require("morgue")

local ok, eq, contains = helpers.ok, helpers.eq, helpers.contains

local tests = helpers.suite()

function tests.morgueScoreWeighsEveryStatByItsOwnFixedWeight()
  local w = Morgue.SCORE_WEIGHTS
  local report = {
    deepestDepth = 4, kills = 12, bossKills = 1, questsCompleted = 2, artifactsFound = 1,
    vaultsOpened = 1, setPiecesFound = 3, chestsOpened = 5, playerLevel = 6, gold = 40, won = false,
  }
  local expected = 4 * w.depth + 12 * w.kill + 1 * w.bossKill + 2 * w.quest + 1 * w.artifact
    + 1 * w.vault + 3 * w.setPiece + 5 * w.chest + 6 * w.playerLevel + 40
  eq(Morgue.score(report), expected, "score sums every weighted stat plus flat gold")
end

function tests.morgueScoreAddsTheWinBonusOnlyWhenWon()
  local base = {
    deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0,
    vaultsOpened = 0, setPiecesFound = 0, chestsOpened = 0, playerLevel = 1, gold = 0, won = false,
  }
  local lost = Morgue.score(base)
  base.won = true
  local won = Morgue.score(base)
  eq(won - lost, Morgue.SCORE_WEIGHTS.win, "winning adds exactly the win bonus and nothing else")
end

function tests.morgueEquipmentListsOnlyOccupiedSlotsInFixedOrder()
  local game = Game.new(9)
  eq(#Morgue.equipment(game.player), 0, "a fresh player with nothing worn has no equipment lines")
  game.player.armor = Items.armor("plate", 4)
  game.player.weapon = Items.weapon("sword", 3)
  local lines = Morgue.equipment(game.player)
  eq(#lines, 2, "only the two worn slots produce a line")
  eq(lines[1], "weapon: sword", "weapon is listed before armor regardless of assignment order")
  eq(lines[2], "armor: plate", "armor keeps its own slot label")
end

function tests.morgueEquipmentPrefixesARevealedCurseButNotAHiddenOne()
  local game = Game.new(9)
  local ring = Items.ring("ring of woe", 0, 0)
  Curses.afflict(ring, Curses.pool.ring[1])
  game.player.ring = ring
  eq(Morgue.equipment(game.player)[1], "ring: ring of woe", "an unrevealed curse reads like an ordinary item")
  Curses.reveal(ring)
  eq(Morgue.equipment(game.player)[1], "ring: cursed ring of woe", "a revealed curse is prefixed")
end

function tests.morgueKillTallySortsByCountThenByCatalogOrderOnTies()
  local compendium = Compendium.new()
  Compendium.noteKill(compendium, "goblin")
  Compendium.noteKill(compendium, "rat")
  Compendium.noteKill(compendium, "rat")
  Compendium.noteKill(compendium, "bat")
  local rows = Morgue.killTally(compendium)
  eq(#rows, 3, "only species with at least one kill appear")
  eq(rows[1].key, "rat", "the heaviest kill count sorts first")
  eq(rows[1].kills, 2, "rat's tally is exactly two")
  eq(rows[2].key, "bat", "a tie between bat and goblin breaks toward bat's earlier catalog slot")
  eq(rows[3].key, "goblin", "goblin follows bat on the same tied count")
end

function tests.morgueBuildMirrorsGameStatsPlayerAndCompendium()
  local game = Game.new(21)
  game.stats.kills = 3
  game.stats.bossKills = 1
  game.deepestDepth = 5
  game.turn = 120
  game.player.gold = 77
  Compendium.noteKill(game.compendium, "orc")
  local report = Morgue.build(game)
  eq(report.kills, 3, "build copies the live kill tally")
  eq(report.bossKills, 1, "build copies the live boss kill tally")
  eq(report.deepestDepth, 5, "build copies the deepest depth reached")
  eq(report.turn, 120, "build copies the current turn")
  eq(report.gold, 77, "build copies the player's gold")
  eq(report.alive, true, "a living player's report says so")
  eq(#report.killTally, 1, "the compendium's own kill feeds straight into the tally")
  eq(report.killTally[1].key, "orc", "the tallied species matches what was actually killed")
end

function tests.morgueFormatRendersOutcomeGearKillsAndScoreInOrder()
  local game = Game.new(3)
  game.player.weapon = Items.weapon("axe", 2)
  Compendium.noteKill(game.compendium, "kobold")
  game.player.hp = 0
  local text = Morgue.format(Morgue.build(game))
  ok(contains(text, "died in the dark"), "a dead player's obituary names the outcome")
  ok(contains(text, "weapon: axe"), "the report lists the worn weapon")
  ok(contains(text, "kobold"), "the report lists a slain species")
  local scoreLine = "score: " .. Morgue.score(Morgue.build(game))
  ok(contains(text, scoreLine), "the report ends with the matching numeric score")
  local scorePos = text:find("score:", 1, true)
  local killsPos = text:find("kills:", 1, true)
  ok(killsPos < scorePos, "the kill tally is printed before the score line")
end

function tests.morgueFormatNamesTheWinOutcomeWhenWon()
  local game = Game.new(3)
  game.won = true
  local text = Morgue.format(Morgue.build(game))
  ok(contains(text, "Victorious the wanderer"), "a won run's heading calls the player victorious")
  ok(contains(text, "escaped the warren with the Amulet"), "a won run's outcome line names the escape")
end

function tests.morgueFormatOmitsEquipmentAndKillsSectionsWhenEmpty()
  local game = Game.new(3)
  local text = Morgue.format(Morgue.build(game))
  ok(not contains(text, "equipment:"), "an unarmed player's report has no equipment section")
  ok(not contains(text, "kills:"), "a report with no recorded kills has no kill section")
  ok(contains(text, "still drawing breath"), "a living player's report says so")
end

function tests.morgueBuildOmitsTitleWithoutMetaAndIncludesItWithMeta()
  local game = Game.new(3)
  local bare = Morgue.build(game)
  eq(bare.title, nil, "a meta-free build carries no title")
  local meta = Meta.new()
  meta.renown = 60
  local withMeta = Morgue.build(game, meta)
  eq(withMeta.title, "Delver", "a build given meta carries the title that renown actually earns")
  local text = Morgue.format(withMeta)
  ok(contains(text, "the Delver"), "the formatted report names the earned title in its heading")
  ok(not contains(Morgue.format(bare), "the Delver"), "a title-less report never mentions any title")
end

return tests
