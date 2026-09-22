local Items = require("items")

local Alchemy = {}

Alchemy.SUNPETAL = "sunpetal"
Alchemy.BLOODROOT = "bloodroot"
Alchemy.EMBERLEAF = "emberleaf"
Alchemy.FROSTMOSS = "frostmoss"
Alchemy.NIGHTCAP = "nightcap"
Alchemy.MOONBELL = "moonbell"

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

local function pairKey(a, b)
  if a > b then a, b = b, a end
  return a .. "+" .. b
end
Alchemy.pairKey = pairKey

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
  [pairKey(Alchemy.MOONBELL, Alchemy.MOONBELL)] = { effect = "confuse" },
  [pairKey(Alchemy.SUNPETAL, Alchemy.MOONBELL)] = CURDLE,
  [pairKey(Alchemy.BLOODROOT, Alchemy.MOONBELL)] = { effect = "clarity" },
  [pairKey(Alchemy.EMBERLEAF, Alchemy.MOONBELL)] = { effect = "blind" },
  [pairKey(Alchemy.FROSTMOSS, Alchemy.MOONBELL)] = { effect = "levitate" },
  [pairKey(Alchemy.NIGHTCAP, Alchemy.MOONBELL)] = { effect = "poison", power = 6 },
}

function Alchemy.herb(key)
  return { kind = Items.HERB, herb = key, name = Alchemy.names[key] .. " herb", glyph = Items.glyphs[Items.HERB] }
end

function Alchemy.lookup(herbA, herbB)
  if not Alchemy.names[herbA] or not Alchemy.names[herbB] then return nil end
  return Alchemy.recipes[pairKey(herbA, herbB)]
end

function Alchemy.brew(herbA, herbB)
  local recipe = Alchemy.lookup(herbA, herbB)
  if not recipe then return nil, "unknown herb" end
  if recipe.curdle then return nil, "curdle" end
  return Items.potionOf(recipe.effect, recipe.power)
end

return Alchemy
