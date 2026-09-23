local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Map = require("map")
local Astar = require("astar")
local Items = require("items")
local Shop = require("shop")
local Monsters = require("monsters")
local Builder = require("builder")
local Game = require("game")
local Hazards = require("hazards")
local Companions = require("companions")
local Artifacts = require("artifacts")
local Alchemy = require("alchemy")
local Factions = require("factions")
local Atmosphere = require("atmosphere")
local Stealth = require("stealth")
local Nodes = require("nodes")
local Sets = require("sets")
local Digging = require("digging")
local Biomes = require("biomes")
local Blocks = require("blocks")
local Prefab = require("gen.prefab")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local function orthogonalNeighbours(x, y)
  return { { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }
end

local function reachableFrom(map, fromX, fromY, x, y)
  return Astar.find(map, fromX, fromY, x, y, function(cx, cy)
    return not map:isPassable(cx, cy, false)
  end) ~= nil
end

local tests = helpers.suite()

function tests.builderCanBeExplicitlySteeredToAMazeFloorAndStillYieldsAPlayableLevel()
  local level = Builder.build(3, Rng.new(11), { generator = "maze" })
  eq(level.generator, "maze", "the level remembers it was built with the maze generator")
  eq(level.map:get(level.upX, level.upY), Tiles.STAIRS_UP, "a maze floor still gets its up stairs")
  eq(level.map:get(level.downX, level.downY), Tiles.STAIRS_DOWN, "a maze floor still gets its down stairs")
  local path = Astar.find(level.map, level.upX, level.upY, level.downX, level.downY, function(x, y)
    return not level.map:isPassable(x, y, true)
  end)
  ok(path ~= nil, "the down stairs are reachable from the up stairs on a maze floor")
end

function tests.doorsAndKeys()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.inventory = {}
  game.level.map:set(4, 6, Tiles.DOOR_CLOSED)
  game:movePlayer(1, 0)
  eq(game.level.map:get(4, 6), Tiles.DOOR_OPEN, "bumping a closed door opens it")
  eq(game.player.x, 3, "opening a door does not move the player")

  game.level.map:set(2, 6, Tiles.FLOOR)
  game.level.map:set(4, 6, Tiles.DOOR_LOCKED)
  game:movePlayer(1, 0)
  eq(game.level.map:get(4, 6), Tiles.DOOR_LOCKED, "a locked door stays shut without a key")
  eq(game.log:last(), "the door is locked", "the game reports a locked door")
  game.player.inventory[#game.player.inventory + 1] = Items.key()
  game:movePlayer(1, 0)
  eq(game.level.map:get(4, 6), Tiles.DOOR_OPEN, "a key unlocks the door")
  eq(#game.player.inventory, 0, "unlocking consumes the key")
end

function tests.builderOccasionallyPlacesAShrineFromDepthFour()
  local level = Builder.build(4, Rng.new(1), {})
  ok(#level.shrines >= 1, "this seed's depth-4 floor places a shrine")
  eq(level.shrines[1].uses, 0, "a freshly built shrine starts unused")
end

function tests.builderOccasionallySeedsAShopWithMatchingWares()
  local level = Builder.build(4, Rng.new(1), {})
  local keeper
  for _, e in ipairs(level.entities) do
    if e.species == "shopkeeper" then keeper = e end
  end
  ok(keeper ~= nil, "this seed's depth-4 floor spawns a shopkeeper")
  local waresFound = 0
  for _, ground in ipairs(level.floorItems) do
    if ground.price then
      waresFound = waresFound + 1
      eq(ground.shopId, keeper.id, "every priced ware is tagged with its shopkeeper's id")
      ok(ground.price > 0, "every priced ware has a positive price")
    end
  end
  ok(waresFound >= 3, "the shop stocks at least three wares")
end

function tests.buildersScatterHerbsFromTheFirstFloor()
  local level = Builder.build(1, Rng.new(1), {})
  local herbs = 0
  for _, ground in ipairs(level.floorItems) do
    if ground.item.kind == Items.HERB then herbs = herbs + 1 end
  end
  ok(herbs >= 2, "the entrance floor already scatters foraging herbs")
end

function tests.buildersOccasionallyPlaceACauldronFromDepthTwo()
  local level = Builder.build(2, Rng.new(14), {})
  eq(#level.cauldrons, 1, "this seed's depth-2 floor places a cauldron")
end

function tests.buildersNeverPlaceANodeOnTheEntranceFloor()
  for seed = 1, 5 do
    local level = Builder.build(1, Rng.new(seed), {})
    eq(#level.nodes, 0, "no resource node appears on the entrance floor")
  end
end

function tests.buildersAlwaysPlaceAtLeastOneNodeFromDepthTwoOn()
  for seed = 1, 5 do
    for depth = 2, 5 do
      local level = Builder.build(depth, Rng.new(seed), {})
      ok(#level.nodes >= 1, "every depth-2-and-deeper floor places at least one resource node")
      ok(#level.nodes <= 2, "no floor places more than two resource nodes")
      for _, node in ipairs(level.nodes) do
        ok(node.kind == Nodes.ORE or node.kind == Nodes.GEM, "every placed node is a known kind")
      end
    end
  end
end

function tests.builderOccasionallyPlacesACharmFromDepthThree()
  local level = Builder.build(3, Rng.new(1), {})
  local found
  for _, ground in ipairs(level.floorItems) do
    if ground.item.kind == Items.CHARM then found = ground.item end
  end
  ok(found ~= nil, "this seed's depth-3 floor places a companion's charm")
  ok(Companions.byKey[found.companion] ~= nil, "the charm names a real companion species")
end

function tests.builderOccasionallyPlacesAnArtifactFromDepthFive()
  local level = Builder.build(5, Rng.new(4), {})
  local found
  for _, ground in ipairs(level.floorItems) do
    if ground.item.artifact then found = ground.item end
  end
  ok(found ~= nil, "this seed's depth-5 floor places a named artifact")
  ok(Artifacts.byKey[found.artifact] ~= nil, "the artifact names a real catalog entry")
end

function tests.builderOccasionallyPlacesATrapKitFromDepthTwo()
  local level = Builder.build(3, Rng.new(3), {})
  local found
  for _, ground in ipairs(level.floorItems) do
    if ground.item.kind == Items.KIT then found = ground.item end
  end
  ok(found ~= nil, "this seed's depth-3 floor places a trap kit")
  local isKnownEffect = false
  for _, effect in ipairs(Builder.TRAP_EFFECTS) do
    if found.effect == effect then isKnownEffect = true end
  end
  ok(isKnownEffect, "the kit's effect is one of Builder.TRAP_EFFECTS")
end

function tests.builderOccasionallyPlacesABossFromDepthSix()
  local level = Builder.build(6, Rng.new(8), {})
  local found
  for _, entity in ipairs(level.entities) do
    if entity.isBoss then found = entity end
  end
  ok(found ~= nil, "this seed's depth-6 floor places a named boss")
  eq(found.bossKey, "warlord", "the only boss eligible at depth 6 is the warlord")
end

function tests.builderOccasionallyPlacesAQuestBoardFromDepthTwo()
  local level = Builder.build(2, Rng.new(11), {})
  eq(#level.questBoards, 1, "this seed's depth-2 floor places a bounty board")
  eq(level.questBoards[1].claimed, false, "a freshly built board starts unclaimed")
  ok(level.questBoards[1].quest ~= nil, "a freshly built board already carries its one bounty")
end

function tests.builderOccasionallyPlacesLavaChasmAndIceFromDepthFour()
  local sawLava, sawChasm, sawIce = false, false, false
  for seed = 1, 60 do
    local level = Builder.build(4, Rng.new(seed), {})
    for _, tile in ipairs(level.map.tiles) do
      if tile == Tiles.LAVA then sawLava = true end
      if tile == Tiles.CHASM then sawChasm = true end
      if tile == Tiles.ICE then sawIce = true end
    end
    if sawLava and sawChasm and sawIce then break end
  end
  ok(sawLava, "a depth-4 floor eventually places lava on some seed")
  ok(sawChasm, "a depth-4 floor eventually places a chasm on some seed")
  ok(sawIce, "a depth-4 floor eventually places ice on some seed")
end

function tests.builderOccasionallyPromotesAMonsterToEliteFromDepthThree()
  local level = Builder.build(3, Rng.new(1), {})
  local found
  for _, e in ipairs(level.entities) do
    if e.elite then found = e end
  end
  ok(found ~= nil, "this seed's depth-3 floor promotes a monster to elite")
  eq(found.eliteTier, "elite", "a depth-3 promotion is a plain elite, never a champion")
end

function tests.builderOccasionallyPlacesAVaultFromDepthFive()
  local level = Builder.build(5, Rng.new(41), {})
  eq(#level.vaultDoors, 1, "this seed's depth-5 floor places exactly one vault door")
  ok(#level.vaultLevers >= 2, "the vault's puzzle has at least two levers")
  local door = level.vaultDoors[1]
  eq(level.map:get(door.x, door.y), Tiles.VAULT_DOOR, "the vault door's own tile matches its sealed glyph")
  for _, lever in ipairs(level.vaultLevers) do
    eq(lever.id, door.id, "every placed lever shares the door's own vault id")
    eq(level.map:get(lever.x, lever.y), Tiles.LEVER, "each lever's tile matches its unpulled glyph")
  end
  local found
  for _, ground in ipairs(level.floorItems) do
    if ground.item.name and ground.item.name:find("vault", 1, true) then found = ground.item end
  end
  ok(found ~= nil, "the vault's guaranteed treasure is placed somewhere on the floor")
end

function tests.builderOnlyEverPlacesASolvableVaultPuzzle()
  local checked = 0
  for seed = 1, 200 do
    local level = Builder.build(5, Rng.new(seed), {})
    if #level.vaultDoors == 1 then
      checked = checked + 1
      for _, lever in ipairs(level.vaultLevers) do
        local path = Astar.find(level.map, level.upX, level.upY, lever.x, lever.y, function(x, y)
          if x == lever.x and y == lever.y then return false end
          return not level.map:isPassable(x, y, false)
        end)
        ok(path ~= nil, "seed " .. seed .. ": every vault lever is reachable without a key or the vault door")
      end
    end
  end
  ok(checked > 0, "at least one of the sampled seeds actually placed a vault to check")
end

function tests.builderOccasionallyPlacesARuneFromDepthThree()
  local level = Builder.build(3, Rng.new(1), {})
  local found
  for _, ground in ipairs(level.floorItems) do
    if ground.item.kind == Items.RUNE then found = ground.item end
  end
  ok(found ~= nil, "this seed's depth-3 floor places a rune stone")
  ok(found.rune ~= nil, "the placed rune names a real catalog key")
end

function tests.builderOccasionallyDrawsEachWeatherConditionFromDepthTwo()
  local infested = Builder.build(2, Rng.new(1), {})
  eq(infested.weather, Atmosphere.INFESTED, "this seed's depth-2 floor draws an infested reading")
  local rat
  for _, entity in ipairs(infested.entities) do
    if entity.species == "rat" then rat = entity end
  end
  ok(rat ~= nil, "an infested floor still places its usual monsters")
  eq(rat.attack, Monsters.byKey.rat.attack + Atmosphere.monsterAttackBonus(Atmosphere.INFESTED),
    "an infested floor bakes its attack bonus into every monster placed on it")

  local consecrated = Builder.build(2, Rng.new(3), {})
  eq(consecrated.weather, Atmosphere.CONSECRATED, "this seed's depth-2 floor draws a consecrated reading")
  local foggy = Builder.build(2, Rng.new(6), {})
  eq(foggy.weather, Atmosphere.FOGGY, "this seed's depth-2 floor draws a foggy reading")
end

function tests.builderLevelsCarryTheBiomeMatchingTheirDepthRegardlessOfSeed()
  for depth = 1, 8 do
    local expected = Biomes.forDepth(depth).key
    for seed = 1, 3 do
      local level = Builder.build(depth, Rng.new(seed), {})
      eq(level.biome, expected, "depth " .. depth .. " always carries its own fixed biome no matter the seed")
    end
  end
end

function tests.builderOccasionallyReinforcesAFloorWithADormantNativeMonster()
  local level = Builder.build(1, Rng.new(7), {})
  ok(#level.entities > 7, "this seed's entrance floor carries one more monster than the ordinary roster ever places")
  local reinforcement = level.entities[#level.entities]
  eq(reinforcement.faction, Factions.VERMIN, "the extra monster belongs to the entrance floor's own biome")
  eq(reinforcement.awareness, Stealth.DORMANT, "the reinforcement starts dormant like every other wild monster")
end

function tests.builderOccasionallyBloomsAHazardMatchingTheFloorSBiome()
  local warrens = Builder.build(1, Rng.new(7), {})
  eq(warrens.hazards[1].kind, Hazards.GAS, "a gas-favoring biome only ever blooms gas at generation")
  local warcamp = Builder.build(4, Rng.new(11), {})
  eq(warcamp.hazards[1].kind, Hazards.FIRE, "a fire-favoring biome only ever blooms fire at generation")
end

function tests.builderPlacesWildDepthOneMonstersAsleepByDefault()
  local game = Game.new(9)
  ok(#game.level.entities > 0, "the opening floor spawns at least one wild monster")
  for _, entity in ipairs(game.level.entities) do
    eq(entity.awareness, Stealth.DORMANT, "every builder-placed wild monster on the opening floor starts asleep")
  end
end

function tests.builderOccasionallyPlacesASetPieceFromDepthThree()
  local found
  for seed = 1, 20 do
    local level = Builder.build(3, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.set then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "a depth-3 floor eventually places a set piece across a handful of seeds")
  ok(Sets.byKey[found.set] ~= nil, "the placed piece names a real catalog set")
end

function tests.builderOccasionallyPlacesAMimicFromDepthTwo()
  local found
  for seed = 1, 20 do
    local level = Builder.build(2, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.mimic then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "a depth-2 floor eventually places a disguised mimic across a handful of seeds")
end

function tests.builderOccasionallyPlacesACursedPieceOfGear()
  local found
  for seed = 1, 80 do
    local level = Builder.build(2, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.cursed then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "a cursed piece of gear eventually turns up across a handful of seeds")
  ok(found.cursePenalty ~= nil or found.curseDrain ~= nil, "a cursed drop always carries a concrete penalty")
end

function tests.builderNeverCursesAnItemThatAlreadyHasABeneficialAffix()
  for seed = 1, 30 do
    for depth = 1, 5 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, ground in ipairs(level.floorItems) do
        if ground.item.affix then
          ok(not ground.item.cursed, "an item with a beneficial affix is never also cursed")
        end
      end
    end
  end
end

function tests.builderCanRollATomeOfTheShockBoltSpell()
  local found
  for seed = 1, 200 do
    local level = Builder.build(6, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.TOME and ground.item.spell == "shock" then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "the shock bolt tome is reachable dungeon loot within a reasonable seed range")
  eq(found.name, "tome of shock", "an unnamed tome defaults its label to the spell key")
end

function tests.builderNeverPlacesAPickBeforeDepthTwo()
  for seed = 1, 20 do
    local level = Builder.build(1, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      ok(ground.item.kind ~= Items.PICK, "a pick never turns up on the entrance floor")
    end
  end
end

function tests.builderOccasionallyPlacesAPickFromDepthTwo()
  local level = Builder.build(2, Rng.new(6), {})
  local found
  for _, ground in ipairs(level.floorItems) do
    if ground.item.kind == Items.PICK then found = ground.item end
  end
  ok(found ~= nil, "this seed's depth-2 floor places a miner's pick")
  ok(Shop.priceOf(found) > 0, "the placed pick still carries a positive catalog price")
end

function tests.builderOccasionallyRollsAPotionOfClarityAsLoot()
  local found
  for seed = 1, 200 do
    local level = Builder.build(2, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.POTION and ground.item.effect == "clarity" then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "a potion of clarity eventually turns up in the depth-2 loot table across a handful of seeds")
  ok(Shop.priceOf(found) > 0, "a found clarity potion still carries a positive catalog price")
end

function tests.builderOccasionallyRollsAPotionOfConfusionAsLoot()
  local found
  for seed = 1, 200 do
    local level = Builder.build(2, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.POTION and ground.item.effect == "confuse" then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "a potion of confusion eventually turns up in the depth-2 loot table across a handful of seeds")
  ok(Shop.priceOf(found) > 0, "a found confusion potion still carries a positive catalog price")
end

function tests.builderOccasionallyRollsAPotionOfBlindnessAsLoot()
  local found
  for seed = 1, 200 do
    local level = Builder.build(2, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.POTION and ground.item.effect == "blind" then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "a potion of blindness eventually turns up in the depth-2 loot table across a handful of seeds")
  ok(Shop.priceOf(found) > 0, "a found blindness potion still carries a positive catalog price")
end

function tests.builderOccasionallyRollsAPotionOfLevitationAsLoot()
  local found
  for seed = 1, 200 do
    local level = Builder.build(2, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.POTION and ground.item.effect == "levitate" then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "a potion of levitation eventually turns up in the depth-2 loot table across a handful of seeds")
  ok(Shop.priceOf(found) > 0, "a found levitation potion still carries a positive catalog price")
end

function tests.builderNeverPlacesAGraveWhenOptionsCarriesNone()
  for seed = 1, 15 do
    local level = Builder.build(5, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      ok(not ground.item.grave, "no grave appears without the caller supplying any")
    end
  end
end

function tests.buildersOnlyRollAGraveOntoAFloorAtOrShallowerThanWhereItWasDug()
  local shallowGrave = { className = "rogue", depth = 2, gold = 40, essence = 5, turn = 30 }
  local found = false
  for seed = 1, 40 do
    local level = Builder.build(5, Rng.new(seed), { graves = { shallowGrave } })
    for _, ground in ipairs(level.floorItems) do
      if ground.item.grave then found = true end
    end
  end
  ok(not found, "a grave dug at depth 2 never surfaces on a floor as deep as 5")
end

function tests.buildersOccasionallyPlaceAnEligibleGraveFromSuppliedOptions()
  local deepGrave = { className = "mage", depth = 6, gold = 80, essence = 12, turn = 90 }
  local found
  for seed = 1, 40 do
    local level = Builder.build(3, Rng.new(seed), { graves = { deepGrave } })
    for _, ground in ipairs(level.floorItems) do
      if ground.item.grave then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "a floor eventually rolls an eligible grave across a handful of seeds")
  eq(found.graveClass, "mage", "the placed marker carries the fallen's own class")
end

function tests.buildersInsertAGraveWithoutDisturbingAnyOtherPlacement()
  local grave = { className = "fighter", depth = 8, gold = 60, essence = 9, turn = 50 }
  local perturbed = false
  local sawExtra = false
  for seed = 1, 40 do
    local plain = Builder.build(4, Rng.new(seed), {})
    local withGrave = Builder.build(4, Rng.new(seed), { graves = { grave } })
    if table.concat(plain.map.tiles) ~= table.concat(withGrave.map.tiles) then perturbed = true end
    if #withGrave.entities ~= #plain.entities then perturbed = true end
    if #withGrave.floorItems == #plain.floorItems + 1 then
      sawExtra = true
      local extra = withGrave.floorItems[#withGrave.floorItems]
      ok(extra.item.grave, "the one extra floor item a supplied grave adds is the grave marker itself")
    elseif #withGrave.floorItems ~= #plain.floorItems then
      perturbed = true
    end
  end
  ok(not perturbed, "supplying a grave never changes the map or any other placement, only adds at most its own marker")
  ok(sawExtra, "across a handful of seeds, at least one actually places the grave marker")
end

function tests.builderOccasionallyPlacesASecretDoorGuardingAGenuinelyUnreachableAlcove()
  local checked = 0
  for seed = 1, 200 do
    local level = Builder.build(3, Rng.new(seed), {})
    if #level.secretDoors == 1 then
      checked = checked + 1
      local door = level.secretDoors[1]
      eq(door.discovered, false, "a freshly built floor's secret door always starts undiscovered")
      eq(level.map:get(door.x, door.y), Tiles.WALL, "an undiscovered secret door still reads as an ordinary wall")

      local alcoveX, alcoveY
      for _, n in ipairs(orthogonalNeighbours(door.x, door.y)) do
        local nx, ny = n[1], n[2]
        if level.map:isWalkable(nx, ny) and not reachableFrom(level.map, level.upX, level.upY, nx, ny) then
          alcoveX, alcoveY = nx, ny
        end
      end
      ok(alcoveX ~= nil, "seed " .. seed .. ": the secret door hides a genuinely unreachable alcove cell")
      if alcoveX then
        level.map:set(door.x, door.y, Tiles.DOOR_CLOSED)
        ok(reachableFrom(level.map, level.upX, level.upY, alcoveX, alcoveY),
          "seed " .. seed .. ": the same alcove opens up the instant its door is discovered")
      end
      if checked >= 10 then break end
    end
  end
  ok(checked > 0, "at least one of the sampled seeds actually places a secret door")
end

function tests.builderNeverPlacesASecretDoorAboveDepthTwo()
  for seed = 1, 10 do
    local level = Builder.build(1, Rng.new(seed), {})
    eq(#level.secretDoors, 0, "no secret door appears on the first floor")
  end
end

function tests.builderCanRollATomeOfTheDiscordSpellSomewhereInARangeOfSeeds()
  local found = false
  for seed = 1, 100 do
    local level = Builder.build(6, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.TOME and ground.item.spell == "discord" then found = true end
    end
    if found then break end
  end
  ok(found, "the discord tome is reachable dungeon loot within a reasonable seed range")
end

function tests.builderCanRollATomeOfTheConfuseSpellSomewhereInARangeOfSeeds()
  local found = false
  for seed = 1, 100 do
    local level = Builder.build(6, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.TOME and ground.item.spell == "confuse" then found = true end
    end
    if found then break end
  end
  ok(found, "the confuse tome is reachable dungeon loot within a reasonable seed range")
end

function tests.builderCanRollAConfuseTrapOrTrapKitSomewhereInARangeOfSeeds()
  local sawTrap, sawKit = false, false
  for seed = 1, 100 do
    local level = Builder.build(3, Rng.new(seed), {})
    for _, trap in ipairs(level.traps) do
      if trap.effect == "confuse" then sawTrap = true end
    end
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.KIT and ground.item.effect == "confuse" then sawKit = true end
    end
    if sawTrap and sawKit then break end
  end
  ok(sawTrap, "a builder-placed confuse trap is reachable within a reasonable seed range")
  ok(sawKit, "a confuse trap kit is reachable dungeon loot within a reasonable seed range")
end

function tests.builderCanRollABlindTrapOrTrapKitSomewhereInARangeOfSeeds()
  local sawTrap, sawKit = false, false
  for seed = 1, 100 do
    local level = Builder.build(3, Rng.new(seed), {})
    for _, trap in ipairs(level.traps) do
      if trap.effect == "blind" then sawTrap = true end
    end
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.KIT and ground.item.effect == "blind" then sawKit = true end
    end
    if sawTrap and sawKit then break end
  end
  ok(sawTrap, "a builder-placed blind trap is reachable within a reasonable seed range")
  ok(sawKit, "a blind trap kit is reachable dungeon loot within a reasonable seed range")
end

function tests.builderCanRollAStunTrapOrTrapKitSomewhereInARangeOfSeeds()
  local sawTrap, sawKit = false, false
  for seed = 1, 100 do
    local level = Builder.build(3, Rng.new(seed), {})
    for _, trap in ipairs(level.traps) do
      if trap.effect == "stun" then sawTrap = true end
    end
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.KIT and ground.item.effect == "stun" then sawKit = true end
    end
    if sawTrap and sawKit then break end
  end
  ok(sawTrap, "a builder-placed stun trap is reachable within a reasonable seed range")
  ok(sawKit, "a stun trap kit is reachable dungeon loot within a reasonable seed range")
end

function tests.builderCanRollATomeOfTheBlindSpellSomewhereInARangeOfSeeds()
  local found = false
  for seed = 1, 200 do
    local level = Builder.build(6, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.TOME and ground.item.spell == "blind" then found = true end
    end
    if found then break end
  end
  ok(found, "the blind tome is reachable dungeon loot within a reasonable seed range")
end

function tests.builderCanRollATomeOfTheWeakenSpellSomewhereInARangeOfSeeds()
  local found = false
  for seed = 1, 200 do
    local level = Builder.build(6, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.TOME and ground.item.spell == "weaken" then found = true end
    end
    if found then break end
  end
  ok(found, "the weaken tome is reachable dungeon loot within a reasonable seed range")
end

function tests.builderCanRollATomeOfTheCleanseSpellSomewhereInARangeOfSeeds()
  local found = false
  for seed = 1, 200 do
    local level = Builder.build(6, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.TOME and ground.item.spell == "cleanse" then found = true end
    end
    if found then break end
  end
  ok(found, "the cleanse tome is reachable dungeon loot within a reasonable seed range")
end

function tests.builderCanRollATomeOfTheLevitateSpellSomewhereInARangeOfSeeds()
  local found = false
  for seed = 1, 200 do
    local level = Builder.build(6, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.TOME and ground.item.spell == "levitate" then found = true end
    end
    if found then break end
  end
  ok(found, "the levitate tome is reachable dungeon loot within a reasonable seed range")
end

function tests.builderCanRollATomeOfThePolymorphSpellSomewhereInARangeOfSeeds()
  local found = false
  for seed = 1, 200 do
    local level = Builder.build(6, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.TOME and ground.item.spell == "polymorph" then found = true end
    end
    if found then break end
  end
  ok(found, "the polymorph tome is reachable dungeon loot within a reasonable seed range")
end

function tests.builderOccasionallyPlacesAGateBlockPuzzleOnceADoorwayIsAvailable()
  local found = false
  for seed = 1, 200 do
    local level = Builder.build(5, Rng.new(seed), {})
    if #level.gates == 1 then
      found = true
      eq(#level.plates, 1, "a placed gate always comes with exactly one linked plate")
      eq(#level.blocks, 1, "a placed gate always comes with exactly one pushable block")
      local gate, plate, block = level.gates[1], level.plates[1], level.blocks[1]
      eq(plate.gateX, gate.x, "the plate's gate link matches the placed gate's x")
      eq(plate.gateY, gate.y, "the plate's gate link matches the placed gate's y")
      eq(level.map:get(gate.x, gate.y), Tiles.GATE_CLOSED, "the gate starts sealed on its own tile")
      local dx, dy = plate.x - block.x, plate.y - block.y
      ok((dx == 0 and math.abs(dy) == 1) or (dy == 0 and math.abs(dx) == 1),
        "the block always starts exactly one cardinal step from its plate")
      local treasureFound
      for _, ground in ipairs(level.floorItems) do
        if ground.item.name and ground.item.name:find("gate%-forged", 1) then treasureFound = ground.item end
      end
      ok(treasureFound ~= nil, "the puzzle's guaranteed treasure is placed somewhere on the floor")
      break
    end
  end
  ok(found, "at least one of the sampled seeds places a gate/block/plate puzzle")
end

function tests.builderOnlyEverPlacesASolvableGatePuzzleThatNeverSealsTheOnlyRoute()
  local checked = 0
  for seed = 1, 200 do
    local level = Builder.build(5, Rng.new(seed), {})
    if #level.gates == 1 then
      checked = checked + 1
      local gate, plate, block = level.gates[1], level.plates[1], level.blocks[1]
      local dx, dy = plate.x - block.x, plate.y - block.y
      local approachX, approachY = block.x - dx, block.y - dy
      local path = Astar.find(level.map, level.upX, level.upY, approachX, approachY, function(x, y)
        if x == approachX and y == approachY then return false end
        if level:blockAt(x, y) then return true end
        return not level.map:isPassable(x, y, false)
      end)
      ok(path ~= nil, "seed " .. seed .. ": the block's approach cell is reachable without crossing the gate")
      local pushed = Blocks.push(level, block, dx, dy)
      ok(pushed, "seed " .. seed .. ": a single shove from the approach cell always succeeds")
      eq(block.x, plate.x, "seed " .. seed .. ": the shoved block lands exactly on its plate's x")
      eq(block.y, plate.y, "seed " .. seed .. ": the shoved block lands exactly on its plate's y")
      ok(reachableFrom(level.map, level.upX, level.upY, level.downX, level.downY),
        "seed " .. seed .. ": the stairs down stay reachable even treating the gate as a wall")
    end
  end
  ok(checked > 0, "at least one of the sampled seeds actually placed a gate to check")
end

function tests.builderStampsEachHandAuthoredVaultMatchingAFreshPrefabStampOfTheSameTemplate()
  local cases = {
    { seed = 5, name = "treasureCell" },
    { seed = 12, name = "guardPost" },
    { seed = 50, name = "flooded" },
  }
  for _, case in ipairs(cases) do
    local level = Builder.build(4, Rng.new(case.seed), {})
    eq(#level.prefabVaults, 1, "seed " .. case.seed .. "'s depth-4 floor places exactly one hand-authored vault")
    local placed = level.prefabVaults[1]
    eq(placed.name, case.name, "seed " .. case.seed .. " places the expected named vault")

    local template
    for _, candidate in ipairs(Prefab.vaults) do
      if candidate.name == case.name then template = candidate end
    end
    local scratch = Map.new(placed.w + 4, placed.h + 4)
    Prefab.stamp(scratch, template, 2, 2)
    local same = true
    for row = 0, placed.h - 1 do
      for col = 0, placed.w - 1 do
        if scratch:get(2 + col, 2 + row) ~= level.map:get(placed.x + col, placed.y + row) then
          same = false
        end
      end
    end
    ok(same, case.name .. ": the floor's stamped footprint matches a fresh Prefab.stamp of the same template exactly")
  end
end

function tests.builderDiggingThroughAPrefabVaultsOuterWallOpensARouteToItsSealedInterior()
  local level = Builder.build(4, Rng.new(49), {})
  eq(#level.prefabVaults, 1, "seed 49's depth-4 floor places exactly one hand-authored vault")
  local vault = level.prefabVaults[1]
  eq(vault.name, "guardPost", "this fixed seed places the guard post vault")

  local wallX, wallY, extX, extY
  for y = vault.y, vault.y + vault.h - 1 do
    for x = vault.x, vault.x + vault.w - 1 do
      local verticalEdge = (x == vault.x or x == vault.x + vault.w - 1) and y > vault.y and y < vault.y + vault.h - 1
      local horizontalEdge = (y == vault.y or y == vault.y + vault.h - 1) and x > vault.x and x < vault.x + vault.w - 1
      local onBoundary = verticalEdge or horizontalEdge
      if onBoundary and not wallX then
        for _, n in ipairs(orthogonalNeighbours(x, y)) do
          local nx, ny = n[1], n[2]
          local outside = nx < vault.x or nx > vault.x + vault.w - 1 or ny < vault.y or ny > vault.y + vault.h - 1
          if outside and level.map:inBounds(nx, ny) and reachableFrom(level.map, level.upX, level.upY, nx, ny) then
            wallX, wallY, extX, extY = x, y, nx, ny
          end
        end
      end
    end
  end
  ok(wallX ~= nil, "at least one of the vault's outer wall cells borders the already-reachable dungeon")
  eq(level.map:get(wallX, wallY), Tiles.WALL, "the bordering cell reads as a plain wall before any digging")
  ok(not reachableFrom(level.map, level.upX, level.upY, wallX, wallY),
    "the wall cell itself is not reachable by ordinary movement while it is still solid rock")

  local inX, inY = 2 * wallX - extX, 2 * wallY - extY
  ok(not reachableFrom(level.map, level.upX, level.upY, inX, inY),
    "the vault's interior stays fully sealed off before the wall is dug through")

  ok(Digging.canDig(level.map, wallX, wallY), "the bordering wall cell is a valid digging target")
  level.map:set(wallX, wallY, Tiles.RUBBLE)
  level.map:set(wallX, wallY, Tiles.FLOOR)
  ok(reachableFrom(level.map, level.upX, level.upY, wallX, wallY),
    "after two swings clear the wall down to floor, the dug cell joins the reachable dungeon")
  ok(level.map:isWalkable(inX, inY), "the cell just inside the dug wall is real, walkable vault interior")
  ok(reachableFrom(level.map, level.upX, level.upY, inX, inY),
    "digging through the outer wall opens a genuine route into the vault's previously sealed interior")
end

function tests.builderOccasionallyPlacesANetFromDepthFive()
  local level = Builder.build(5, Rng.new(10), {})
  local found
  for _, ground in ipairs(level.floorItems) do
    if ground.item.kind == Items.NET then found = ground.item end
  end
  ok(found ~= nil, "this seed's depth-5 floor places a net")
end

function tests.builderPlacesARiftShardFromDepthFourAndARiftFromDepthSix()
  local shardLevel = Builder.build(4, Rng.new(1), {})
  local foundShard = false
  for _, ground in ipairs(shardLevel.floorItems) do
    if ground.item.kind == Items.RIFTSTONE then foundShard = true end
  end
  ok(foundShard, "this seed's depth-4 floor places a rift shard")

  local riftLevel = Builder.build(6, Rng.new(1), {})
  ok(#riftLevel.rifts >= 1, "this seed's depth-6 floor tears open a rift")
end

function tests.buildersOccasionallyRollAMoonbellHerbAsForagingLoot()
  local found
  for seed = 1, 200 do
    local level = Builder.build(1, Rng.new(seed), {})
    for _, ground in ipairs(level.floorItems) do
      if ground.item.kind == Items.HERB and ground.item.herb == Alchemy.MOONBELL then found = ground.item end
    end
    if found then break end
  end
  ok(found ~= nil, "a moonbell herb eventually turns up in the entrance-floor foraging loot across a handful of seeds")
  eq(found.name, "moonbell herb", "a foraged moonbell herb carries its plain, unmasked name like any other herb")
end

return tests
