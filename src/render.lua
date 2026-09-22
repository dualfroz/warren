local Status = require("status")
local Identify = require("identify")
local Hazards = require("hazards")
local Encumbrance = require("encumbrance")
local Stealth = require("stealth")
local Nodes = require("nodes")
local Sets = require("sets")
local Curses = require("curses")
local Momentum = require("momentum")
local Conductivity = require("conductivity")
local Sanity = require("sanity")
local Events = require("events")
local Proficiency = require("proficiency")
local Durability = require("durability")
local Hunger = require("hunger")
local Disease = require("disease")

local Render = {}

Render.glyphs = {
  player = "@",
  fire = "`",
  gas = ",",
  shrine = "_",
  block = "0",
  plate = ";",
  cauldron = "U",
  board = "N",
  claimedBoard = "E",
  corpse = "X",
  chest = "B",
  emptiedChest = "u",
  rift = "A",
}

local glyphs = Render.glyphs

local hazardGlyphs = { [Hazards.FIRE] = glyphs.fire, [Hazards.GAS] = glyphs.gas }

local function cell(game, x, y)
  local level = game.level
  local map = level.map
  local idx = map:index(x, y)
  if not level.explored[idx] then return " " end
  if game.visible[idx] then
    if game.player.x == x and game.player.y == y then return glyphs.player end
    local monster = level:entityAt(x, y)
    if monster then return monster.glyph end
    local hazard = Hazards.at(level, x, y)
    if hazard then return hazardGlyphs[hazard.kind] end
    if level:shrineAt(x, y) then return glyphs.shrine end
    if level:blockAt(x, y) then return glyphs.block end
    if level:plateAt(x, y) then return glyphs.plate end
    if level:cauldronAt(x, y) then return glyphs.cauldron end
    local node = level:nodeAt(x, y)
    if node then return Nodes.glyph(node) end
    local board = level:questBoardAt(x, y)
    if board then return board.claimed and glyphs.claimedBoard or glyphs.board end
    if level:corpseAt(x, y) then return glyphs.corpse end
    local chest = level:chestAt(x, y)
    if chest then return chest.opened and glyphs.emptiedChest or glyphs.chest end
    if level:riftAt(x, y) then return glyphs.rift end
    local here = level:itemsAt(x, y)
    if #here > 0 then return here[1].item.glyph end
  end
  return map:get(x, y)
end

local function statusTags(entity)
  local tags = {}
  for _, active in ipairs(entity.statuses) do
    tags[#tags + 1] = Status.noun(active.kind)
  end
  if Disease.isInfected(entity) then
    local infection = entity.disease
    local name = Disease.defs[infection.key].name
    tags[#tags + 1] = Disease.hasErupted(entity)
      and string.format("%s(stage %d)", name, infection.stage)
      or string.format("%s(incubating)", name)
  end
  if #tags == 0 then return { "none" } end
  return tags
end

local panelWidth = 80

local function wrapList(label, parts, separator)
  local indent = string.rep(" ", #label)
  local trail = separator:match("^(.-)%s*$")
  local lines, line = {}, label .. (parts[1] or "")
  for i = 2, #parts do
    local joined = line .. separator .. parts[i]
    local reserve = i < #parts and #trail or 0
    if #joined + reserve <= panelWidth then
      line = joined
    else
      lines[#lines + 1] = line .. trail
      line = indent .. parts[i]
    end
  end
  lines[#lines + 1] = line
  return lines
end

local function appendAll(lines, extra)
  for _, line in ipairs(extra) do lines[#lines + 1] = line end
end

local function words(text)
  local found = {}
  for word in text:gmatch("%S+") do found[#found + 1] = word end
  return found
end

local function dormantCount(level)
  local count = 0
  for _, entity in ipairs(level.entities) do
    if entity.kind == "monster" and entity:isAlive() and Stealth.isUnaware(entity) then
      count = count + 1
    end
  end
  return count
end

local function gearLabel(item, label)
  if Durability.missing(item) == 0 then return label end
  if Durability.isBroken(item) then return label .. " (broken)" end
  return string.format("%s (%d/%d)", label, item.durability, item.maxDurability)
end

function Render.panel(game)
  local player = game.player
  local level = game.level
  local weapon = player.weapon
    and gearLabel(player.weapon, Curses.label(player.weapon, Identify.label(game.identify, player.weapon))) or "none"
  local armor = player.armor
    and gearLabel(player.armor, Curses.label(player.armor, Identify.label(game.identify, player.armor))) or "none"
  local ring = player.ring and Curses.label(player.ring, player.ring.name) or "none"
  local bow = player.bow and gearLabel(player.bow, Curses.label(player.bow, player.bow.name)) or "none"
  local torch = player.light.fuel > 0 and tostring(player.light.fuel) or "spent"
  local asleep = dormantCount(level)
  local foes = asleep > 0 and string.format("%d (%d asleep)", #level.entities, asleep)
    or tostring(#level.entities)
  local floorFields = { "depth " .. game.depth, "turn " .. game.turn, "foes " .. foes, level.generator }
  if level.dark then floorFields[#floorFields + 1] = "dark" end
  if level.weather then floorFields[#floorFields + 1] = level.weather end
  if game.won then floorFields[#floorFields + 1] = "WON" end
  local lines = {}
  appendAll(lines, wrapList("", {
    string.format("HP %d/%d", player.hp, player.maxHp),
    "ATK " .. player:effectiveAttack(),
    "DEF " .. player:effectiveDefense(),
    "lvl " .. player.level,
    string.format("xp %d/%d", player.xp, player.xpNext),
    string.format("mana %d/%d", player.mana, player.maxMana),
  }, "  "))
  appendAll(lines, wrapList("", floorFields, "  "))
  appendAll(lines, wrapList("", {
    "food " .. player.satiation,
    "torch " .. torch,
    "gold " .. player.gold,
    string.format("load %s (%d/%d)",
      player:encumbranceTier(), Encumbrance.carriedWeight(player), Encumbrance.capacityFor(player)),
    "items " .. #player.inventory,
  }, "  "))
  appendAll(lines, wrapList("status: ", statusTags(player), ", "))
  appendAll(lines, wrapList("weapon ", words(weapon), " "))
  appendAll(lines, wrapList("", { "armor " .. armor, "ring " .. ring, "bow " .. bow }, "  "))
  local activeSets = Sets.activeDescriptions(player)
  if activeSets then lines[#lines + 1] = "set " .. activeSets end
  local combo = Momentum.stacks(player)
  if combo > 0 then lines[#lines + 1] = string.format("combo x%d", combo) end
  if Conductivity.isWet(player) then lines[#lines + 1] = string.format("wet (%d)", player.wet) end
  local masteryBonus = Proficiency.attackBonus(player)
  if masteryBonus > 0 then
    appendAll(lines, wrapList(string.format("mastery +%d with ", masteryBonus), words(Proficiency.keyFor(player)), " "))
  end
  local sanityTier = Sanity.tierOf(player)
  if sanityTier ~= Sanity.COMPOSED then
    lines[#lines + 1] = string.format("sanity %d/%d (%s)", Sanity.current(player), Sanity.MAX, sanityTier)
  end
  local hungerTier = Hunger.tierOf(player)
  if hungerTier ~= Hunger.FED then
    lines[#lines + 1] = string.format("hunger %d/%d (%s)", Hunger.current(player), Hunger.CAP, hungerTier)
  end
  if level.event then
    lines[#lines + 1] = string.format("event %s (%d turns left)", level.event.key, level.event.turnsLeft)
  end
  if game.ascension and #game.ascension > 0 then
    appendAll(lines, wrapList("ascension ", game.ascension, ","))
  end
  local last = game.log:last()
  if last then appendAll(lines, wrapList("- ", words(last), " ")) end
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
