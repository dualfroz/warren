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

function Export.leaderboardCsv(board)
  local lines = { table.concat(Export.COLUMNS, ",") }
  for rank, entry in ipairs(board) do
    local row = { rank, entry.score, entry.className, entry.depth, entry.turn, entry.won, entry.seed }
    for i, value in ipairs(row) do row[i] = csvField(value) end
    lines[#lines + 1] = table.concat(row, ",")
  end
  return table.concat(lines, "\n") .. "\n"
end

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
