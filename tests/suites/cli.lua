local helpers = require("helpers")

local ok, eq, contains = helpers.ok, helpers.eq, helpers.contains
local scriptDir = helpers.testsDir

local warrenEntry = scriptDir .. "/../warren.lua"
local luaExe = arg[-1] or "lua"

local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function runWarrenCli(argv, stdinText)
  local parts = { shellQuote(luaExe), shellQuote(warrenEntry) }
  for _, a in ipairs(argv) do parts[#parts + 1] = shellQuote(a) end
  local inPath
  if stdinText then
    inPath = os.tmpname()
    local input = io.open(inPath, "w")
    input:write(stdinText)
    input:close()
    parts[#parts + 1] = "<"
    parts[#parts + 1] = shellQuote(inPath)
  end
  parts[#parts + 1] = "2>&1"
  local proc = io.popen(table.concat(parts, " "), "r")
  local output = proc:read("a")
  local success, exitType, code = proc:close()
  if inPath then os.remove(inPath) end
  local exitCode = success and 0 or (exitType == "exit" and code or -1)
  return output, exitCode
end

local tests = helpers.suite()

function tests.cliHeadlessAutoRunPrintsTheStatusBarAndExitsZero()
  local output, code = runWarrenCli({ "--seed", "42", "--auto", "20" })
  eq(code, 0, "a plain headless auto-run exits zero")
  ok(contains(output, "HP "), "the status bar's HP field reaches real stdout")
  ok(contains(output, "depth "), "the status bar's depth field reaches real stdout")
  ok(not contains(output, "traceback"), "a routine auto-run never prints a Lua traceback")
end

function tests.cliPlayReplDrivesRealCommandsThroughRealStdin()
  local script = "status\nlook\nlearn cleave\nlearn cleave\nforge fire\nhelp\nquit\n"
  local output, code = runWarrenCli({ "--seed", "5", "--class", "fighter", "--play" }, script)
  eq(code, 0, "a scripted --play session exits zero")
  ok(contains(output, "you learn cleave"), "learn is wired through the real stdin loop")
  ok(contains(output, "you already know that"), "a repeated learn is rejected through the real stdin loop")
  ok(contains(output, "you see no threats nearby"), "look reaches the real command dispatcher")
  ok(contains(output, "cannot forge: not enough essence"),
    "forge's failure message reaches real stdout with a fresh fighter's zero essence")
  ok(contains(output, "commands: north/south/east/west"), "help lists the command vocabulary over real stdout")
end

function tests.cliPlayLoopChargesATurnOnlyForCommandsThatActuallySucceed()
  local script = "wait\nasdf\nstatus\nquit\n"
  local output, code = runWarrenCli({ "--seed", "1", "--auto", "0", "--play" }, script)
  eq(code, 0, "a mixed valid/invalid --play script still exits zero")
  ok(contains(output, "unknown command: asdf"), "an unrecognized verb is reported over real stdout")
  ok(contains(output, "turn 1"), "one successful wait (and one rejected typo) leaves the turn counter at exactly 1")
  ok(not contains(output, "turn 2"), "the rejected typo never advances the turn counter a second time")
end

function tests.cliSaveThenLoadRoundTripsThroughTheRealEntryPoint()
  local savePath = os.tmpname()
  local saveOut, saveCode = runWarrenCli({ "--seed", "9", "--auto", "15", "--save", savePath })
  eq(saveCode, 0, "--save exits zero")
  ok(contains(saveOut, "saved to"), "--save reports where it wrote the file")
  local saved = io.open(savePath, "r")
  ok(saved ~= nil, "the save file actually exists on disk after --save")
  if saved then
    ok(#saved:read("a") > 0, "the save file is not empty")
    saved:close()
  end
  local loadOut, loadCode = runWarrenCli({ "--load", savePath, "--auto", "0" })
  os.remove(savePath)
  eq(loadCode, 0, "--load exits zero")
  ok(contains(loadOut, "turn 15"), "the loaded run resumes at exactly the turn it was saved on")
end

function tests.cliVerifyConfirmsADeterministicReplayThroughTheRealEntryPoint()
  local output, code = runWarrenCli({ "--seed", "7", "--auto", "30", "--verify" })
  eq(code, 0, "--verify exits zero")
  ok(contains(output, "replay verified: seed 7 reproduces this run"),
    "a meta-free run reports a verified replay over real stdout")
end

function tests.cliChallengePresetPrintsAChallengeLineAndAVerdict()
  local output, code = runWarrenCli({ "--challenge", "3", "--auto", "40" })
  eq(code, 0, "--challenge exits zero")
  ok(contains(output, "challenge:"), "the challenge preset announces itself over real stdout")
  ok(contains(output, "challenge honored") or contains(output, "challenge broken"),
    "the challenge preset reaches a pass/fail verdict by the end of the run")
end

function tests.cliReportShowsFreshProgressionStateForANewMetaFile()
  local metaPath = os.tmpname()
  os.remove(metaPath)
  local output, code = runWarrenCli({ "--meta", metaPath, "--report" })
  os.remove(metaPath)
  eq(code, 0, "--report against a brand-new --meta file exits zero")
  ok(contains(output, "renown 0"), "a fresh meta file reports zero renown")
  ok(contains(output, "streak:"), "the report includes the streak line")
  ok(contains(output, "compendium:"), "the report includes the compendium section")
  ok(contains(output, "leaderboard:"), "the report includes the leaderboard section")
  ok(contains(output, "perk vigor"), "the report lists purchasable perks")
end

function tests.cliExportsRealLeaderboardAndCompendiumCsvFiles()
  local metaPath = os.tmpname()
  os.remove(metaPath)
  local csvPath = os.tmpname()
  local bestiaryPath = os.tmpname()
  local output, code = runWarrenCli({
    "--meta", metaPath, "--seed", "5", "--auto", "30",
    "--export-csv", csvPath, "--export-compendium", bestiaryPath,
  })
  eq(code, 0, "a run with both export flags exits zero")
  ok(contains(output, "leaderboard exported to"), "the CLI reports the leaderboard export path")
  ok(contains(output, "compendium exported to"), "the CLI reports the compendium export path")
  local csv = io.open(csvPath, "r")
  ok(csv ~= nil, "the leaderboard CSV file exists on disk")
  if csv then
    local header = csv:read("l")
    eq(header, "rank,score,className,depth,turn,won,seed", "the leaderboard CSV has the expected header row")
    csv:close()
  end
  local bestiary = io.open(bestiaryPath, "r")
  ok(bestiary ~= nil, "the compendium CSV file exists on disk")
  if bestiary then
    ok(#bestiary:read("a") > 0, "the compendium CSV is not empty")
    bestiary:close()
  end
  os.remove(metaPath)
  os.remove(csvPath)
  os.remove(bestiaryPath)
end

function tests.cliLoadingAMissingSaveFileFailsLoudlyRatherThanSilently()
  local output, code = runWarrenCli({ "--load", "/tmp/warren-tests-nonexistent-save-xyz.sav" })
  eq(code, 1, "loading a save file that does not exist exits nonzero")
  ok(contains(output, "cannot load save"), "the failure names the save-loading step, not a generic crash")
  ok(contains(output, "missing"), "the failure explains that the file itself is what is missing")
end

function tests.cliPlayReplExploreAdvancesSeveralTurnsInASingleTypedCommand()
  local script = "status\nexplore\nstatus\nquit\n"
  local output, code = runWarrenCli({ "--seed", "5", "--class", "fighter", "--play" }, script)
  eq(code, 0, "a scripted explore through --play exits zero")
  ok(not contains(output, "traceback"), "explore over real stdin never crashes")
  local turns = {}
  for turn in output:gmatch("turn (%d+)") do turns[#turns + 1] = tonumber(turn) end
  ok(#turns >= 2, "the turn counter appears in the transcript")
  ok(turns[#turns] > turns[1], "explore actually advances the turn counter through the real entry point")
end

function tests.cliPlayReplRestRefusesWithoutSpendingATurnAtFullHealth()
  local script = "status\nrest\nstatus\nquit\n"
  local output, code = runWarrenCli({ "--seed", "5", "--class", "fighter", "--play" }, script)
  eq(code, 0, "a scripted rest through --play exits zero")
  ok(not contains(output, "traceback"), "rest over real stdin never crashes")
  ok(contains(output, "you are already at full health"), "the real entry point surfaces the refusal verbatim")
  ok(not contains(output, "turn 1"), "the refused rest never advances the turn counter past the opening render")
end

function tests.cliPlayReplTravelDownAdvancesSeveralTurnsInASingleTypedCommand()
  local script = "status\ntravel down\nstatus\nquit\n"
  local output, code = runWarrenCli({ "--seed", "1", "--class", "fighter", "--play" }, script)
  eq(code, 0, "a scripted travel through --play exits zero")
  ok(not contains(output, "traceback"), "travel over real stdin never crashes")
  ok(contains(output, "you stop traveling - a monster is in sight"),
    "the real entry point surfaces Game:travelTo's own interrupt verbatim")
  local turns = {}
  for turn in output:gmatch("turn (%d+)") do turns[#turns + 1] = tonumber(turn) end
  ok(#turns >= 2, "the turn counter appears in the transcript")
  ok(turns[#turns] > turns[1], "travel actually advances the turn counter through the real entry point")
end

return tests
