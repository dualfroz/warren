local scriptDir = arg[0]:match("^(.*)[/\\]") or "."
package.path = scriptDir .. "/src/?.lua;" .. scriptDir .. "/../src/?.lua;" .. package.path

local Game = require("game")
local Meta = require("meta")
local Compendium = require("compendium")
local Graves = require("graves")
local Ascension = require("ascension")
local Morgue = require("morgue")
local Leaderboard = require("leaderboard")
local Replay = require("replay")
local Challenges = require("challenges")
local Analytics = require("analytics")
local Titles = require("titles")
local Export = require("export")
local Streaks = require("streaks")

local function splitCommaList(text)
  local list = {}
  for part in text:gmatch("[^,]+") do
    list[#list + 1] = part
  end
  return list
end

local function parseArgs(argv)
  local opts = { seed = os.time() & 0xFFFF, auto = 0 }
  local i = 1
  while i <= #argv do
    local flag = argv[i]
    if flag == "--seed" then opts.seed = math.tointeger(tonumber(argv[i + 1])); i = i + 2
    elseif flag == "--auto" then opts.auto = math.tointeger(tonumber(argv[i + 1])); i = i + 2
    elseif flag == "--save" then opts.save = argv[i + 1]; i = i + 2
    elseif flag == "--load" then opts.load = argv[i + 1]; i = i + 2
    elseif flag == "--class" then opts.class = argv[i + 1]; i = i + 2
    elseif flag == "--meta" then opts.metaPath = argv[i + 1]; i = i + 2
    elseif flag == "--buy" then opts.buy = argv[i + 1]; i = i + 2
    elseif flag == "--report" then opts.report = true; i = i + 1
    elseif flag == "--morgue" then opts.morguePath = argv[i + 1]; i = i + 2
    elseif flag == "--verify" then opts.verify = true; i = i + 1
    elseif flag == "--mutators" then opts.mutators = splitCommaList(argv[i + 1]); i = i + 2
    elseif flag == "--challenge" then opts.challengeDay = math.tointeger(tonumber(argv[i + 1])); i = i + 2
    elseif flag == "--export-csv" then opts.exportPath = argv[i + 1]; i = i + 2
    elseif flag == "--export-compendium" then opts.exportCompendiumPath = argv[i + 1]; i = i + 2
    elseif flag == "--play" then opts.play = true; i = i + 1
    else i = i + 1 end
  end
  return opts
end

local function playLoop(game)
  io.write(game:render(), "\n")
  while game.player:isAlive() and not game.won do
    io.write("> ")
    io.flush()
    local line = io.read("l")
    if not line then break end
    local command = line:match("^%s*(.-)%s*$")
    if command == "quit" or command == "exit" or command == "q" then
      break
    elseif command ~= "" then
      local _, message = game:manualStep(command)
      if message then io.write(message, "\n") end
      io.write(game:render(), "\n")
    end
  end
  if game.won then
    io.write("you escape with the Amulet of Warren - you win!\n")
  elseif not game.player:isAlive() then
    io.write("you have died.\n")
  end
end

local function reportMeta(meta)
  local toNext = Titles.toNext(meta.renown)
  local titleLine = toNext and string.format("%s (%d renown to next title)", Titles.forRenown(meta.renown), toNext)
    or string.format("%s (top of the ladder)", Titles.forRenown(meta.renown))
  io.write(string.format("renown %d | runs %d | wins %d | best depth %d | win rate %.0f%% | title %s\n",
    meta.renown, meta.totalRuns, meta.wins, meta.bestDepth, Analytics.winRate(meta) * 100, titleLine))
  local streakLength, streakOutcome = Streaks.current(meta.runHistory)
  io.write(string.format("streak: %d %s in a row | best win streak %d\n",
    streakLength, streakOutcome == nil and "runs" or (streakOutcome and "wins" or "losses"),
    Streaks.bestWinStreak(meta.runHistory)))
  for _, def in ipairs(Meta.PERKS) do
    io.write(string.format("  perk %-12s %s (%d renown)\n",
      def.key, Meta.isOwned(meta, def.key) and "[owned]" or "[locked]", def.cost))
  end
  io.write("challenges:\n")
  for _, preset in ipairs(Challenges.CATALOG) do
    io.write("  " .. Challenges.describe(preset) .. "\n")
  end
  for _, ach in ipairs(Meta.ACHIEVEMENTS) do
    io.write(string.format("  achievement %-14s %s\n",
      ach.key, meta.achievements[ach.key] and "[unlocked]" or "[locked]"))
  end
  for _, def in ipairs(Ascension.MUTATORS) do
    io.write(string.format("  mutator %-12s %s (+%d%% renown) %s\n",
      def.key, def.desc, def.renownBonus, Ascension.isUnlocked(meta, def.key) and "[unlocked]" or "[locked]"))
  end
  io.write("compendium:\n")
  for _, entry in ipairs(Compendium.entries(meta.compendium or Compendium.new())) do
    if entry.seen then
      io.write(string.format("  %-14s slain %-3d %s\n", entry.name, entry.kills, entry.flavor or ""))
    else
      io.write(string.format("  %-14s [undiscovered]\n", entry.key))
    end
  end
  local board = meta.leaderboard or Leaderboard.new()
  io.write("leaderboard:\n")
  for rank, entry in ipairs(Leaderboard.top(board)) do
    io.write(string.format("  #%-2d %-6d %-10s depth %-2d turn %-5d seed %s %s\n",
      rank, entry.score, entry.className, entry.depth, entry.turn, tostring(entry.seed),
      entry.won and "(won)" or ""))
  end
  if #board > 0 then
    io.write(string.format("  average score %.1f | favorite class %s\n",
      Analytics.averageScore(board), Analytics.favoriteClass(board) or "none"))
  end
end

local opts = parseArgs(arg)

local challengePreset
if opts.challengeDay then
  challengePreset, opts.seed = Challenges.forDay(opts.challengeDay)
  opts.class = challengePreset.class
  opts.mutators = challengePreset.mutators
  io.write(string.format("challenge: %s, seed %d\n", Challenges.describe(challengePreset), opts.seed))
end

local meta = opts.metaPath and Meta.load(opts.metaPath) or nil

if meta and opts.buy then
  local success, message = Meta.purchase(meta, opts.buy)
  io.write(message, "\n")
  if not success then os.exit(1) end
end

local game = opts.load and Game.load(opts.load)
  or Game.new(opts.seed, { class = opts.class, meta = meta, graves = meta and meta.graves, mutators = opts.mutators })

for _ = 1, opts.auto do
  if not game.player:isAlive() then break end
  game:autoStep()
end

if opts.play then
  playLoop(game)
else
  io.write(game:render(), "\n")
end

if meta and opts.auto > 0 and (not game.player:isAlive() or game.won) then
  local stats = game:metaStats()
  local gained = Meta.renownFor(stats)
  local unlocked = Meta.recordRun(meta, stats)
  io.write(string.format("run recorded: +%d renown (total %d)\n", gained, meta.renown))
  for _, name in ipairs(unlocked) do
    io.write("achievement unlocked: " .. name .. "\n")
  end
  local report = Morgue.build(game, meta)
  local score = Morgue.score(report)
  local percentile = Analytics.percentile(meta.leaderboard, score)
  local rank = Leaderboard.record(meta.leaderboard, {
    score = score, className = report.className, depth = report.deepestDepth,
    turn = report.turn, won = report.won, seed = game.seed,
  })
  if rank then
    io.write(string.format("leaderboard: rank #%d with score %d (beat %.0f%% of prior runs)\n",
      rank, score, percentile * 100))
  end
end

if meta and opts.auto > 0 and not game.player:isAlive() then
  Graves.record(meta, game:graveEntry())
  io.write(string.format("a grave is left at depth %d\n", game.deepestDepth))
end

if meta then
  Meta.save(meta, opts.metaPath)
end

if opts.exportPath then
  local file = io.open(opts.exportPath, "w")
  file:write(Export.leaderboardCsv(meta and meta.leaderboard or Leaderboard.new()))
  file:close()
  io.write("leaderboard exported to " .. opts.exportPath .. "\n")
end

if opts.exportCompendiumPath then
  local file = io.open(opts.exportCompendiumPath, "w")
  file:write(Export.compendiumCsv(meta and meta.compendium or Compendium.new()))
  file:close()
  io.write("compendium exported to " .. opts.exportCompendiumPath .. "\n")
end

if opts.report then
  reportMeta(meta or Meta.new())
end

if opts.verify and not opts.load then
  if meta then
    io.write("replay skipped: verification only covers meta-free runs (see replay.lua)\n")
  else
    local report = Morgue.build(game)
    local matches, mismatchField, score =
      Replay.verify(opts.seed, { class = opts.class, mutators = opts.mutators }, opts.auto, report)
    if matches then
      io.write(string.format("replay verified: seed %d reproduces this run (score %d)\n", opts.seed, score))
    else
      io.write(string.format("replay mismatch at '%s': seed %d replayed to a different outcome (score %d)\n",
        mismatchField, opts.seed, score))
    end
  end
end

if opts.save then
  game:save(opts.save)
  io.write("saved to " .. opts.save .. "\n")
end

if opts.morguePath and (game.won or not game.player:isAlive()) then
  local report = Morgue.build(game, meta)
  local file = io.open(opts.morguePath, "w")
  file:write(Morgue.format(report))
  file:close()
  io.write(string.format("morgue written to %s (score %d)\n", opts.morguePath, Morgue.score(report)))
end

if challengePreset and opts.auto > 0 then
  local satisfied, reason = Challenges.satisfiedBy(challengePreset, game)
  if satisfied then
    io.write("challenge honored: every requirement was active for this run\n")
  else
    io.write("challenge broken: " .. reason .. "\n")
  end
end
