-- Renders meta.lua's own leaderboard as CSV text, one row per entry, for a
-- player who wants their run history in a spreadsheet rather than
-- warren.lua's own --report listing. A leaderboard entry's exact field set
-- (see leaderboard.lua's Leaderboard.record) becomes the exact column set
-- here, so the header row and every data row are always built from the
-- same list and can never drift apart from each other.

local Compendium = require("compendium")

local Export = {}

Export.COLUMNS = { "rank", "score", "className", "depth", "turn", "won", "seed" }
Export.COMPENDIUM_COLUMNS = { "key", "name", "seen", "kills" }

local function csvField(value)
  if value == nil then return "" end
  if value == true then return "true" end
  if value == false then return "false" end
  return tostring(value)
end

-- One CSV document: a header row naming Export.COLUMNS, then one row per
-- `board` entry in its own existing order (best score first, see
-- Leaderboard.record) with a 1-based rank column prepended.
function Export.leaderboardCsv(board)
  local lines = { table.concat(Export.COLUMNS, ",") }
  for rank, entry in ipairs(board) do
    local row = { rank, entry.score, entry.className, entry.depth, entry.turn, entry.won, entry.seed }
    for i, value in ipairs(row) do row[i] = csvField(value) end
    lines[#lines + 1] = table.concat(row, ",")
  end
  return table.concat(lines, "\n") .. "\n"
end

-- One CSV document over every species Compendium.entries knows about (see
-- compendium.lua), sighted or not - so an export always lists the whole
-- bestiary's shape, not just whatever a given save has stumbled across.
function Export.compendiumCsv(compendium)
  local lines = { table.concat(Export.COMPENDIUM_COLUMNS, ",") }
  for _, entry in ipairs(Compendium.entries(compendium)) do
    local row = { entry.key, entry.name, entry.seen, entry.kills }
    for i, value in ipairs(row) do row[i] = csvField(value) end
    lines[#lines + 1] = table.concat(row, ",")
  end
  return table.concat(lines, "\n") .. "\n"
end

return Export
