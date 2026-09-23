local helpers = require("helpers")
local Game = require("game")
local Classes = require("classes")
local Meta = require("meta")
local Ascension = require("ascension")
local Challenges = require("challenges")

local ok, eq, contains = helpers.ok, helpers.eq, helpers.contains

local tests = helpers.suite()

function tests.challengesForDaySameDayAlwaysReturnsTheSamePresetAndSeed()
  local presetA, seedA = Challenges.forDay(7)
  local presetB, seedB = Challenges.forDay(7)
  eq(presetA, presetB, "the same day index always names the identical preset table")
  eq(seedA, seedB, "the same day index always yields the identical seed")
end

function tests.challengesForDayCyclesThroughTheCatalogInOrder()
  for i = 0, #Challenges.CATALOG - 1 do
    local preset = Challenges.forDay(i)
    eq(preset, Challenges.CATALOG[i + 1], "day " .. i .. " maps to catalog slot " .. (i + 1))
  end
  local wrapped = Challenges.forDay(#Challenges.CATALOG)
  eq(wrapped, Challenges.CATALOG[1], "the cycle wraps back to the first preset after one full lap")
end

function tests.challengesSeedForStaysWithinTheDefaultSeedRange()
  for _, day in ipairs({ 0, 1, 42, 365, 999999 }) do
    local seed = Challenges.seedFor(day)
    ok(seed >= 0 and seed < 65536, "day " .. day .. " hashes into the same 16-bit range as the default seed")
  end
end

function tests.challengesCatalogPresetsReferenceOnlyRealClassesAndMutators()
  for _, preset in ipairs(Challenges.CATALOG) do
    ok(Classes.isValid(preset.class), preset.key .. " names a real class")
    for _, key in ipairs(preset.mutators) do
      ok(Ascension.byKey[key] ~= nil, preset.key .. "'s mutator '" .. key .. "' is a real ascension mutator")
    end
  end
end

function tests.challengesDescribeNamesTheClassAndEveryRequiredMutator()
  local described = Challenges.describe(Challenges.byKey.wild_hunt)
  eq(described, "Wild Hunt (ranger + nightblind)", "a single-mutator preset lists its class and that mutator")
end

function tests.challengesDescribeOmitsTheMutatorJoinWhenNoneAreRequired()
  local described = Challenges.describe(Challenges.byKey.shadow_creed)
  eq(described, "Shadow Creed (rogue)", "a mutator-free preset reads as just its name and class")
end

function tests.challengesSatisfiedByFailsOnAClassMismatch()
  local game = Game.new(9, { class = "rogue" })
  local satisfied, reason = Challenges.satisfiedBy(Challenges.byKey.iron_gauntlet, game)
  eq(satisfied, false, "a rogue never satisfies a fighter-only challenge")
  ok(contains(reason, "fighter"), "the failure names the class the challenge actually required")
end

function tests.challengesSatisfiedBySucceedsWithTheRightClassAndNoMutatorsRequired()
  local game = Game.new(9, { class = "rogue" })
  local satisfied = Challenges.satisfiedBy(Challenges.byKey.shadow_creed, game)
  eq(satisfied, true, "matching the class is enough when the preset demands no mutators")
end

function tests.challengesSatisfiedByFailsWhenARequiredMutatorNeverActivated()
  local game = Game.new(9, { class = "fighter" })
  local satisfied, reason = Challenges.satisfiedBy(Challenges.byKey.iron_gauntlet, game)
  eq(satisfied, false, "a run with no active mutators cannot satisfy one that requires bloodbound")
  eq(reason, "missing mutator bloodbound", "the failure names the exact missing mutator")
end

function tests.challengesSatisfiedBySucceedsOnceItsRequiredMutatorIsActuallyActive()
  local unlocked = Meta.new()
  unlocked.bestDepth = 3
  local game = Game.new(9, { class = "fighter", meta = unlocked, mutators = { "bloodbound" } })
  local satisfied = Challenges.satisfiedBy(Challenges.byKey.iron_gauntlet, game)
  eq(satisfied, true, "the challenge is honored once its required mutator actually resolved active")
end

return tests
