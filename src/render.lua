-- ASCII presentation of the current level and a status panel. Reads game state
-- only; never mutates. Unexplored cells stay blank, explored-but-unseen cells
-- show terrain, and only cells currently lit reveal actors and loot.

local Status = require("status")
local Identify = require("identify")

local Render = {}

local function cell(game, x, y)
  local level = game.level
  local map = level.map
  local idx = map:index(x, y)
  if not level.explored[idx] then return " " end
  if game.visible[idx] then
    if game.player.x == x and game.player.y == y then return "@" end
    local monster = level:entityAt(x, y)
    if monster then return monster.glyph end
    local here = level:itemsAt(x, y)
    if #here > 0 then return here[1].item.glyph end
  end
  return map:get(x, y)
end

local function statusTags(entity)
  local tags = {}
  for _, active in ipairs(entity.statuses) do
    tags[#tags + 1] = active.kind
  end
  if #tags == 0 then return "none" end
  return table.concat(tags, ",")
end

function Render.panel(game)
  local player = game.player
  local level = game.level
  local weapon = player.weapon and Identify.label(game.identify, player.weapon) or "none"
  local armor = player.armor and Identify.label(game.identify, player.armor) or "none"
  local ring = player.ring and player.ring.name or "none"
  local torch = player.light.fuel > 0 and tostring(player.light.fuel) or "spent"
  local lines = {
    string.format("HP %d/%d  ATK %d  DEF %d  depth %d  turn %d  %s%s",
      player.hp, player.maxHp, player:effectiveAttack(), player:effectiveDefense(),
      game.depth, game.turn, level.generator, level.dark and "  dark" or ""),
    string.format("food %d  torch %s  status %s", player.satiation, torch, statusTags(player)),
    string.format("weapon %s  armor %s  ring %s  items %d  foes %d",
      weapon, armor, ring, #player.inventory, #level.entities),
  }
  local last = game.log:last()
  if last then lines[#lines + 1] = "- " .. last end
  return table.concat(lines, "\n")
end

function Render.frame(game)
  local map = game.level.map
  local rows = {}
  for y = 1, map.height do
    local row = {}
    for x = 1, map.width do
      row[x] = cell(game, x, y)
    end
    rows[#rows + 1] = table.concat(row)
  end
  return table.concat(rows, "\n") .. "\n" .. Render.panel(game)
end

return Render
