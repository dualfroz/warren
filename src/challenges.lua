local Ascension = require("ascension")

local Challenges = {}

Challenges.CATALOG = {
  { key = "iron_gauntlet", name = "Iron Gauntlet", class = "fighter", mutators = { "bloodbound" } },
  { key = "arcane_sprint", name = "Arcane Sprint", class = "mage", mutators = { "famine" } },
  { key = "shadow_creed", name = "Shadow Creed", class = "rogue", mutators = {} },
  { key = "wild_hunt", name = "Wild Hunt", class = "ranger", mutators = { "nightblind" } },
}

Challenges.byKey = {}
for _, def in ipairs(Challenges.CATALOG) do
  Challenges.byKey[def.key] = def
end

function Challenges.seedFor(dayIndex)
  return (dayIndex * 2654435761) % 65536
end

function Challenges.forDay(dayIndex)
  local preset = Challenges.CATALOG[(dayIndex % #Challenges.CATALOG) + 1]
  return preset, Challenges.seedFor(dayIndex)
end

function Challenges.satisfiedBy(preset, game)
  if game.player.class ~= preset.class then
    return false, "started as " .. tostring(game.player.class) .. " instead of " .. preset.class
  end
  for _, key in ipairs(preset.mutators) do
    if not Ascension.isActive(game.ascension, key) then
      return false, "missing mutator " .. key
    end
  end
  return true, nil
end

function Challenges.describe(preset)
  if #preset.mutators == 0 then
    return string.format("%s (%s)", preset.name, preset.class)
  end
  return string.format("%s (%s + %s)", preset.name, preset.class, table.concat(preset.mutators, ", "))
end

return Challenges
