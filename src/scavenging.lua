-- A third way to spend a fresh corpse, alongside Game:butcherCorpse's meal
-- and Game:raiseCorpse's thrall: carving it for the herb its own kind
-- carries rather than for food or an undead ally, so a cauldron (see
-- alchemy.lua) can draw on combat itself and not only on whatever the floor
-- happened to scatter. Every wild faction maps to a fixed herb, so the same
-- species always yields the same ingredient no matter which floor or seed
-- felled it - a goblinoid's crude poultice weed is always bloodroot, a
-- drake's scorched hide is always emberleaf. A corpse already past its rot
-- threshold (see Corpses.isRotten) has nothing left worth carving, and one
-- left behind by anything without a bestiary entry - a bonded companion or
-- a hired ally, never a wild monster - carries no herb at all; the corpse
-- itself is spent either way it fails, exactly like Corpses.butcher's own
-- certain trade, this is a deliberate trade the autopilot never makes on
-- its own (see Game:scavengeCorpse), the same way it never raises one.

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

-- The herb key `corpse` would yield, or nil when its species is unknown to
-- the bestiary (a companion's or hireling's own remains) or belongs to a
-- faction (UNDEAD is the only one) with nothing mapped above - moot in
-- practice since Corpses.leavesCorpse already refuses the undead a corpse
-- at all, kept here only so an unmapped faction fails closed rather than
-- erroring.
function Scavenging.herbFor(corpse)
  local spec = Monsters.byKey[corpse.species]
  local faction = spec and spec.faction
  return faction and Scavenging.HERB_BY_FACTION[faction]
end

-- Carves `corpse` for its herb instead of food, spending it in one stroke.
-- Refuses without spending anything when the corpse has already rotted past
-- use or its species yields no known herb; returns (false, reason) in
-- either case so a caller never has to re-derive why.
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
