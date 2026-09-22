local Entity = require("entity")
local Factions = require("factions")
local Items = require("items")

local Mimics = {}

Mimics.FACTION = Factions.BEAST

Mimics.DISGUISES = {
  { name = "a weathered chest", glyph = "B" },
  { name = "a glinting pile of gold", glyph = Items.glyphs[Items.GOLD] },
  { name = "an ornate tome", glyph = Items.glyphs[Items.TOME] },
  { name = "a discarded shield", glyph = Items.glyphs[Items.ARMOR] },
}

function Mimics.floorItem(rng)
  local disguise = Mimics.DISGUISES[rng:range(1, #Mimics.DISGUISES)]
  return { kind = "mimic", mimic = true, name = disguise.name, glyph = disguise.glyph }
end

function Mimics.reveal(id, x, y, depth)
  local bonusHp = depth - 1
  local entity = Entity.new({
    id = id, x = x, y = y,
    glyph = "M", name = "mimic", kind = "monster",
    species = "mimic", ai = "chase",
    hp = 12 + bonusHp, maxHp = 12 + bonusHp,
    attack = 5, defense = 1, speed = 100,
  })
  entity.cooldown = 0
  entity.faction = Mimics.FACTION
  entity.mimic = true
  return entity
end

function Mimics.xpFor()
  return 10
end

return Mimics
