-- Depth-band environmental theme layered on top of the systems that already
-- read raw depth alone: unlike atmosphere.lua's weather (a coin flip drawn
-- fresh on every floor from depth two on, see Atmosphere.order), a biome is
-- a fixed function of depth by itself, so floor three always belongs to the
-- same people and the same climate no matter which seed generated it -
-- weather is what a given run of that floor happens to be like today, a
-- biome is what the floor always is. Each entry names the faction that
-- actually lives there (see factions.lua) and the hazard kind its climate
-- tends toward (see hazards.lua), which the builder's biome pass - appended
-- dead last of all in Builder.build, after even the grave, so it can never
-- perturb any earlier system's rng sequence - may draw on to reinforce a
-- floor with one more native monster or bloom a small pocket of that
-- hazard, strictly on top of everything already placed there.

local Factions = require("factions")
local Hazards = require("hazards")

local Biomes = {}

Biomes.CATALOG = {
  { key = "warrens",  name = "the mossy warrens",  favoredFaction = Factions.VERMIN,    hazardKind = Hazards.GAS,  ambient = "damp stone and skittering claws" },
  { key = "burrows",  name = "the goblin burrows", favoredFaction = Factions.GOBLINOID, hazardKind = Hazards.GAS,  ambient = "crude tunnels reeking of tallow smoke" },
  { key = "crypts",   name = "the sunken crypts",  favoredFaction = Factions.UNDEAD,    hazardKind = Hazards.GAS,  ambient = "cold air thick with grave rot" },
  { key = "warcamp",  name = "the orcish warcamp", favoredFaction = Factions.ORCISH,    hazardKind = Hazards.FIRE, ambient = "smoke-stained banners and cookfires" },
  { key = "sanctum",  name = "the cult sanctum",   favoredFaction = Factions.CULT,      hazardKind = Hazards.FIRE, ambient = "chanting echoes off blood-lit stone" },
  { key = "wyrmnest", name = "the wyrm's nest",    favoredFaction = Factions.DRAKE,     hazardKind = Hazards.FIRE, ambient = "scorched walls and the reek of sulfur" },
}

Biomes.byKey = {}
for _, biome in ipairs(Biomes.CATALOG) do
  Biomes.byKey[biome.key] = biome
end

-- Cyclic by depth, exactly the way chosenGenerator above already cycles
-- through Gen.order: a dungeon of any Builder.maxDepth wraps back through
-- the catalog rather than running off its end once depth outgrows it.
function Biomes.forDepth(depth)
  return Biomes.CATALOG[((depth - 1) % #Biomes.CATALOG) + 1]
end

function Biomes.describe(biome)
  return string.format("%s: %s", biome.name, biome.ambient)
end

-- The subset of an already depth-filtered species list (see
-- Monsters.forDepth) that actually belongs to biome's own faction - the
-- pool the builder's reinforcement pass draws a native from, empty whenever
-- nothing eligible this shallow yet belongs to the biome's own people.
-- Ranged specs are excluded outright: a second archer stacks free damage no
-- melee approach can answer, so reinforcement only ever sends backup a
-- player can actually close the distance on.
function Biomes.nativesAmong(biome, eligible)
  local natives = {}
  for _, spec in ipairs(eligible) do
    if spec.faction == biome.favoredFaction and spec.ai ~= "ranged" then
      natives[#natives + 1] = spec
    end
  end
  return natives
end

return Biomes
