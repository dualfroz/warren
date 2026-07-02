-- Renewable resource nodes scattered on the map: an ore vein pays out
-- crafting essence (crafting.lua's forging currency) and a gem seam yields a
-- raw tier-1 gem outright, both without spending a single turn in combat -
-- a genuine second income alongside killing monsters (Crafting.essenceFor),
-- not a strictly better replacement for it. Each node holds a fixed number
-- of charges before it plays out; a played-out node does not vanish, it goes
-- fallow and slowly reopens on its own, so a floor already cleared of
-- monsters still rewards a return visit. Nodes are plain data on
-- level.nodes, exactly like level.shrines and level.cauldrons, so they
-- serialize with no special save-format handling.

local Crafting = require("crafting")

local Nodes = {}

Nodes.ORE = "ore"
Nodes.GEM = "gem"

Nodes.glyphs = { [Nodes.ORE] = "O", [Nodes.GEM] = "M" }

Nodes.MAX_CHARGES = 3
Nodes.REGEN_TURNS = 40
Nodes.ORE_YIELD_MIN = 3
Nodes.ORE_YIELD_MAX = 7

-- A freshly placed node at full charges, never on cooldown. Builder stamps
-- x/y directly onto the returned table, matching how it stamps every other
-- floor feature (shrines, cauldrons, vault levers).
function Nodes.new(kind, element)
  return { kind = kind, element = element, charges = Nodes.MAX_CHARGES, cooldown = 0 }
end

function Nodes.isFallow(node)
  return node.charges <= 0
end

function Nodes.glyph(node)
  return Nodes.glyphs[node.kind]
end

-- Extracts one charge's worth of resource from `node` into `game.player`.
-- Returns (false, line) without touching the node when it has nothing left
-- to give, or (true, line) once a charge is spent - dropping the node into
-- cooldown the instant that spends its last one.
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

-- Advances every fallow node's cooldown one world round, exactly like
-- hazards.step advances fire and gas - called once per round, not per actor,
-- so a seeded run always reopens a vein on the identical turn regardless of
-- how many actors acted that round.
function Nodes.step(level)
  for _, node in ipairs(level.nodes) do
    if node.cooldown > 0 then
      node.cooldown = node.cooldown - 1
      if node.cooldown <= 0 then node.charges = Nodes.MAX_CHARGES end
    end
  end
end

return Nodes
