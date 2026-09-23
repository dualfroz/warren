local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Level = require("level")
local Crafting = require("crafting")
local Nodes = require("nodes")
local Events = require("events")
local Ascension = require("ascension")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local function nodePlayer()
  return { essence = 0, inventory = {} }
end

local function nodeGame(seed)
  local game = { player = nodePlayer(), rng = Rng.new(seed), level = { event = nil }, ascension = {} }
  function game:essenceMultiplier()
    return Events.essenceMultiplier(self.level.event) * Ascension.essenceMultiplier(self.ascension)
  end
  return game
end

local tests = helpers.suite()

function tests.nodesHarvestingAnOreVeinPaysEssenceAndSpendsACharge()
  local node = Nodes.new(Nodes.ORE)
  local game = nodeGame(3)
  local success, line = Nodes.harvest(game, node)
  ok(success, "harvesting a fresh ore vein succeeds")
  eq(node.charges, Nodes.MAX_CHARGES - 1, "a harvest spends exactly one charge")
  ok(game.player.essence >= Nodes.ORE_YIELD_MIN and game.player.essence <= Nodes.ORE_YIELD_MAX,
    "the essence paid out falls within the vein's yield range")
  ok(contains(line, "essence"), "the harvest is logged")
end

function tests.nodesHarvestingAnOreVeinDoublesItsYieldDuringRichVeins()
  local node = Nodes.new(Nodes.ORE)
  local game = nodeGame(3)
  game.level.event = { key = Events.RICHVEINS, turnsLeft = 5 }
  Nodes.harvest(game, node)
  ok(game.player.essence >= Nodes.ORE_YIELD_MIN * 2 and game.player.essence <= Nodes.ORE_YIELD_MAX * 2,
    "rich veins doubles the vein's ordinary yield range")
end

function tests.nodesHarvestingAGemSeamYieldsARawTierOneGemOfItsElement()
  local node = Nodes.new(Nodes.GEM, Crafting.FIRE)
  local game = nodeGame(3)
  local success = Nodes.harvest(game, node)
  ok(success, "harvesting a fresh gem seam succeeds")
  eq(#game.player.inventory, 1, "a gem lands in the inventory")
  local gem = game.player.inventory[1]
  eq(gem.kind, Items.GEM, "the yield is a gem item")
  eq(gem.element, Crafting.FIRE, "the gem matches the seam's own element")
  eq(gem.tier, 1, "a freshly pried gem is raw, tier one")
end

function tests.nodesGoingFallowRefusesFurtherHarvestsUntilItReopens()
  local node = Nodes.new(Nodes.ORE)
  node.charges = 1
  local game = nodeGame(9)
  ok(Nodes.harvest(game, node), "the last charge still pays out")
  eq(node.charges, 0, "spending the last charge empties the vein")
  eq(node.cooldown, Nodes.REGEN_TURNS, "emptying a vein starts its regen cooldown")
  local success, line = Nodes.harvest(game, node)
  eq(success, false, "a fallow vein refuses to be harvested again")
  ok(contains(line, "played out"), "the refusal is logged")
end

function tests.nodesStepCountsDownAndReopensAFallowNode()
  local level = { nodes = { Nodes.new(Nodes.ORE) } }
  local node = level.nodes[1]
  node.charges = 0
  node.cooldown = 2
  Nodes.step(level)
  eq(node.cooldown, 1, "each step counts the cooldown down by one")
  eq(node.charges, 0, "the vein stays fallow until its cooldown reaches zero")
  Nodes.step(level)
  eq(node.cooldown, 0, "the cooldown reaches zero on schedule")
  eq(node.charges, Nodes.MAX_CHARGES, "reaching zero cooldown fully reopens the vein")
end

function tests.nodesFieldsSurviveSerialization()
  local level = arena(21, 11)
  local node = Nodes.new(Nodes.GEM, Crafting.FROST)
  node.x, node.y = 4, 4
  node.charges = 1
  node.cooldown = 5
  level.nodes = { node }
  local restored = Level.fromData(level:toData())
  eq(#restored.nodes, 1, "the node list survives a round trip")
  eq(restored.nodes[1].kind, Nodes.GEM, "a node's kind survives a round trip")
  eq(restored.nodes[1].element, Crafting.FROST, "a node's element survives a round trip")
  eq(restored.nodes[1].charges, 1, "a node's charges survive a round trip")
  eq(restored.nodes[1].cooldown, 5, "a node's cooldown survives a round trip")
end

function tests.nodeRendersItsGlyphWhenVisible()
  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y = 5, 6
  rendered.level.nodes = { ore }
  rendered:computeVisible()
  ok(contains(rendered:render(), "O"), "an ore vein on a visible cell renders as its glyph")
end

function tests.gameHarvestNodeAtAnOreVeinAddsEssenceAndSpendsACharge()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y = 5, 5
  game.level.nodes = { ore }
  local before = game.player.essence
  ok(game:harvestNode(), "harvesting the ore vein underfoot succeeds")
  ok(game.player.essence > before, "harvesting an ore vein raises the player's essence")
  eq(ore.charges, Nodes.MAX_CHARGES - 1, "harvesting spends one of the vein's charges")
end

function tests.gameHarvestNodeFailsWithoutANodeUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(not game:harvestNode(), "harvesting empty ground fails")
end

function tests.gameHarvestNodeOnAFallowVeinFails()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y, ore.charges = 5, 5, 0
  game.level.nodes = { ore }
  ok(not game:harvestNode(), "a fallow vein cannot be harvested")
end

return tests
