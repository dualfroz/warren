-- Named challenge presets: a fixed class, a fixed mutator set and a
-- deterministic seed, bound together so "today's challenge" means the same
-- run for everyone who plays it - the daily-seed ritual familiar
-- roguelikes build around, reproduced here without this module ever
-- touching the wall clock itself (see Challenges.seedFor's own
-- caller-supplied day index), so a test can pin any "day" it likes and get
-- the exact same answer back every time.

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

-- A Knuth multiplicative hash of `dayIndex`, folded into the same 16-bit
-- range warren.lua's own default seed (os.time() & 0xFFFF) already uses, so
-- a challenge seed is never distinguishable from an ordinary one downstream.
function Challenges.seedFor(dayIndex)
  return (dayIndex * 2654435761) % 65536
end

-- The preset and seed "day `dayIndex`" always resolves to - a pure function
-- of dayIndex alone, so the same day always hands out the same challenge to
-- everyone who asks it, and a test can walk arbitrary days without waiting
-- on a clock.
function Challenges.forDay(dayIndex)
  local preset = Challenges.CATALOG[(dayIndex % #Challenges.CATALOG) + 1]
  return preset, Challenges.seedFor(dayIndex)
end

-- True iff `game` was actually played under `preset`'s own terms: started
-- as its class, with every mutator it demands active (see
-- Ascension.isActive) - extra mutators beyond the preset's own are fine,
-- only a missing requirement fails it. Returns (false, reason) naming
-- exactly what fell short, so a caller never has to re-derive why.
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

-- One human-readable line describing `preset`: its display name, the class
-- it demands, and every mutator it demands active - exactly the terms
-- Challenges.satisfiedBy itself checks, spelled out for a player deciding
-- whether to attempt it.
function Challenges.describe(preset)
  if #preset.mutators == 0 then
    return string.format("%s (%s)", preset.name, preset.class)
  end
  return string.format("%s (%s + %s)", preset.name, preset.class, table.concat(preset.mutators, ", "))
end

return Challenges
