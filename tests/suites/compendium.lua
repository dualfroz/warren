local helpers = require("helpers")
local Monsters = require("monsters")
local Game = require("game")
local Bosses = require("bosses")
local Compendium = require("compendium")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.compendiumNoteSightingReturnsTrueOnlyOnTheFirstSighting()
  local compendium = Compendium.new()
  eq(Compendium.noteSighting(compendium, "rat"), true, "the very first sighting of a species reports true")
  eq(Compendium.noteSighting(compendium, "rat"), false, "a repeat sighting of the same species reports false")
  ok(Compendium.hasSeen(compendium, "rat"), "the species is recorded as seen")
  ok(not Compendium.hasSeen(compendium, "bat"), "an entirely different species is unaffected")
end

function tests.compendiumNoteKillAccumulatesAcrossMultipleKills()
  local compendium = Compendium.new()
  eq(Compendium.killCount(compendium, "goblin"), 0, "a species starts with zero recorded kills")
  Compendium.noteKill(compendium, "goblin")
  Compendium.noteKill(compendium, "goblin")
  Compendium.noteKill(compendium, "goblin")
  eq(Compendium.killCount(compendium, "goblin"), 3, "kills accumulate one at a time")
end

function tests.compendiumEntriesListsEveryWildSpeciesAndEveryBoss()
  local entries = Compendium.entries(Compendium.new())
  eq(#entries, #Monsters.species + #Bosses.catalog, "the compendium lists every wild species and every named boss")
  local byKey = {}
  for _, entry in ipairs(entries) do byKey[entry.key] = entry end
  ok(byKey.orc ~= nil, "a wild species keys its entry by its plain species key")
  ok(byKey.boss_warlord ~= nil, "a boss keys its entry with the same boss_ prefix game.lua stamps onto its entity")
  eq(byKey.orc.seen, false, "a freshly created compendium has not seen anything yet")
  ok(byKey.orc.flavor ~= nil, "every catalogued species carries a flavor line")
end

function tests.gameRecordsASightingTheFirstTimeAMonsterBecomesVisible()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  game.level.entities = { orc }
  game:computeVisible()
  ok(Compendium.hasSeen(game.compendium, "orc"),
    "a monster within sight is recorded into the compendium the moment it is seen")

  local rat = Monsters.create(Monsters.byKey.rat, 2, 19, 10, 1)
  game.level.entities = { rat }
  game:computeVisible()
  ok(not Compendium.hasSeen(game.compendium, "rat"),
    "a species standing far outside sight range is never recorded just because it exists on the level")
end

function tests.gameRecordsAKillIntoItsCompendiumOnAwardKill()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  game.level.entities = { orc }
  eq(Compendium.killCount(game.compendium, "orc"), 0, "no kills recorded before the fight starts")
  game:awardKill(orc)
  eq(Compendium.killCount(game.compendium, "orc"), 1, "felling a monster records exactly one kill for its species")
  game:awardKill(Monsters.create(Monsters.byKey.orc, 3, 4, 6, 1))
  eq(Compendium.killCount(game.compendium, "orc"), 2, "kill counts accumulate across separate kills of the same species")
end

function tests.compendiumFieldsSurviveAGameSaveLoadRoundTrip()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  game.level.entities = { orc }
  game:computeVisible()
  game:awardKill(orc)
  local restored = Game.fromData(game:toData())
  eq(Compendium.killCount(restored.compendium, "orc"), 1, "a recorded kill survives a save/load round trip")
  ok(Compendium.hasSeen(restored.compendium, "orc"), "a recorded sighting survives a save/load round trip too")
end

return tests
