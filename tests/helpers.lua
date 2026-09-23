local Map = require("map")
local Items = require("items")
local Level = require("level")
local Game = require("game")

local Helpers = { passed = 0, failed = 0, failures = {} }

Helpers.testsDir = arg[0]:match("^(.*)[/\\]") or "."

function Helpers.ok(condition, name)
  if condition then
    Helpers.passed = Helpers.passed + 1
  else
    Helpers.failed = Helpers.failed + 1
    Helpers.failures[#Helpers.failures + 1] = name
  end
end

function Helpers.eq(actual, expected, name)
  Helpers.ok(actual == expected,
    string.format("%s (expected %s, got %s)", name, tostring(expected), tostring(actual)))
end

function Helpers.contains(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

local suiteNames = setmetatable({}, { __mode = "k" })

function Helpers.suite()
  local names = {}
  local tests = setmetatable({}, {
    __newindex = function(tests, name, fn)
      names[#names + 1] = name
      rawset(tests, name, fn)
    end,
  })
  suiteNames[tests] = names
  return tests
end

function Helpers.testNames(tests)
  return suiteNames[tests]
end

local function arena(w, h)
  local map = Map.new(w, h)
  for y = 2, h - 1 do for x = 2, w - 1 do map:set(x, y, Map.FLOOR) end end
  return Level.new({
    depth = 1, generator = "arena", map = map,
    entities = {}, floorItems = {}, traps = {}, lights = {}, dark = false, explored = {},
    upX = 2, upY = 2, downX = w - 1, downY = h - 1,
  })
end

local function stagedGame(seed, level, px, py)
  local game = Game.new(seed)
  game.level = level
  game.player.x, game.player.y = px, py
  game:computeVisible()
  return game
end

local function arenaDark(w, h)
  local map = Map.new(w, h)
  for y = 2, h - 1 do for x = 2, w - 1 do map:set(x, y, Map.FLOOR) end end
  return Level.new({
    depth = 1, generator = "arena", map = map,
    entities = {}, floorItems = {}, traps = {}, lights = {}, dark = true, explored = {},
    upX = 2, upY = 2, downX = w - 1, downY = h - 1,
  })
end

local function padWith(entity, count)
  for _ = 1, count do
    entity.inventory[#entity.inventory + 1] = Items.armor("lockbox", 0)
  end
end

local function wallSplitArena()
  local map = Map.new(21, 11)
  for y = 2, 10 do for x = 2, 20 do map:set(x, y, Map.FLOOR) end end
  for y = 2, 10 do map:set(11, y, Map.WALL) end
  return Level.new({
    depth = 1, generator = "arena", map = map,
    entities = {}, floorItems = {}, traps = {}, lights = {}, dark = false, explored = {},
    upX = 2, upY = 2, downX = 20, downY = 10,
  })
end

local function glyphAt(game, x, y)
  local row = 0
  for line in (game:render() .. "\n"):gmatch("(.-)\n") do
    row = row + 1
    if row == y then return line:sub(x, x) end
  end
end

Helpers.arena = arena
Helpers.stagedGame = stagedGame
Helpers.glyphAt = glyphAt
Helpers.arenaDark = arenaDark
Helpers.padWith = padWith
Helpers.wallSplitArena = wallSplitArena

return Helpers
