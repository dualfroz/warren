local helpers = require("helpers")
local Compendium = require("compendium")
local Leaderboard = require("leaderboard")
local Export = require("export")

local ok, eq, contains = helpers.ok, helpers.eq, helpers.contains

local tests = helpers.suite()

function tests.exportLeaderboardCsvOnAnEmptyBoardIsJustTheHeaderRow()
  local csv = Export.leaderboardCsv(Leaderboard.new())
  eq(csv, table.concat(Export.COLUMNS, ",") .. "\n", "an empty board exports to a single header line")
end

function tests.exportLeaderboardCsvEmitsOneRowPerEntryInRankOrder()
  local board = Leaderboard.new()
  Leaderboard.record(board, { score = 300, className = "fighter", depth = 5, turn = 200, won = true, seed = 11 })
  Leaderboard.record(board, { score = 200, className = "mage", depth = 3, turn = 150, won = false, seed = 22 })
  local csv = Export.leaderboardCsv(board)
  local lines = {}
  for line in csv:gmatch("[^\n]+") do lines[#lines + 1] = line end
  eq(#lines, 3, "the header plus one row per entry gives three lines total")
  eq(lines[1], "rank,score,className,depth,turn,won,seed", "the header names every column in a fixed order")
  eq(lines[2], "1,300,fighter,5,200,true,11", "the top-ranked entry becomes the first data row")
  eq(lines[3], "2,200,mage,3,150,false,22", "the second-ranked entry keeps that same rank order")
end

function tests.exportLeaderboardCsvRendersBooleansAsLowercaseWords()
  local board = Leaderboard.new()
  Leaderboard.record(board, { score = 50, className = "rogue", depth = 1, turn = 10, won = true, seed = 1 })
  ok(contains(Export.leaderboardCsv(board), ",true,"), "a won run's CSV row spells out 'true', not '1' or 'TRUE'")
end

function tests.exportCompendiumCsvListsEverySpeciesSeenOrNot()
  local compendium = Compendium.new()
  Compendium.noteSighting(compendium, "rat")
  Compendium.noteKill(compendium, "rat")
  Compendium.noteKill(compendium, "rat")
  local csv = Export.compendiumCsv(compendium)
  local lines = {}
  for line in csv:gmatch("[^\n]+") do lines[#lines + 1] = line end
  eq(lines[1], "key,name,seen,kills", "the header names every compendium export column")
  eq(#lines, #Compendium.entries(compendium) + 1, "every catalogued species gets a row, sighted or not")
  ok(contains(csv, "rat,rat,true,2"), "a sighted, twice-slain species reports its own seen flag and tally")
  ok(contains(csv, "false,0"), "an undiscovered species still reports as unseen with a zero tally")
end

return tests
