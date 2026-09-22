local Crafting = require("crafting")

local Nodes = {}

Nodes.ORE = "ore"
Nodes.GEM = "gem"

Nodes.glyphs = { [Nodes.ORE] = "O", [Nodes.GEM] = "S" }

Nodes.MAX_CHARGES = 3
Nodes.REGEN_TURNS = 40
Nodes.ORE_YIELD_MIN = 3
Nodes.ORE_YIELD_MAX = 7

function Nodes.new(kind, element)
  return { kind = kind, element = element, charges = Nodes.MAX_CHARGES, cooldown = 0 }
end

function Nodes.isFallow(node)
  return node.charges <= 0
end

function Nodes.glyph(node)
  return Nodes.glyphs[node.kind]
end

function Nodes.harvest(game, node)
  if Nodes.isFallow(node) then
    return false, "the vein is played out; give it time to reopen"
  end
  node.charges = node.charges - 1
  if node.charges <= 0 then node.cooldown = Nodes.REGEN_TURNS end
  local player = game.player
  if node.kind == Nodes.ORE then
    local amount = math.floor(game.rng:range(Nodes.ORE_YIELD_MIN, Nodes.ORE_YIELD_MAX) * game:essenceMultiplier())
    player.essence = player.essence + amount
    return true, string.format("you chip %d essence from the ore vein", amount)
  end
  local gem = Crafting.gem(node.element, 1)
  player.inventory[#player.inventory + 1] = gem
  return true, "you pry a " .. gem.name .. " loose from the seam"
end

function Nodes.step(level)
  for _, node in ipairs(level.nodes) do
    if node.cooldown > 0 then
      node.cooldown = node.cooldown - 1
      if node.cooldown <= 0 then node.charges = Nodes.MAX_CHARGES end
    end
  end
end

return Nodes
