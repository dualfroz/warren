local helpers = require("helpers")
local Monsters = require("monsters")
local Level = require("level")
local Hazards = require("hazards")
local Factions = require("factions")
local Biomes = require("biomes")

local ok, eq, arena = helpers.ok, helpers.eq, helpers.arena

local tests = helpers.suite()

function tests.biomesForDepthCyclesThroughTheCatalogInOrder()
  for i, biome in ipairs(Biomes.CATALOG) do
    eq(Biomes.forDepth(i), biome, "depth " .. i .. " maps to the catalog's own entry in order")
  end
  eq(Biomes.forDepth(#Biomes.CATALOG + 1), Biomes.CATALOG[1],
    "depth wraps back to the first biome once the catalog is exhausted")
  eq(Biomes.forDepth(3 * #Biomes.CATALOG), Biomes.CATALOG[#Biomes.CATALOG],
    "depth keeps cycling any number of catalog lengths deep")
end

function tests.biomesDescribeNamesTheBiomeAndItsAmbientText()
  eq(Biomes.describe(Biomes.byKey.warrens), "the mossy warrens: damp stone and skittering claws",
    "describe joins a biome's own name and ambient line")
end

function tests.biomesCatalogEveryEntryNamesARealFactionAndHazardKind()
  local realFactions = {}
  for _, faction in pairs(Factions) do
    if type(faction) == "string" then realFactions[faction] = true end
  end
  for _, biome in ipairs(Biomes.CATALOG) do
    ok(realFactions[biome.favoredFaction], biome.key .. " names a real faction")
    ok(biome.hazardKind == Hazards.FIRE or biome.hazardKind == Hazards.GAS,
      biome.key .. " names a real hazard kind")
  end
end

function tests.biomesNativesAmongFiltersToTheFavoredFactionAndExcludesRangedSpecs()
  local crypts = Biomes.byKey.crypts
  local deepRoster = Monsters.forDepth(6)
  local natives = Biomes.nativesAmong(crypts, deepRoster)
  ok(#natives > 0, "crypts finds at least one native among a deep enough roster")
  for _, spec in ipairs(natives) do
    eq(spec.faction, Factions.UNDEAD, "every native belongs to the biome's own faction")
    ok(spec.ai ~= "ranged", "no native reinforcement is ever a ranged specialist")
  end
  local shallowRoster = Monsters.forDepth(1)
  eq(#Biomes.nativesAmong(crypts, shallowRoster), 0,
    "no undead have surfaced yet this shallow, so crypts finds no native at depth one")
end

function tests.biomeFieldSurvivesSerialization()
  local level = arena(21, 11)
  level.biome = "crypts"
  local restored = Level.fromData(level:toData())
  eq(restored.biome, "crypts", "a floor's biome survives a round trip")
end

return tests
