local Curses = require("curses")
local Compendium = require("compendium")
local Titles = require("titles")

local Morgue = {}

Morgue.SCORE_WEIGHTS = {
  depth = 100, kill = 10, bossKill = 250, quest = 150, artifact = 200,
  vault = 120, setPiece = 180, chest = 15, playerLevel = 50, win = 1000,
}

function Morgue.score(report)
  local w = Morgue.SCORE_WEIGHTS
  local total = report.deepestDepth * w.depth + report.kills * w.kill
    + report.bossKills * w.bossKill + report.questsCompleted * w.quest
    + report.artifactsFound * w.artifact + report.vaultsOpened * w.vault
    + report.setPiecesFound * w.setPiece + report.chestsOpened * w.chest
    + report.playerLevel * w.playerLevel + report.gold
  if report.won then total = total + w.win end
  return total
end

Morgue.EQUIP_SLOTS = { "weapon", "armor", "ring", "bow" }

function Morgue.equipment(player)
  local lines = {}
  for _, slot in ipairs(Morgue.EQUIP_SLOTS) do
    local item = player[slot]
    if item then
      lines[#lines + 1] = slot .. ": " .. Curses.label(item, item.name)
    end
  end
  return lines
end

function Morgue.killTally(compendium)
  local rows = {}
  for i, entry in ipairs(Compendium.entries(compendium)) do
    if entry.kills > 0 then
      rows[#rows + 1] = { key = entry.key, name = entry.name, kills = entry.kills, order = i }
    end
  end
  table.sort(rows, function(a, b)
    if a.kills ~= b.kills then return a.kills > b.kills end
    return a.order < b.order
  end)
  return rows
end

function Morgue.build(game, meta)
  return {
    won = game.won,
    alive = game.player:isAlive(),
    className = game.player.class or "wanderer",
    title = meta and Titles.forRenown(meta.renown) or nil,
    playerLevel = game.player.level,
    deepestDepth = game.deepestDepth,
    turn = game.turn,
    gold = game.player.gold,
    essence = game.player.essence,
    kills = game.stats.kills,
    bossKills = game.stats.bossKills,
    questsCompleted = game.stats.questsCompleted,
    artifactsFound = game.stats.artifactsFound,
    vaultsOpened = game.stats.vaultsOpened,
    setPiecesFound = game.stats.setPiecesFound,
    chestsOpened = game.stats.chestsOpened,
    equipment = Morgue.equipment(game.player),
    killTally = Morgue.killTally(game.compendium),
    finalMessages = game.log:recent(5),
  }
end

local function outcomeLine(report)
  if report.won then return "escaped the warren with the Amulet" end
  if report.alive then return "still drawing breath, for now" end
  return "died in the dark"
end

function Morgue.format(report)
  local lines = {}
  local heading = report.alive and (report.won and "Victorious" or "Wandering") or "Late"
  if report.title then
    lines[#lines + 1] = string.format("%s the %s, the %s", heading, report.className, report.title)
  else
    lines[#lines + 1] = string.format("%s the %s", heading, report.className)
  end
  lines[#lines + 1] = outcomeLine(report)
  lines[#lines + 1] = string.format("depth %d, turn %d, level %d", report.deepestDepth, report.turn,
    report.playerLevel)
  lines[#lines + 1] = string.format("gold %d, essence %d", report.gold, report.essence)
  if #report.equipment > 0 then
    lines[#lines + 1] = "equipment:"
    for _, line in ipairs(report.equipment) do lines[#lines + 1] = "  " .. line end
  end
  if #report.killTally > 0 then
    lines[#lines + 1] = "kills:"
    for _, row in ipairs(report.killTally) do
      lines[#lines + 1] = string.format("  %-14s x%d", row.name, row.kills)
    end
  end
  if #report.finalMessages > 0 then
    lines[#lines + 1] = "final moments:"
    for _, line in ipairs(report.finalMessages) do lines[#lines + 1] = "  " .. line end
  end
  lines[#lines + 1] = string.format("score: %d", Morgue.score(report))
  return table.concat(lines, "\n") .. "\n"
end

return Morgue
