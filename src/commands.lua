-- Text command parser and dispatcher for a human player, layered entirely on
-- top of the granular Game:<action> methods choosePlayerAction (ai.lua's own
-- autopilot) already drives - nothing here duplicates combat, targeting or
-- turn bookkeeping, it only translates a typed word into the same call the
-- autopilot would have made. Every other player-facing system in this engine
-- is a mechanic; this is the one module whose whole job is the interface
-- between a line of text and those mechanics, which is why it takes `game`
-- as a plain argument rather than requiring game.lua itself (that require
-- runs the other way, from game.lua's Game:manualStep).
--
-- Commands.apply(game, text) always returns (consumesTurn, message): a
-- movement/action word that actually did something returns true and leaves
-- Game:manualStep to spend the turn, exactly like choosePlayerAction would
-- have; an unrecognized word, a bad argument, or an action with nothing to
-- act on returns false and spends nothing, so a typo never costs a turn the
-- way a wasted keystroke would in any other roguelike. Purely informational
-- commands (inventory, look, status, help) always return false for the same
-- reason - reading your own inventory is free.

local Spells = require("spells")
local Identify = require("identify")
local Factions = require("factions")
local Examine = require("examine")
local Skills = require("skills")

local Commands = {}

local DIRS = {
  north = { 0, -1 }, n = { 0, -1 },
  south = { 0, 1 }, s = { 0, 1 },
  east = { 1, 0 }, e = { 1, 0 },
  west = { -1, 0 }, w = { -1, 0 },
  northeast = { 1, -1 }, ne = { 1, -1 },
  northwest = { -1, -1 }, nw = { -1, -1 },
  southeast = { 1, 1 }, se = { 1, 1 },
  southwest = { -1, 1 }, sw = { -1, 1 },
}

-- Splits `text` on whitespace into a lowercase verb plus its remaining
-- tokens as args. Returns nil for anything with no verb at all (an empty or
-- all-whitespace line), which Commands.apply treats the same as an unknown
-- command - no turn spent either way.
function Commands.parse(text)
  if type(text) ~= "string" then return nil end
  local tokens = {}
  for token in text:gmatch("%S+") do
    tokens[#tokens + 1] = token:lower()
  end
  if #tokens == 0 then return nil end
  local args = {}
  for i = 2, #tokens do args[#args + 1] = tokens[i] end
  return { verb = tokens[1], args = args }
end

-- A monster the player can actually see right now: alive, kind "monster"
-- (excludes the player's own companions/hirelings/thralls, which never
-- carry that kind - see game.lua's isPlayerAlly), and standing on a tile
-- game.visible already marks lit for the player this turn.
local function isVisibleHostile(game, entity)
  return entity.kind == "monster" and entity:isAlive()
    and game.visible[game.level.map:index(entity.x, entity.y)] == true
end

-- Up to `count` nearest visible hostiles, Chebyshev distance, ties broken by
-- ascending id - the same tie rule Game:nearestAlly and companions.lua's own
-- nearestHostile already use, so auto-targeting a ranged command picks
-- exactly the monster the autopilot would have picked in the same spot.
local function nearestHostiles(game, count)
  local player = game.player
  local results, excluded = {}, {}
  for _ = 1, count do
    local best, bestDist
    for _, entity in ipairs(game.level.entities) do
      if not excluded[entity] and isVisibleHostile(game, entity) then
        local dist = math.max(math.abs(entity.x - player.x), math.abs(entity.y - player.y))
        if not best or dist < bestDist or (dist == bestDist and entity.id < best.id) then
          best, bestDist = entity, dist
        end
      end
    end
    if not best then break end
    results[#results + 1] = best
    excluded[best] = true
  end
  return results
end

local function nearestHostile(game)
  return nearestHostiles(game, 1)[1]
end

-- Every visible hostile in game.level.entities's own order, unlike
-- nearestHostiles above which sorts by distance - this is the order
-- Handlers.look numbers its list in, so "examine monster <n>" always means
-- the same monster the player just saw look print at that number.
local function visibleHostilesInOrder(game)
  local list = {}
  for _, entity in ipairs(game.level.entities) do
    if isVisibleHostile(game, entity) then list[#list + 1] = entity end
  end
  return list
end

-- Resolves an optional trailing target number - the exact 1-based index
-- Handlers.look/examine already print next to each visible hostile - to an
-- entity, falling back to the nearest visible hostile (the old, only
-- behaviour) when the caller omitted it. Every targeted handler below stays
-- correct for a player who never bothers naming a target, while letting a
-- player who cares (a dangerous archer standing behind an expendable rat)
-- reach past the default without any change to game.lua's own range/line-of-
-- sight checks, which still reject an out-of-reach explicit target exactly
-- like they already reject a too-far auto-picked one.
-- Returns (target, explicit): explicit is true only when the caller actually
-- passed a token for the slot, so callers can tell "you named a target that
-- is not there" apart from "there is no target in sight at all" and keep
-- their own existing wording for the latter.
local function resolveTarget(game, indexText)
  if indexText == nil then return nearestHostile(game), false end
  local index = tonumber(indexText)
  return index and visibleHostilesInOrder(game)[index], true
end

-- Commands.parse lowercases every token before a handler ever sees it, which
-- is harmless for directions/spells/factions/slots (already all-lowercase
-- keys) but not for Skills.active/Skills.passive, whose keys are camelCase
-- (secondWind, poisonBlade, manaShield) - a player typing the skill's own
-- name would otherwise never match it. Maps a lowercased word back to its
-- real key by case-insensitive scan; returns the word unchanged when nothing
-- matches, so an actually unknown skill still reaches Skills.use/Skills.learn
-- and gets their own "no such skill" wording instead of being swallowed here.
local function resolveSkillKey(word)
  if not word then return word end
  for key in pairs(Skills.active) do
    if key:lower() == word then return key end
  end
  for key in pairs(Skills.passive) do
    if key:lower() == word then return key end
  end
  return word
end

local Handlers = {}

local function moveHandler(dx, dy)
  return function(game)
    if game:movePlayer(dx, dy) then return true, nil end
    return false, "you cannot go that way"
  end
end

for name, dir in pairs(DIRS) do
  Handlers[name] = moveHandler(dir[1], dir[2])
end

Handlers.attack = function(game, args)
  local dir = DIRS[args[1]]
  if not dir then return false, "attack which direction?" end
  if game:movePlayer(dir[1], dir[2]) then return true, nil end
  return false, "there is nothing to attack there"
end

