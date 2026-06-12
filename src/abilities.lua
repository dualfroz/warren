-- Species-level passive and death-triggered abilities layered on top of the
-- generic AI behaviours in ai.lua. Declared per species in Monsters.species
-- so a bestiary entry fully describes what a creature does, not just how
-- hard it hits or how it moves.

local Status = require("status")
local Items = require("items")
local Los = require("los")
local Combat = require("combat")
local Durability = require("durability")
local Momentum = require("momentum")

local Abilities = {}

-- Regeneration: heals `monster.regen` hp at the start of its turn, unless it
-- is actively burning - fire cauterizes the wound faster than it closes.
-- Runs after Status.tick so a fresh burn this same turn still suppresses it.
function Abilities.regenTick(monster)
  local amount = monster.regen
  if not amount or not monster:isAlive() then return nil end
  if Status.has(monster, Status.BURNING) then return nil end
  local before = monster.hp
  monster.hp = math.min(monster.maxHp, monster.hp + amount)
  if monster.hp == before then return nil end
  return string.format("%s knits its wounds for %d", monster.name, monster.hp - before)
end

-- On-death bursts: some species release a parting effect on whatever is
-- adjacent to their corpse - including the player - the instant they die.
-- Keyed by the `onDeath` tag on the species, run from Game:awardKill so the
-- burst fires no matter what finished the monster off (melee, spell, thrown
-- weapon, or a status effect ticking it down).
local bursts = {
  spores = function(game, monster)
    local hit = {}
    local targets = { game.player }
    for _, other in ipairs(game:currentEntities()) do targets[#targets + 1] = other end
    for _, victim in ipairs(targets) do
      if victim ~= monster and victim:isAlive()
        and math.abs(victim.x - monster.x) <= 1 and math.abs(victim.y - monster.y) <= 1 then
        Status.apply(victim, Status.POISON, 4, 2)
        hit[#hit + 1] = victim.name
      end
    end
    if #hit == 0 then return nil end
    return string.format("a burst of spores poisons %s", table.concat(hit, ", "))
  end,
}

function Abilities.onDeath(game, monster)
  local burst = monster.onDeath and bursts[monster.onDeath]
  if not burst then return nil end
  return burst(game, monster)
end

-- Turn-start special abilities, keyed by the `ability` tag on the species
-- (Monsters.species) and stamped onto the entity at creation. Abilities.tryAct
-- runs from Game:takeMonsterTurn BEFORE the plain ai.lua behaviour: when it
-- fires it consumes the whole turn and the caller must skip Ai.act; when it
-- returns false the monster falls through to its ordinary ai tag unchanged.
-- Range/cooldown constants live here, not on the species, mirroring how
-- `bursts` above centralises onDeath behaviour by tag rather than by species.

local RANGE = { summon = 6, curse = 5, heal = 5, shriek = 5 }
local COOLDOWN = { summon = 6, curse = 4, heal = 5, rally = 8, shriek = 6 }
local MAX_SUMMONED = 2

local EIGHT_DIRS = {
  { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
  { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

-- The first free, unoccupied, walkable cell next to (x, y), scanning a fixed
-- direction order so results are deterministic for a given map state.
local function freeAdjacent(game, x, y)
  for _, dir in ipairs(EIGHT_DIRS) do
    local nx, ny = x + dir[1], y + dir[2]
    if game.level.map:isWalkable(nx, ny) and not game.level:entityAt(nx, ny)
      and not (nx == game.player.x and ny == game.player.y) then
      return nx, ny
    end
  end
  return nil
end

function Abilities.tickCooldown(monster)
  if monster.cooldown and monster.cooldown > 0 then
    monster.cooldown = monster.cooldown - 1
  end
end

-- Necromancer-style ability: raises a fresh minion of `summonSpecies` beside
-- itself, tagged `summonedBy` so the population cap only counts its own brood.
local function trySummon(game, monster)
  if not game:canSeePlayer(monster, RANGE.summon) then return false end
  local count = 0
  for _, other in ipairs(game.level.entities) do
    if other:isAlive() and other.summonedBy == monster.id then count = count + 1 end
  end
  if count >= MAX_SUMMONED then return false end
  local x, y = freeAdjacent(game, monster.x, monster.y)
  if not x then return false end
  local minion = game:spawnMinion(monster.summonSpecies, x, y)
  minion.summonedBy = monster.id
  monster.cooldown = COOLDOWN.summon
  return true, string.format("%s calls forth a %s", monster.name, minion.name)
end

-- Shaman-style ability: a ranged bolt that both hurts and weakens the player,
-- withheld at point-blank range so the caster's ai (flee) kites instead. The
-- hurt half runs through the exact same Combat.damage the melee/shoot paths
-- use - mitigated by the player's defense and resistances, breaking Momentum
-- (see momentum.lua's own "claw, breath or ambush" wording - a curse bolt is
-- none of those by name but is that in shape) and wearing armor exactly like
-- monsterShoot's breath already does - rather than a flat, unmitigated
-- subtraction none of that pipeline ever saw.
local function tryCurse(game, monster)
  if game:playerAdjacent(monster) then return false end
  if not game:canSeePlayer(monster, RANGE.curse) or not game:hasClearShot(monster) then
    return false
  end
  local dealt = Combat.damage(monster, game.player, 1)
  game.player.hp = game.player.hp - dealt
  Momentum.onDamaged(game.player)
  local broke = Durability.wearArmor(game.player)
  if broke then game.log:add(broke) end
  Status.apply(game.player, Status.WEAKEN, 6, 3)
  monster.cooldown = COOLDOWN.curse
  return true, string.format("%s curses you for %d", monster.name, dealt)
end

-- Banshee-style ability: a ranged wail that blinds instead of hurting,
-- withheld point-blank exactly like tryCurse so the caster's own "flee" ai
-- keeps it at kiting distance rather than trading blows. Status.BLIND
-- (game.lua's Game:effectiveRadius) was previously only ever inflicted BY
-- the player - a thrown potion, the blind spell, or a shared trap effect -
-- never the other way around; this is the first hostile source of it, the
-- same gap tryShriek's sibling "curse" would leave for WEAKEN if a monster
-- could apply it but nothing here ever did. Duration outlasts the cooldown
-- by one turn on purpose (5 vs 6) so a banshee left free to keep casting
-- keeps you blind almost the whole encounter but not with zero window - the
-- one turn of clear sight between wails is a player's chance to reposition
-- or close the distance before the next howl lands.
local function tryShriek(game, monster)
  if game:playerAdjacent(monster) then return false end
  if not game:canSeePlayer(monster, RANGE.shriek) or not game:hasClearShot(monster) then
    return false
  end
  Status.apply(game.player, Status.BLIND, 5, 1)
  monster.cooldown = COOLDOWN.shriek
  return true, string.format("%s's wail blinds you", monster.name)
end

