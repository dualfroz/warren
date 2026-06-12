-- Herb-based potion brewing, layered on top of items.lua's existing potion
-- catalog rather than inventing a second one: a cauldron turns two foraged
-- herbs into the same potions rollItem already scatters as loot, so a
-- brewed potion drinks, throws (throwing.lua) and identifies exactly like a
-- found one. Recipes are fixed data, the same way crafting.lua's elemental
-- riders are fixed - the uncertainty here is not "what does this pair do"
-- but whether two ill-matched herbs curdle instead of brewing cleanly. See
-- Game:brewAt for how a curdle is resolved against the brewer.

local Items = require("items")

local Alchemy = {}

Alchemy.SUNPETAL = "sunpetal"
Alchemy.BLOODROOT = "bloodroot"
Alchemy.EMBERLEAF = "emberleaf"
Alchemy.FROSTMOSS = "frostmoss"
Alchemy.NIGHTCAP = "nightcap"
Alchemy.MOONBELL = "moonbell"

-- Fixed order so a given rng draw always names the same herb. New herbs
-- append at the end (see builder.lua's own comment on Alchemy.order) so an
-- existing seed's earlier picks never change which herb they name.
Alchemy.order = {
  Alchemy.BLOODROOT, Alchemy.EMBERLEAF, Alchemy.FROSTMOSS, Alchemy.NIGHTCAP, Alchemy.SUNPETAL,
  Alchemy.MOONBELL,
}

Alchemy.names = {
  [Alchemy.SUNPETAL] = "sunpetal",
  [Alchemy.BLOODROOT] = "bloodroot",
  [Alchemy.EMBERLEAF] = "emberleaf",
  [Alchemy.FROSTMOSS] = "frostmoss",
  [Alchemy.NIGHTCAP] = "nightcap",
  [Alchemy.MOONBELL] = "moonbell",
}

local CURDLE = { curdle = true }

-- Canonical order-independent key for a herb pair: the two herb keys sorted
-- and joined, so brewing (A, B) and (B, A) always land on the same recipe.
local function pairKey(a, b)
  if a > b then a, b = b, a end
  return a .. "+" .. b
end
Alchemy.pairKey = pairKey

-- Same-herb pairs concentrate that herb's own aspect; cross pairs blend two
-- aspects into a shared potion, except the pairings whose aspects outright
-- oppose each other (light versus shade, fire versus frost, day versus
-- dream), which curdle instead of brewing.
Alchemy.recipes = {
  [pairKey(Alchemy.SUNPETAL, Alchemy.SUNPETAL)] = { effect = "heal", power = 18 },
  [pairKey(Alchemy.SUNPETAL, Alchemy.BLOODROOT)] = { effect = "heal", power = 10 },
  [pairKey(Alchemy.SUNPETAL, Alchemy.EMBERLEAF)] = { effect = "haste" },
  [pairKey(Alchemy.SUNPETAL, Alchemy.FROSTMOSS)] = { effect = "fortify" },
  [pairKey(Alchemy.SUNPETAL, Alchemy.NIGHTCAP)] = CURDLE,
  [pairKey(Alchemy.BLOODROOT, Alchemy.BLOODROOT)] = { effect = "strength" },
  [pairKey(Alchemy.BLOODROOT, Alchemy.EMBERLEAF)] = { effect = "strength" },
  [pairKey(Alchemy.BLOODROOT, Alchemy.FROSTMOSS)] = { effect = "fortify" },
  [pairKey(Alchemy.BLOODROOT, Alchemy.NIGHTCAP)] = { effect = "poison", power = 4 },
  [pairKey(Alchemy.EMBERLEAF, Alchemy.EMBERLEAF)] = { effect = "haste" },
  [pairKey(Alchemy.EMBERLEAF, Alchemy.FROSTMOSS)] = CURDLE,
  [pairKey(Alchemy.EMBERLEAF, Alchemy.NIGHTCAP)] = { effect = "poison", power = 5 },
  [pairKey(Alchemy.FROSTMOSS, Alchemy.FROSTMOSS)] = { effect = "fortify" },
  [pairKey(Alchemy.FROSTMOSS, Alchemy.NIGHTCAP)] = { effect = "poison", power = 5 },
  [pairKey(Alchemy.NIGHTCAP, Alchemy.NIGHTCAP)] = { effect = "poison", power = 7 },
  -- Moonbell's own aspect is dream-fog, so concentrating it addles the
  -- brewer's own mind rather than anyone else's - the same "own aspect
  -- turned inward" shape as every other same-herb pair above. Sunlight is
  -- the one aspect it outright opposes (wakeful day versus dreaming night,
  -- the same shape as sunpetal/nightcap's light-versus-shade curdle above),
  -- so that pairing curdles instead of brewing.
  [pairKey(Alchemy.MOONBELL, Alchemy.MOONBELL)] = { effect = "confuse" },
  [pairKey(Alchemy.SUNPETAL, Alchemy.MOONBELL)] = CURDLE,
  [pairKey(Alchemy.BLOODROOT, Alchemy.MOONBELL)] = { effect = "clarity" },
  [pairKey(Alchemy.EMBERLEAF, Alchemy.MOONBELL)] = { effect = "blind" },
  [pairKey(Alchemy.FROSTMOSS, Alchemy.MOONBELL)] = { effect = "levitate" },
  [pairKey(Alchemy.NIGHTCAP, Alchemy.MOONBELL)] = { effect = "poison", power = 6 },
}

function Alchemy.herb(key)
  return { kind = Items.HERB, herb = key, name = Alchemy.names[key] .. " herb", glyph = ";" }
end

-- The fixed outcome for brewing herbA with herbB together, order
-- independent. Returns nil only when either key names no known herb.
function Alchemy.lookup(herbA, herbB)
  if not Alchemy.names[herbA] or not Alchemy.names[herbB] then return nil end
  return Alchemy.recipes[pairKey(herbA, herbB)]
end

-- Resolves a completed brew into a fresh potion item, or (nil, "curdle") for
-- an opposed pairing - the caller decides what a curdle does to the brewer.
function Alchemy.brew(herbA, herbB)
  local recipe = Alchemy.lookup(herbA, herbB)
  if not recipe then return nil, "unknown herb" end
  if recipe.curdle then return nil, "curdle" end
  return Items.potionOf(recipe.effect, recipe.power)
end

return Alchemy
