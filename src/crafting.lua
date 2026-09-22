local Items = require("items")
local Status = require("status")
local Affixes = require("affixes")

local Crafting = {}

Crafting.FIRE = "fire"
Crafting.FROST = "frost"
Crafting.SHOCK = "shock"
Crafting.VENOM = "venom"

Crafting.elements = { Crafting.FIRE, Crafting.FROST, Crafting.SHOCK, Crafting.VENOM }

Crafting.riders = {
  [Crafting.FIRE]  = { status = Status.BURNING, duration = 3, potency = 2 },
  [Crafting.FROST] = { status = Status.SLOW,    duration = 2, potency = 1 },
  [Crafting.SHOCK] = { status = Status.STUN,    duration = 2, potency = 1 },
  [Crafting.VENOM] = { status = Status.POISON,  duration = 4, potency = 2 },
}

Crafting.tierNames = { "chip", "flawed", "perfect" }
Crafting.MAX_TIER = #Crafting.tierNames

Crafting.FORGE_COST = 6
Crafting.ENCHANT_COST = 10
Crafting.TEMPER_MAX = 5

local function isElement(element)
  return Crafting.riders[element] ~= nil
end

function Crafting.gem(element, tier)
  return {
    kind = Items.GEM,
    glyph = Items.glyphs[Items.GEM],
    element = element,
    tier = tier,
    power = tier,
    name = Crafting.tierNames[tier] .. " " .. element .. " gem",
  }
end

function Crafting.essenceFor(xp)
  return math.max(1, xp // 3)
end

function Crafting.forge(entity, element)
  if not isElement(element) then return false, "no such element" end
  if entity.essence < Crafting.FORGE_COST then return false, "not enough essence" end
  entity.essence = entity.essence - Crafting.FORGE_COST
  return true, Crafting.gem(element, 1)
end

function Crafting.mergeGems(gemA, gemB)
  if gemA.element ~= gemB.element then return false, "elements do not match" end
  if gemA.tier ~= gemB.tier then return false, "tiers do not match" end
  if gemA.tier >= Crafting.MAX_TIER then return false, "already at maximum tier" end
  return true, nil, Crafting.gem(gemA.element, gemA.tier + 1)
end

local function socketable(item)
  return item.kind == Items.WEAPON or item.kind == Items.ARMOR
    or item.kind == Items.BOW or item.kind == Items.RING
end

local function applyPowerDelta(entity, item, delta)
  if delta == 0 then return end
  if entity.weapon == item then
    entity.attack = entity.attack + delta
  elseif entity.armor == item then
    entity.defense = entity.defense + delta
  end
end

function Crafting.socket(entity, item, gem)
  if not socketable(item) then return false, "cannot be socketed" end
  if gem.kind ~= Items.GEM then return false, "not a gem" end
  local previousPower = item.socket and item.socket.power or 0
  item.socket = { element = gem.element, tier = gem.tier, power = gem.power, onHit = Crafting.riders[gem.element] }
  if item.kind == Items.WEAPON or item.kind == Items.ARMOR then
    local delta = gem.power - previousPower
    item.power = item.power + delta
    applyPowerDelta(entity, item, delta)
  end
  return true
end

function Crafting.temperCost(item)
  return ((item.temper or 0) + 1) * 4
end

function Crafting.temper(entity, item)
  if item.kind ~= Items.WEAPON and item.kind ~= Items.ARMOR then
    return false, "cannot be tempered"
  end
  local level = item.temper or 0
  if level >= Crafting.TEMPER_MAX then return false, "fully tempered" end
  local cost = Crafting.temperCost(item)
  if entity.essence < cost then return false, "not enough essence" end
  entity.essence = entity.essence - cost
  item.temper = level + 1
  item.power = item.power + 1
  applyPowerDelta(entity, item, 1)
  return true
end

local function affixPool(item)
  if item.kind == Items.WEAPON then return Affixes.weapon end
  if item.kind == Items.ARMOR then return Affixes.armor end
  return nil
end

function Crafting.enchant(entity, item, affixKey)
  local pool = affixPool(item)
  if not pool then return false, "cannot be enchanted" end
  if item.affix then return false, "already bears an affix" end
  local chosen
  for _, entry in ipairs(pool) do
    if entry.key == affixKey then chosen = entry end
  end
  if not chosen then return false, "unknown affix" end
  if entity.essence < Crafting.ENCHANT_COST then return false, "not enough essence" end
  entity.essence = entity.essence - Crafting.ENCHANT_COST
  Affixes.decorate(item, chosen)
  applyPowerDelta(entity, item, chosen.power)
  return true
end

function Crafting.disenchant(entity, item)
  if not item.affix then return false, "nothing to disenchant" end
  local affix = item.affix
  local refund = Crafting.FORGE_COST + affix.power * 3
  applyPowerDelta(entity, item, -affix.power)
  item.power = item.power - affix.power
  local prefix = affix.name .. " "
  if item.name:sub(1, #prefix) == prefix then
    item.name = item.name:sub(#prefix + 1)
  end
  item.affix = nil
  item.damageType = nil
  entity.essence = entity.essence + refund
  return true, refund
end

return Crafting
