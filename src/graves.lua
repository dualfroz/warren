local Entity = require("entity")
local Factions = require("factions")

local Graves = {}

Graves.MAX_RECORDED = 20
Graves.markerGlyph = "|"
Graves.shadeGlyph = "i"

function Graves.record(meta, entry)
  meta.graves = meta.graves or {}
  table.insert(meta.graves, 1, entry)
  while #meta.graves > Graves.MAX_RECORDED do
    table.remove(meta.graves)
  end
end

function Graves.eligibleFor(graves, depth)
  local eligible = {}
  if not graves then return eligible end
  for _, grave in ipairs(graves) do
    if grave.depth >= depth then eligible[#eligible + 1] = grave end
  end
  return eligible
end

function Graves.floorItem(grave)
  return {
    kind = "grave", grave = true, name = "a weathered grave marker", glyph = Graves.markerGlyph,
    graveClass = grave.className, graveGold = grave.gold, graveEssence = grave.essence,
  }
end

function Graves.reveal(id, x, y, ground)
  local gold = ground.graveGold or 0
  local essence = ground.graveEssence or 0
  local wealth = gold + essence * 2
  local bonusHp = math.min(20, wealth // 8)
  local bonusAttack = math.min(6, wealth // 30)
  local entity = Entity.new({
    id = id, x = x, y = y,
    glyph = Graves.shadeGlyph, name = "vengeful shade", kind = "monster",
    species = "shade", ai = "chase",
    hp = 10 + bonusHp, maxHp = 10 + bonusHp,
    attack = 4 + bonusAttack, defense = 1, speed = 105,
  })
  entity.cooldown = 0
  entity.faction = Factions.UNDEAD
  entity.grave = true
  entity.graveClass = ground.graveClass
  entity.graveGold = gold
  entity.graveEssence = essence
  return entity
end

function Graves.xpFor()
  return 12
end

function Graves.lootFor(entity)
  local gold = (entity.graveGold or 0) // 2
  local essence = (entity.graveEssence or 0) // 3
  return gold, essence
end

return Graves
