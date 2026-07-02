-- A mimic disguises itself as ordinary loot until a hand reaches for it.
-- Builder.build drops one as a plain floorItem tagged `mimic = true`,
-- wearing a random disguise's name and glyph (Mimics.DISGUISES) - utterly
-- indistinguishable at rest from a real item, since render.lua and
-- Game:pickupHere both just read an ordinary floorItem's own `.item.glyph`
-- and `.item.name`, with no idea a given tile might be a trap. The instant
-- the player steps onto it (Game:triggerMimic, called from pickupHere),
-- Mimics.reveal builds the real hostile monster underneath, scaled by
-- depth the same way Monsters.create scales a wild species's hp, and gets
-- one free ambush swing in (via combat.lua, so it still respects the
-- player's defense and resistances) before it settles into an ordinary
-- chase like any other monster on its own turns from then on.

local Entity = require("entity")
local Factions = require("factions")

local Mimics = {}

Mimics.FACTION = Factions.BEAST

Mimics.DISGUISES = {
  { name = "a weathered chest", glyph = "=" },
  { name = "a glinting pile of gold", glyph = "$" },
  { name = "an ornate tome", glyph = "&" },
  { name = "a discarded shield", glyph = "[" },
}

-- The inert floorItem a builder drops: it looks exactly like whichever
-- disguise it rolled until Game:pickupHere unmasks it.
function Mimics.floorItem(rng)
  local disguise = Mimics.DISGUISES[rng:range(1, #Mimics.DISGUISES)]
  return { kind = "mimic", mimic = true, name = disguise.name, glyph = disguise.glyph }
end

-- The hostile monster a disguised item becomes the instant it is
-- disturbed, its hp scaled by depth exactly the way Monsters.create scales
-- a wild species's own base hp.
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

-- Flat xp reward for felling a revealed mimic - kept separate from
-- Monsters.xpFor since a mimic is never a member of the wild bestiary
-- Monsters.forDepth draws its ordinary per-floor population from.
function Mimics.xpFor()
  return 10
end

return Mimics
