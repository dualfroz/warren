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

function Biomes.forDepth(depth)
  return Biomes.CATALOG[((depth - 1) % #Biomes.CATALOG) + 1]
end

function Biomes.describe(biome)
  return string.format("%s: %s", biome.name, biome.ambient)
end

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
