-- End-of-run obituary. Turns a finished game's own stats, gear and message
-- log into a NetHack-style morgue report plus a single comparable score,
-- reusing exactly the field names Game:metaStats/graveEntry already expose
-- so a future stat only has to land there to show up here too.

local Curses = require("curses")
local Compendium = require("compendium")
local Titles = require("titles")

local Morgue = {}

Morgue.SCORE_WEIGHTS = {
  depth = 100, kill = 10, bossKill = 250, quest = 150, artifact = 200,
  vault = 120, setPiece = 180, chest = 15, playerLevel = 50, win = 1000,
}

-- A single deterministic number from a Morgue.build report, so two runs
-- (or a run against its own best-so-far) can be ranked without re-reading
-- every field by hand.
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

-- One line per worn slot, empty-handed slots omitted outright rather than
-- padded with "(nothing)" - an obituary should read like a eulogy, not a
-- character sheet.
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

-- Every species this compendium has ever seen the player slay, heaviest
-- kill count first, ties broken by catalog order (Compendium.entries' own
-- fixed order) rather than name so the listing never depends on whatever
-- order table.sort happens to leave equal keys in.
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

-- Gathers everything Morgue.format needs straight off a live or just-ended
-- game, mirroring Game:metaStats' own field names so the two never drift.
-- `meta` is optional (see warren.lua's --meta flag) - a meta-free run's
-- report simply carries no title, exactly like it banks no renown.
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

-- Renders `report` (see Morgue.build) as a fixed-shape text obituary:
-- outcome, vitals, gear, kills, final words, score - always in that order
-- so two runs diff cleanly against each other.
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
