local helpers = require("helpers")
local Monsters = require("monsters")
local Alchemy = require("alchemy")
local Corpses = require("corpses")
local Scavenging = require("scavenging")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.scavengingHerbForMapsEachWildFactionToItsOwnFixedHerb()
  eq(Scavenging.herbFor({ species = "rat" }), Alchemy.NIGHTCAP, "vermin always yields nightcap")
  eq(Scavenging.herbFor({ species = "goblin" }), Alchemy.BLOODROOT, "goblinoids always yield bloodroot")
  eq(Scavenging.herbFor({ species = "troll" }), Alchemy.EMBERLEAF, "beasts always yield emberleaf")
  eq(Scavenging.herbFor({ species = "dragon" }), Alchemy.EMBERLEAF, "drakes yield the same herb as any other beast-aspected foe")
end

function tests.scavengingHerbForReturnsNilForACorpseWithNoBestiaryEntry()
  eq(Scavenging.herbFor({ species = "hound" }), nil,
    "a bonded companion's own remains carry no bestiary-mapped herb")
end

function tests.gameScavengeCorpseCarvesTheMatchingHerbAndClearsTheCorpse()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 5, 5, 2)
  Corpses.spawn(game.level, goblin)
  local before = #game.player.inventory
  ok(game:scavengeCorpse(), "scavenging the corpse underfoot succeeds")
  eq(#game.level.corpses, 0, "the corpse is gone after scavenging")
  eq(#game.player.inventory, before + 1, "the player's inventory gains the carved herb")
  local herb = game.player.inventory[#game.player.inventory]
  eq(herb.herb, Alchemy.BLOODROOT, "the carved herb matches the goblin's own goblinoid aspect")
  ok(contains(game.log:last(), "carve"), "a successful scavenge is logged")
end

function tests.gameScavengeCorpseFailsWithoutACorpseUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(not game:scavengeCorpse(), "scavenging empty ground fails")
  ok(contains(game.log:last(), "nothing here"), "the failure is logged")
end

function tests.gameScavengeCorpseFailsOnARottenCorpse()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  game.level.corpses[1].decay = Corpses.ROT_TURNS
  local before = #game.player.inventory
  ok(not game:scavengeCorpse(), "a rotten corpse yields no herb")
  eq(#game.level.corpses, 1, "a failed scavenge leaves the corpse in place rather than spending it")
  eq(#game.player.inventory, before, "no herb is added on a failed scavenge")
end

function tests.gameScavengeCorpseFailsForASpeciesWithNoKnownHerb()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.corpses = { { x = 5, y = 5, species = "hound", name = "hound", nutrition = 40, decay = Corpses.DECAY_TURNS } }
  ok(not game:scavengeCorpse(), "a companion's own remains carry nothing worth carving")
  eq(#game.level.corpses, 1, "a failed scavenge leaves the corpse in place")
end

return tests
