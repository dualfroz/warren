-- ASCII presentation of the current level and a status panel. Reads game state
-- only; never mutates. Unexplored cells stay blank, explored-but-unseen cells
-- show terrain, and only cells currently lit reveal actors and loot.

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

local hazardGlyphs = { [Hazards.FIRE] = "`", [Hazards.GAS] = "," }

local function cell(game, x, y)
  local level = game.level
  local map = level.map
  local idx = map:index(x, y)
  if not level.explored[idx] then return " " end
  if game.visible[idx] then
    if game.player.x == x and game.player.y == y then return "@" end
    local monster = level:entityAt(x, y)
    if monster then return monster.glyph end
    local hazard = Hazards.at(level, x, y)
    if hazard then return hazardGlyphs[hazard.kind] end
    if level:shrineAt(x, y) then return "_" end
    if level:blockAt(x, y) then return "0" end
    if level:plateAt(x, y) then return ";" end
    if level:cauldronAt(x, y) then return "U" end
    local node = level:nodeAt(x, y)
    if node then return Nodes.glyph(node) end
    local board = level:questBoardAt(x, y)
    if board then return board.claimed and "=" or "&" end
    if level:corpseAt(x, y) then return "%" end
    local chest = level:chestAt(x, y)
    if chest then return chest.opened and "b" or "B" end
    if level:riftAt(x, y) then return "Q" end
    local here = level:itemsAt(x, y)
    if #here > 0 then return here[1].item.glyph end
  end
  return map:get(x, y)
end

-- Disease was previously invisible outside the transient log lines
-- Disease.tick emits (the eruption, a damage tick, an escalation) - once
-- one of those scrolled off, a player mid-incubation or mid-plague had no
-- persistent way to check their own affliction at all. Folded into the same
-- comma-joined tag line as the timed statuses above, since both are
-- "what's currently afflicting this entity" facts the HUD already exists to
-- surface.
local function statusTags(entity)
  local tags = {}
  for _, active in ipairs(entity.statuses) do
    tags[#tags + 1] = active.kind
  end
  if Disease.isInfected(entity) then
    local infection = entity.disease
    local name = Disease.defs[infection.key].name
    tags[#tags + 1] = Disease.hasErupted(entity)
      and string.format("%s(stage %d)", name, infection.stage)
      or string.format("%s(incubating)", name)
  end
  if #tags == 0 then return "none" end
  return table.concat(tags, ",")
end

-- How many of the level's living monsters are still asleep, out of the total
-- - purely informational, so autopilot and other callers never read it.
local function dormantCount(level)
  local count = 0
  for _, entity in ipairs(level.entities) do
    if entity.kind == "monster" and entity:isAlive() and Stealth.isUnaware(entity) then
      count = count + 1
    end
  end
  return count
end

-- Appends a wear indicator to `label` only once `item` has actually taken
-- damage - broken outright, or merely dinged - leaving a pristine piece's
-- label exactly as clean as before this module existed.
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
  local lines = {
    string.format("HP %d/%d  ATK %d  DEF %d  lvl %d  depth %d  turn %d  %s%s%s%s",
      player.hp, player.maxHp, player:effectiveAttack(), player:effectiveDefense(),
      player.level, game.depth, game.turn, level.generator, level.dark and "  dark" or "",
      level.weather and ("  " .. level.weather) or "", game.won and "  WON" or ""),
    string.format("xp %d/%d  mana %d/%d  food %d  torch %s  gold %d  status %s",
      player.xp, player.xpNext, player.mana, player.maxMana, player.satiation, torch, player.gold, statusTags(player)),
    string.format("load %s (%d/%d)",
      player:encumbranceTier(), Encumbrance.carriedWeight(player), Encumbrance.capacityFor(player)),
    string.format("weapon %s  armor %s  ring %s  bow %s  items %d  foes %s",
      weapon, armor, ring, bow, #player.inventory, foes),
  }
  local activeSets = Sets.activeDescriptions(player)
  if activeSets then lines[#lines + 1] = "set " .. activeSets end
  local combo = Momentum.stacks(player)
  if combo > 0 then lines[#lines + 1] = string.format("combo x%d", combo) end
  if Conductivity.isWet(player) then lines[#lines + 1] = string.format("wet (%d)", player.wet) end
  local masteryBonus = Proficiency.attackBonus(player)
  if masteryBonus > 0 then
    lines[#lines + 1] = string.format("mastery +%d with %s", masteryBonus, Proficiency.keyFor(player))
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
    lines[#lines + 1] = "ascension " .. table.concat(game.ascension, ",")
  end
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
