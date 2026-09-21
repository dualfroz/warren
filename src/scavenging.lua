local Corpses = require("corpses")
local Alchemy = require("alchemy")
local Monsters = require("monsters")
local Factions = require("factions")

local Scavenging = {}

Scavenging.HERB_BY_FACTION = {
  [Factions.VERMIN] = Alchemy.NIGHTCAP,
  [Factions.GOBLINOID] = Alchemy.BLOODROOT,
  [Factions.ORCISH] = Alchemy.BLOODROOT,
  [Factions.BEAST] = Alchemy.EMBERLEAF,
  [Factions.CULT] = Alchemy.NIGHTCAP,
  [Factions.DRAKE] = Alchemy.EMBERLEAF,
  [Factions.BANDIT] = Alchemy.SUNPETAL,
  [Factions.MERCHANT] = Alchemy.SUNPETAL,
}

function Scavenging.herbFor(corpse)
  local spec = Monsters.byKey[corpse.species]
  local faction = spec and spec.faction
  return faction and Scavenging.HERB_BY_FACTION[faction]
end

function Scavenging.harvest(game, corpse)
  if Corpses.isRotten(corpse) then
    return false, "the corpse has rotted too far to yield anything worth carving"
  end
  local herbKey = Scavenging.herbFor(corpse)
  if not herbKey then
    return false, "there is nothing worth carving from this corpse"
  end
  Corpses.remove(game.level, corpse)
  local herb = Alchemy.herb(herbKey)
  game.player.inventory[#game.player.inventory + 1] = herb
  return true, string.format("you carve a %s from the %s corpse", herb.name, corpse.name)
end

return Scavenging
