-- Turn orchestration built on an energy scheduler: the world advances actor by
-- actor until the player is due, the player acts, and the cycle repeats. Owns
-- the dungeon, the player, identification and the message log, and drives the
-- headless autopilot that descends the dungeon deterministically.

local Rng = require("rng")
local Tiles = require("tiles")
local Astar = require("astar")
local Los = require("los")
local Light = require("light")
local Combat = require("combat")
local Items = require("items")
local Shop = require("shop")
local Effects = require("effects")
local Status = require("status")
local Identify = require("identify")
local Builder = require("builder")
local Dungeon = require("dungeon")
local Entity = require("entity")
local MessageLog = require("messagelog")
local Scheduler = require("scheduler")
local Ai = require("ai")
local SaveGame = require("savegame")
local Render = require("render")
local Progression = require("progression")
local Monsters = require("monsters")
local Spells = require("spells")
local Throwing = require("throwing")
local Ranged = require("ranged")
local Abilities = require("abilities")
local Hazards = require("hazards")
local Terrain = require("terrain")
local Shrines = require("shrines")
local Classes = require("classes")
local Skills = require("skills")
local Crafting = require("crafting")
local Companions = require("companions")
local Mercenaries = require("mercenaries")
local Artifacts = require("artifacts")
local Sets = require("sets")
local Hunger = require("hunger")
local Mimics = require("mimics")
local Bosses = require("bosses")
local Phases = require("phases")
local Quests = require("quests")
local Meta = require("meta")
local Alchemy = require("alchemy")
local Resistances = require("resistances")
local Factions = require("factions")
local Encumbrance = require("encumbrance")
local Elites = require("elites")
local Vaults = require("vaults")
local Runewords = require("runewords")
local Atmosphere = require("atmosphere")
local Events = require("events")
local Stealth = require("stealth")
local Compendium = require("compendium")
local Nodes = require("nodes")
local Curses = require("curses")
local Momentum = require("momentum")
local Corpses = require("corpses")
local Digging = require("digging")
local Sanity = require("sanity")
local Graves = require("graves")
local Proficiency = require("proficiency")
local Ascension = require("ascension")
local Durability = require("durability")
local Conductivity = require("conductivity")
local Disarm = require("disarm")
local Reanimation = require("reanimation")
local Secrets = require("secrets")
local Chests = require("chests")
local Nemesis = require("nemesis")
local Scavenging = require("scavenging")
local Infighting = require("infighting")
local Blocks = require("blocks")
local Noise = require("noise")
local Disease = require("disease")
local Captives = require("captives")
local Level = require("level")
local Horde = require("horde")
local Branches = require("branches")
local Commands = require("commands")

-- Real feature history, oldest first, matching the fields Game.fromData
-- below has always had to guard with "or" because they arrived after the
-- original snapshot shape: essence and the vault/set-piece tallies, then the
-- skill tree and reputation, then sanity. A run save from before any of
-- those landed is missing exactly the fields each step below fills in.
local GameSave = SaveGame.new({
  [1] = function(data)
    data.playerExtra.essence = data.playerExtra.essence or 0
    data.stats = data.stats or { kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0 }
    data.stats.vaultsOpened = data.stats.vaultsOpened or 0
    data.stats.setPiecesFound = data.stats.setPiecesFound or 0
    return data
  end,
  [2] = function(data)
    data.playerExtra.skills = data.playerExtra.skills or {}
    data.playerExtra.skillPoints = data.playerExtra.skillPoints or 0
    data.playerExtra.skillCooldowns = data.playerExtra.skillCooldowns or {}
    data.playerExtra.reputation = data.playerExtra.reputation or {}
    return data
  end,
  [3] = function(data)
    data.playerExtra.sanity = data.playerExtra.sanity or Sanity.MAX
    return data
  end,
})

local Game = {}
Game.__index = Game

local FOV_RADIUS = 8

-- Which equip slot each wearable item kind occupies, used to check a slot
-- for a bound curse before letting a new piece take its place.
local slotByItemKind = {
  [Items.WEAPON] = "weapon", [Items.ARMOR] = "armor",
  [Items.RING] = "ring", [Items.BOW] = "bow",
}

local function sign(n)
  if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end
end

function Game.new(seed, options)
  local game = setmetatable({}, Game)
  game.seed = seed
  game.rng = Rng.new(seed)
  game.depth = 1
  game.turn = 0
  game.won = false
  game.log = MessageLog.new(32)
  game.identify = Identify.new(game.rng)
  game.dungeon = Dungeon.new(seed, options)
  game.maxDepth = Builder.maxDepth(options)
  game.level = game.dungeon:get(1)
  game.player = Entity.new({
    id = 0, x = game.level.upX, y = game.level.upY,
    glyph = "@", name = "you", kind = "player",
    hp = 30, maxHp = 30, attack = 5, defense = 1, speed = 100,
  })
  game.player.satiation = Hunger.START
  game.player.sanity = Sanity.MAX
  game.player.gold = 20
  game.player.essence = 0
  game.player.light = { fuel = 400, radius = 8 }
  game.player.level = 1
  game.player.xp = 0
  game.player.xpNext = Progression.xpToNext(1)
  game.player.mana = 10
  game.player.maxMana = 10
  game.player.spellsKnown = { "missile" }
  game.player.inventory = {
    Items.potion(10), Items.potion(10), Items.food("ration", 400), Items.scroll("mapping"),
  }
  game.player.skills = {}
  game.player.skillPoints = 1
  game.player.skillCooldowns = {}
  game.player.reputation = {}
  game.deepestDepth = 1
  game.stats = {
    kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, vaultsOpened = 0,
    setPiecesFound = 0, chestsOpened = 0,
  }
  if options and options.meta then
    Meta.applyAll(options.meta, game.player)
    -- Reuses options.meta's own table (rather than copying it) so every
    -- sighting/kill recorded mid-run is already sitting in the table
    -- warren.lua writes back out with Meta.save at the end of the run.
    options.meta.compendium = options.meta.compendium or Compendium.new()
    game.compendium = options.meta.compendium
  else
    game.compendium = Compendium.new()
  end
  if options and options.class and Classes.isValid(options.class) then
    Classes.apply(game.player, options.class)
  end
  game.ascension = Ascension.resolve(options and options.meta, options and options.mutators)
  Ascension.applyToPlayer(game.ascension, game.player)
  game.visible = {}
  game.monsterSeq = 0
  game.nemesis = nil
  game:computeVisible()
  return game
end

-- Snapshot fed to meta.lua at the end of a run (see warren.lua's --meta
-- flag): everything Meta.renownFor and every achievement condition read,
-- gathered in one place so neither has to know Game's own field names.
function Game:metaStats()
  return {
    deepestDepth = self.deepestDepth,
    kills = self.stats.kills,
    bossKills = self.stats.bossKills,
    questsCompleted = self.stats.questsCompleted,
    artifactsFound = self.stats.artifactsFound,
    vaultsOpened = self.stats.vaultsOpened,
    setPiecesFound = self.stats.setPiecesFound,
    chestsOpened = self.stats.chestsOpened,
    won = self.won,
    mutators = self.ascension,
  }
end

-- The grave this run leaves behind for a future one to stumble across (see
-- graves.lua and Builder's options.graves): only warren.lua's --meta path
-- ever calls this, and only once a run has actually ended in death -
-- winning walks out with the Amulet, not a grave. className falls back to
-- "wanderer" for a run that never picked a class at all.
function Game:graveEntry()
  return {
    className = self.player.class or "wanderer",
    depth = self.deepestDepth,
    gold = self.player.gold,
    essence = self.player.essence,
    turn = self.turn,
  }
end

-- Fresh id for a monster spawned mid-game (summon, split), disjoint from the
-- small sequential ids the builder hands out at level generation.
function Game:nextMonsterId()
  self.monsterSeq = self.monsterSeq + 1
  return 100000 + self.monsterSeq
end

function Game:spawnMinion(speciesKey, x, y)
  local spec = Monsters.byKey[speciesKey]
  local minion = Monsters.create(spec, self:nextMonsterId(), x, y, self.depth)
  -- Summoned or split mid-fight, so it is already aware rather than asleep -
  -- see stealth.lua's header for why builder-placed wild monsters differ.
  minion.awareness = Stealth.HUNTING
  self.level.entities[#self.level.entities + 1] = minion
  return minion
end

function Game:currentEntities()
  return self.level.entities
end

function Game:effectiveRadius()
  local radius = FOV_RADIUS
  if self.level.dark then
    radius = self.player.light.fuel > 0 and self.player.light.radius or 2
  end
  radius = radius - Atmosphere.sightPenalty(self.level.weather) - Events.sightPenalty(self.level.event)
    - Ascension.sightPenalty(self.ascension)
  if radius < 1 then radius = 1 end
  -- Blindness overrides every other light/weather/mutator term rather than
  -- stacking with them: a blinded player run through with a full lantern in
  -- clear weather still can't see past their own hand.
  if Status.has(self.player, Status.BLIND) then radius = 1 end
  return radius
end

-- Folds events.lua's level-scoped monster damage swing together with
-- whatever ascension.lua mutators the player opted into for this run, read
-- live at the point a monster actually lands a hit (Game:monsterMelee,
-- Game:monsterShoot, Game:triggerMimic and Game:triggerGrave's ambush
-- swings) rather than baked into any monster's own stats.
function Game:monsterDamageMultiplier()
  return Events.monsterDamageMultiplier(self.level.event) * Ascension.damageMultiplier(self.ascension)
end

-- Folds events.lua's rich-veins swing together with ascension.lua's own
-- essence mutators, read live wherever essence is actually credited
-- (Game:awardKill, Nodes.harvest).
function Game:essenceMultiplier()
  return Events.essenceMultiplier(self.level.event) * Ascension.essenceMultiplier(self.ascension)
end

function Game:computeVisible()
  self.visible = Light.compute(self.level.map, self.player.x, self.player.y,
    self:effectiveRadius(), self.level.lights)
  for idx in pairs(self.visible) do
    self.level:markExplored(idx)
  end
  self:noteSightings()
end

-- Records every currently-visible living monster's species into the
-- compendium (see compendium.lua) - silent bookkeeping, never touches the
-- message log, so it cannot perturb anything that reads recent log lines.
function Game:noteSightings()
  local map = self.level.map
  for _, entity in ipairs(self.level.entities) do
    if entity.kind == "monster" and entity:isAlive() and self.visible[map:index(entity.x, entity.y)] then
      Compendium.noteSighting(self.compendium, entity.species)
    end
  end
end

function Game:cleanupDead()
  self.level:removeDead()
end

function Game:hasKey()
  for _, item in ipairs(self.player.inventory) do
    if item.kind == Items.KEY then return true end
  end
  return false
end

function Game:hasAmulet()
  for _, item in ipairs(self.player.inventory) do
    if item.kind == Items.AMULET then return true end
  end
  return false
end

function Game:randomFloorCell()
  local map = self.level.map
  local cells = {}
  for y = 1, map.height do
    for x = 1, map.width do
      if map:isWalkable(x, y) and not self.level:entityAt(x, y)
        and not (x == self.player.x and y == self.player.y) then
        cells[#cells + 1] = { x = x, y = y }
      end
    end
  end
  if #cells == 0 then return nil end
  local pick = cells[self.rng:range(1, #cells)]
  return pick.x, pick.y
end

function Game:revealWholeLevel()
  local map = self.level.map
  for idx = 1, map.width * map.height do
    self.level:markExplored(idx)
  end
end

-- Monster-turn helpers used by the ai module.

function Game:playerAdjacent(monster)
  return math.abs(monster.x - self.player.x) + math.abs(monster.y - self.player.y) == 1
end

-- The player-aligned companion, hireling, or thrall standing right next to
-- `monster` (Manhattan-1, the same cardinal-only adjacency Game:playerAdjacent
-- itself uses), or nil if none is that close. A hostile monster whose only
-- route toward the player runs through a one-wide corridor an ally is
-- standing in cannot path around it (Game:stepMonsterToward's own
-- blockedForMonster treats any occupied non-goal cell as a wall), so without
-- this check every ai.lua pursuit behaviour just holds position forever once
-- it reaches that ally's doorstep - the ally becomes an unkillable, un-
-- fightable roadblock rather than the combatant Game:onActorDeath and the
-- companion/mercenary/thrall noise-emission work already treat it as. Ties
-- break toward the lower entity id, matching Game:nearestAlly's own rule.
function Game:adjacentAlly(monster)
  local best
  for _, other in ipairs(self.level.entities) do
    if other ~= monster and other:isAlive()
      and (other.kind == "companion" or other.kind == "hireling" or other.kind == "thrall")
      and math.abs(other.x - monster.x) + math.abs(other.y - monster.y) == 1
      and (not best or other.id < best.id) then
      best = other
    end
  end
  return best
end

function Game:canSeePlayer(monster, range)
  local penalty = Skills.detectionPenalty(self.player, self.level.dark)
  local effectiveRange = math.max(range - penalty, 0)
  -- A blinded monster can still feel the player out at melee range but loses
  -- every longer-ranged aggro/pack/flee/ranged check in ai.lua - the same
  -- clamp Game:effectiveRadius applies to a blinded player's own sight.
  if Status.has(monster, Status.BLIND) then effectiveRange = math.min(effectiveRange, 1) end
  local cheb = math.max(math.abs(monster.x - self.player.x), math.abs(monster.y - self.player.y))
  if cheb > effectiveRange then return false end
  return Los.clear(self.level.map, monster.x, monster.y, self.player.x, self.player.y)
end

function Game:hasClearShot(monster)
  return Los.clear(self.level.map, monster.x, monster.y, self.player.x, self.player.y)
end

function Game:monsterMelee(monster)
  if Skills.evades(self, self.player) then
    self.log:add(string.format("you evade %s's attack", monster.name))
    return
  end
  local outcome = Combat.attack(monster, self.player, self:monsterDamageMultiplier())
  Momentum.onDamaged(self.player)
  self.log:add(string.format("%s hits you for %d", monster.name, outcome.damage))
  local broke = Durability.wearArmor(self.player)
  if broke then self.log:add(broke) end
  self:applyEliteOnHit(monster, outcome.damage, self.player)
  local thorns = Artifacts.thornsAmount(self.player, outcome.damage)
  if thorns > 0 then
    -- Aegis of Embers "sears" its attacker by name and by log line, so this
    -- reflect is fire damage, not a bare stat subtraction - a fire-immune
    -- dragon (bestiary-real, reachable from depth 6) shrugs it off entirely,
    -- exactly like every other fire source in the engine already does.
    local dealt = Resistances.apply(monster, thorns, Resistances.FIRE)
    if dealt > 0 then
      monster.hp = monster.hp - dealt
      self.log:add(string.format("your armor sears %s for %d", monster.name, dealt))
      if not monster:isAlive() then self:awardKill(monster) end
    else
      self.log:add(string.format("your armor's embers wash harmlessly over %s", monster.name))
    end
  end
  if monster.biteDisease and self.player:isAlive() and self.rng:chance(1, 4) then
    if Disease.infect(self.player, monster.biteDisease) then
      self.log:add(string.format("%s's bite leaves you feeling ill", monster.name))
    end
  end
  self:emitNoise(monster.x, monster.y, Noise.MELEE)
end

-- A vampiric elite heals a portion of the damage it just dealt; a chilling
-- one leaves its status rider on the victim. Shared by melee and a ranged
-- shot so either delivery route triggers the same elite hooks - and, since
-- Infighting.strike resolves an elite fighting a rival monster or the
-- player's own companion/hireling/thrall through this same method, the log
-- line names the actual victim instead of always assuming it is the player.
function Game:applyEliteOnHit(attacker, dealt, victim)
  local lifesteal = Elites.lifestealFraction(attacker)
  if lifesteal > 0 then
    local healed = math.floor(dealt * lifesteal)
    if healed > 0 and attacker:isAlive() then
      attacker.hp = math.min(attacker.maxHp, attacker.hp + healed)
      local from = victim == self.player and "you" or victim.name
      self.log:add(string.format("%s drains %d hp from %s", attacker.name, healed, from))
    end
  end
  local rider = Elites.onHitRider(attacker)
  if rider and victim:isAlive() then
    Status.apply(victim, rider.status, rider.duration, rider.potency)
    local who = victim == self.player and "you" or victim.name
    self.log:add(string.format("%s's touch leaves %s %s", attacker.name, who, rider.status))
  end
end

function Game:monsterShoot(monster)
  local damageType = monster.breath == "fire" and Resistances.FIRE or Resistances.PHYSICAL
  local dealt = Combat.damage(monster, self.player, self:monsterDamageMultiplier(), damageType)
  self.player.hp = self.player.hp - dealt
  Momentum.onDamaged(self.player)
  self.log:add(string.format("%s shoots you for %d", monster.name, dealt))
  local broke = Durability.wearArmor(self.player)
  if broke then self.log:add(broke) end
  self:applyEliteOnHit(monster, dealt, self.player)
  if monster.breath == "fire" then
    if Resistances.tierOf(self.player, Resistances.FIRE) == Resistances.IMMUNE then
      self.log:add("the flames wash over you harmlessly")
    else
      Status.apply(self.player, Status.BURNING, 3, 2)
      self.log:add("the flames catch you alight")
    end
  end
end

local function blockedForMonster(game, self, goalX, goalY)
  return function(x, y)
    if x == goalX and y == goalY then return false end
    if not game.level.map:isWalkable(x, y) then return true end
    if game.level:blockAt(x, y) then return true end
    if x == game.player.x and y == game.player.y then return true end
    local occupant = game.level:entityAt(x, y)
    return occupant ~= nil and occupant ~= self
  end
end

-- Springs whatever untouched trap sits under `entity` after it has just
-- moved there - a player-planted trap kit harms a monster or companion
-- exactly as a builder-placed one harms the player, since both live in the
-- same level.traps list and share springTrap's resolution. A levitating
-- entity (Status.LEVITATE) drifts clear of the pressure plate entirely -
-- deliberately silent and without marking the trap revealed, unlike the
-- lava/chasm skip in checkTerrainFor: a hidden trap is information the
-- player never earned just by floating over it, so levitation buys safety
-- without also buying detection.
function Game:checkTrapFor(entity)
  if Status.has(entity, Status.LEVITATE) then return end
  local trap = self.level:trapAt(entity.x, entity.y)
  if trap and not trap.revealed then
    self:springTrap(trap, entity)
    if not entity:isAlive() then self:onActorDeath(entity) end
  end
end

-- A pit with no floor below it: the player falls to the next depth and
-- takes fall damage, a monster that blunders in is simply gone. Builder
-- never seeds a chasm on the final floor, so there is always a level below
-- to land on.
function Game:fallIntoChasm(entity)
  if entity == self.player then
    local dealt = 6 + self.rng:range(0, 6)
    self.player.hp = self.player.hp - dealt
    self.log:add(string.format("the floor gives way - you plunge into the dark for %d", dealt))
    if not self.player:isAlive() then return end
    self.depth = self.depth + 1
    self.level = self.dungeon:get(self.depth)
    local x, y = self:randomFloorCell()
    if not x then x, y = self.level.upX, self.level.upY end
    self.player.x, self.player.y = x, y
    if self.depth > self.deepestDepth then self.deepestDepth = self.depth end
    self:computeVisible()
  else
    entity.hp = 0
    self.log:add(string.format("%s plunges into the chasm and is gone", entity.name))
    self:onActorDeath(entity)
  end
end

-- Runs after entity has just come to rest on (dx, dy) from its previous
-- cell: ice keeps sliding it onward, lava burns it in place, and a chasm
-- ends the move altogether. Order matters - a slide can carry a traveller
-- straight off the ice and into whatever waits beyond it. A levitating
-- entity (Status.LEVITATE) never touches the ground at all, so it short
-- circuits every branch below - no slide, no burn, no fall - though it
-- still gets a log line when that skip actually mattered (standing over
-- lava or a chasm), since both are visible on the map and worth calling out.
function Game:checkTerrainFor(entity, dx, dy)
  if not entity:isAlive() then return end
  if Status.has(entity, Status.LEVITATE) then
    if self.level.map:get(entity.x, entity.y) == Tiles.LAVA or Terrain.isChasm(self.level, entity) then
      self.log:add(entity == self.player and "you drift safely over the hazard below"
        or string.format("%s drifts safely over the hazard below", entity.name))
    end
    return
  end
  if self.level.map:get(entity.x, entity.y) == Tiles.ICE then
    Terrain.slide(self.level, entity, dx, dy)
  end
  local line = Terrain.afflictLava(self.level, entity)
  if line then
    self.log:add(line)
    if not entity:isAlive() then
      if entity ~= self.player then self:onActorDeath(entity) end
      return
    end
  end
  if Terrain.isChasm(self.level, entity) then
    self:fallIntoChasm(entity)
  end
end

function Game:stepMonsterToward(monster, tx, ty)
  local path = Astar.find(self.level.map, monster.x, monster.y, tx, ty,
    blockedForMonster(self, monster, tx, ty))
  if path and #path >= 2 then
    local step = path[2]
    if self.level.map:isWalkable(step.x, step.y) and not self.level:entityAt(step.x, step.y)
      and not (step.x == self.player.x and step.y == self.player.y) then
      local dx, dy = step.x - monster.x, step.y - monster.y
      monster.x, monster.y = step.x, step.y
      self:checkTrapFor(monster)
      self:checkTerrainFor(monster, dx, dy)
    end
  end
end

local MONSTER_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Game:stepMonsterAway(monster, tx, ty)
  local current = math.abs(monster.x - tx) + math.abs(monster.y - ty)
  local best, bx, by = current, nil, nil
  for _, dir in ipairs(MONSTER_DIRS) do
    local nx, ny = monster.x + dir[1], monster.y + dir[2]
    if self.level.map:isWalkable(nx, ny) and not self.level:entityAt(nx, ny)
      and not (nx == self.player.x and ny == self.player.y) then
      local dist = math.abs(nx - tx) + math.abs(ny - ty)
      if dist > best then
        best, bx, by = dist, nx, ny
      end
    end
  end
  if bx then
    local dx, dy = bx - monster.x, by - monster.y
    monster.x, monster.y = bx, by
    self:checkTrapFor(monster)
    self:checkTerrainFor(monster, dx, dy)
  end
end

-- An erratic wanderer's random step or a confused chaser's overridden one
-- (Ai.act, both routed here) can land on an ally's cell exactly as easily as
-- the player's - Infighting.strike resolves that the same generic way
-- Game:adjacentAlly's own callers do, rather than the bump silently doing
-- nothing the way it would against an impassable wall.
function Game:moveMonster(monster, dx, dy)
  local nx, ny = monster.x + dx, monster.y + dy
  if nx == self.player.x and ny == self.player.y then
    self:monsterMelee(monster)
    return
  end
  local occupant = self.level:entityAt(nx, ny)
  if occupant and (occupant.kind == "companion" or occupant.kind == "hireling" or occupant.kind == "thrall") then
    Infighting.strike(self, monster, occupant)
    return
  end
  if self.level.map:isWalkable(nx, ny) and not occupant then
    monster.x, monster.y = nx, ny
    self:checkTrapFor(monster)
    self:checkTerrainFor(monster, dx, dy)
  end
end

-- Mirrors ai.lua's own Ai.act confusion stumble for the three player-aligned
-- actor kinds (companion/hireling/thrall). None of those ever dispatch
-- through Ai.act, so without this they would leave Status.CONFUSE completely
-- inert on them despite Game:springTrap and friends already applying it to
-- "any victim" regardless of kind. Returns true whenever the roll actually
-- fires (whether or not the stumble itself finds anywhere to go), so each
-- caller can `if game:allyActsConfused(ally) then return end` first thing,
-- exactly the precedence Ai.act gives the same roll over chase/pack/etc.
-- Unlike a confused monster's stumble (moveMonster above, which treats a
-- step onto the player's cell as an attack), a confused ally's stumble onto
-- its own master's cell is harmless - an ally never attacks the player it is
-- bonded or hired to protect, so that one direction is simply blocked like a
-- wall rather than routed into any melee helper.
function Game:allyActsConfused(ally)
  if not Status.has(ally, Status.CONFUSE) then return false end
  if not self.rng:chance(Status.CONFUSE_NUMERATOR, Status.CONFUSE_DENOMINATOR) then return false end
  local dir = MONSTER_DIRS[self.rng:range(1, #MONSTER_DIRS)]
  local nx, ny = ally.x + dir[1], ally.y + dir[2]
  if not (nx == self.player.x and ny == self.player.y)
    and self.level.map:isWalkable(nx, ny) and not self.level:entityAt(nx, ny) then
    ally.x, ally.y = nx, ny
    self:checkTrapFor(ally)
    self:checkTerrainFor(ally, dir[1], dir[2])
  end
  return true
end

-- A burrower's turn when it can neither reach nor see the player through
-- open floor: senses the player's general direction through solid rock out
-- to Digging.SENSE_RANGE away and, of the two candidate cells toward them
-- (longer axis first - see Digging.directionsToward), either claws one
-- swing into the first one that is still diggable, exactly like Game:dig
-- but toolless and self-directed, or - if open floor already leads that
-- way - simply steps there so it closes the distance before it ever needs
-- to swing at all. Idles once out of range or once neither candidate cell
-- is diggable nor walkable, the same way "flee" idles once it loses sight.
function Game:monsterDig(monster, tx, ty)
  local cheb = math.max(math.abs(monster.x - tx), math.abs(monster.y - ty))
  if cheb == 0 or cheb > Digging.SENSE_RANGE then return end
  for _, dir in ipairs(Digging.directionsToward(monster.x, monster.y, tx, ty)) do
    local nx, ny = monster.x + dir[1], monster.y + dir[2]
    if Digging.canDig(self.level.map, nx, ny) then
      self.log:add(Digging.swing(self, monster, nx, ny))
      if not monster:isAlive() then self:onActorDeath(monster) end
      return
    elseif self.level.map:isWalkable(nx, ny) and not self.level:entityAt(nx, ny)
      and not (nx == self.player.x and ny == self.player.y) then
      monster.x, monster.y = nx, ny
      self:checkTrapFor(monster)
      self:checkTerrainFor(monster, dir[1], dir[2])
      return
    end
  end
end

function Game:nearestAlly(monster)
  local best, ally = math.huge, nil
  for _, other in ipairs(self.level.entities) do
    if other ~= monster and other:isAlive() then
      local dist = math.abs(other.x - monster.x) + math.abs(other.y - monster.y)
      if dist < best or (dist == best and ally and other.id < ally.id) then
        best, ally = dist, other
      end
    end
  end
  return ally
end

-- A monster's death sweeps xp and essence to the player; a companion fights
-- for the player rather than yielding a reward for dying, so its death is
-- only logged and swept.
function Game:onActorDeath(actor)
  if actor.kind == "companion" then
    self.log:add("your " .. actor.name .. " falls")
    self:cleanupDead()
  elseif actor.kind == "hireling" then
    self.log:add("your " .. actor.name .. " falls")
    self:cleanupDead()
  elseif actor.kind == "thrall" then
    self.log:add("your " .. actor.name .. " crumbles back to bones")
    self:cleanupDead()
  else
    self:awardKill(actor)
  end
end

function Game:takeMonsterTurn(monster)
  self.log:addAll(Status.tick(monster))
  if not monster:isAlive() then
    self:onActorDeath(monster)
    return
  end
  Conductivity.tick(self.level, monster)
  local hazardLine = Hazards.afflict(self.level, monster)
  if hazardLine then self.log:add(hazardLine) end
  if not monster:isAlive() then
    self:onActorDeath(monster)
    return
  end
  -- Mirrors Game:hungerTorchTick's own Disease.tick(self.player) call - a
  -- disease is plain generic entity state (see disease.lua), and since
  -- Infighting.strike can now infect a rival monster or the player's own
  -- companion/hireling/thrall (not just the player), every non-player actor
  -- needs its own infection to actually progress on its turn too, or an
  -- infected ally would sit permanently incubating with no way to ever
  -- erupt, escalate, or be noticed.
  local diseaseLine = Disease.tick(monster)
  if diseaseLine then self.log:add(diseaseLine) end
  if not monster:isAlive() then
    self:onActorDeath(monster)
    return
  end
  local regenLine = Abilities.regenTick(monster)
  if regenLine then self.log:add(regenLine) end
  local enrageLine = Bosses.tryEnrage(monster)
  if enrageLine then self.log:add(enrageLine) end
  local phaseLine, phaseConsumedTurn = Phases.tick(self, monster)
  if phaseLine then self.log:add(phaseLine) end
  if not phaseConsumedTurn and not Status.skipsTurn(monster) then
    if monster.kind == "companion" then
      Companions.act(self, monster)
    elseif monster.kind == "hireling" then
      Mercenaries.act(self, monster)
    elseif monster.kind == "thrall" then
      Reanimation.act(self, monster)
    elseif Infighting.tryAct(self, monster) then
      -- A rivalry or a discorded mind has nothing to do with how this
      -- monster currently feels about the player: it fights regardless of
      -- wariness or - unlike Stealth.tick's own gating - whether it has
      -- otherwise noticed the player at all this turn.
    elseif Factions.isWary(self.player, monster) then
      -- A wary tribe member holds its ground: neither provoked nor hated
      -- into open hostility yet, it leaves the player be this turn.
    elseif Stealth.tick(self, monster) then
      Abilities.tickCooldown(monster)
      if not Abilities.tryAct(self, monster) then
        Ai.act(self, monster)
      end
    end
  end
  Scheduler.spend(monster)
  self:cleanupDead()
end

function Game:runToPlayer()
  while true do
    local actor = Scheduler.next(self)
    if actor == nil or actor == self.player then return end
    self:takeMonsterTurn(actor)
    if not self.player:isAlive() then return end
  end
end

-- Player actions.

-- Common tail of any player-caused kill: log it, grant the xp it was worth,
-- and sweep it off the level. Shared by melee and offensive spells so xp
-- always tracks a felled monster regardless of what felled it.
function Game:awardKill(target)
  self.log:add(target.name .. " dies")
  local burst = Abilities.onDeath(self, target)
  if burst then self.log:add(burst) end
  local eliteBurst = Elites.onDeath(self, target)
  if eliteBurst then self.log:add(eliteBurst) end
  self.stats.kills = self.stats.kills + 1
  if target.isBoss then self.stats.bossKills = self.stats.bossKills + 1 end
  Factions.registerKill(self.player, target)
  local xp = target.isBoss and Bosses.xpFor(target) or target.mimic and Mimics.xpFor()
    or target.grave and Graves.xpFor() or Monsters.xpFor(target)
  xp = xp + Elites.xpBonus(target, xp)
  if target.nemesis then xp = xp + Nemesis.xpBonus(target.nemesisGrudge or 1) end
  self.log:addAll(Progression.grantXp(self.player, xp))
  self.player.essence = self.player.essence + math.floor(Crafting.essenceFor(xp) * self:essenceMultiplier())
  Quests.registerKill(self.player, target.species)
  Compendium.noteKill(self.compendium, target.species)
  Corpses.spawn(self.level, target)
  self:resolveQuest()
  if target.isBoss then
    local loot = Bosses.lootFor(target)
    if loot then
      self.level.floorItems[#self.level.floorItems + 1] = { x = target.x, y = target.y, item = loot }
      self.log:add(string.format("%s drops %s", target.name, loot.name))
    end
  end
  if target.grave then
    local gold, essence = Graves.lootFor(target)
    if gold > 0 then
      self.player.gold = self.player.gold + gold
      self.log:add(string.format("the shade scatters %d gold as it fades", gold))
    end
    if essence > 0 then
      self.player.essence = self.player.essence + essence
    end
  end
  if target.nemesis then
    local bounty = Nemesis.bountyGold(target.nemesisGrudge or 1)
    self.player.gold = self.player.gold + bounty
    self.log:add(string.format("the hunt is over - you claim %d gold from %s", bounty, target.name))
    self.nemesis = nil
  end
  self:cleanupDead()
end

-- Applies a weapon's on-hit rider - rolled affix or socketed gem, or both -
-- to a still-living target, logging each status it lands.
function Game:applyWeaponRiders(weapon, target)
  if not (weapon and target:isAlive()) then return end
  local riders = {}
  if weapon.affix and weapon.affix.onHit then riders[#riders + 1] = weapon.affix.onHit end
  if weapon.socket and weapon.socket.onHit then riders[#riders + 1] = weapon.socket.onHit end
  for _, rider in ipairs(riders) do
    Status.apply(target, rider.status, rider.duration, rider.potency)
    self.log:add(string.format("%s is %s", target.name, rider.status))
  end
end

-- Marks a monster as no longer wary (see factions.lua): once the player has
-- aimed any offensive action at it, a tribal target that used to hold back
-- fights (or flees) like any other monster from then on, hit or miss. Any
-- offensive action also wakes a dormant target outright (see stealth.lua) -
-- an arrow or a spell that misses still gives away exactly where you are.
function Game:provoke(target)
  if target and target.kind == "monster" then
    target.provoked = true
    Stealth.alert(target, self.player.x, self.player.y)
  end
end

-- Floods a burst of noise.lua sound out from (x, y) and gives every other
-- still-dormant monster the flood actually reaches a chance to stir - a
-- clash of steel three rooms over does not single out whichever target
-- Game:provoke already woke outright, it startles whatever else is close
-- enough to hear it too. A monster startled this way only ever starts
-- searching the noise's origin (see Stealth.hear), never snaps straight to
-- hunting the way a direct hit does.
function Game:emitNoise(x, y, loudness)
  local field = Noise.propagate(self.level.map, x, y, loudness)
  for _, entity in ipairs(self.level.entities) do
    if entity.kind == "monster" and Stealth.isUnaware(entity) then
      local intensity = Noise.intensityAt(field, self.level.map, entity.x, entity.y)
      if intensity > 0 and self.rng:chance(intensity, loudness) then
        Stealth.hear(entity, x, y)
        self.log:add(string.format("%s stirs at the noise", entity.name))
      end
    end
  end
end

function Game:playerAttack(target)
  -- Read before provoke() wakes the target below, so the bonus reflects
  -- whatever it actually was the instant the blow landed.
  local sneak = Stealth.sneakMultiplier(target)
  self:provoke(target)
  self:emitNoise(self.player.x, self.player.y, Noise.MELEE)
  local multiplier = Skills.meleeDamageMultiplier(self.player, target) * sneak
  local outcome = Combat.attack(self.player, target, multiplier)
  Momentum.onMeleeHit(self.player)
  if sneak > 1 then
    self.log:add(string.format("you catch %s completely unaware", target.name))
  end
  self.log:add(string.format("you hit %s for %d", target.name, outcome.damage))
  local broke = Durability.wearWeapon(self.player)
  if broke then self.log:add(broke) end
  local lifesteal = Artifacts.lifestealAmount(self.player, outcome.damage)
  if lifesteal > 0 then
    self.player.hp = math.min(self.player.maxHp, self.player.hp + lifesteal)
    self.log:add(string.format("your %s drinks %d hp from %s", self.player.weapon.name, lifesteal, target.name))
  end
  self:applyWeaponRiders(self.player.weapon, target)
  if Skills.consumePoisonBlade(self.player) and target:isAlive() then
    Status.apply(target, Status.POISON, 5, 2)
    self.log:add(string.format("%s is envenomed", target.name))
  end
  local masteredKey, masteredBonus = Proficiency.onMeleeHit(self.player)
  if masteredKey then
    self.log:add(string.format("you grow more skilled with your %s (+%d attack)", masteredKey, masteredBonus))
  end
  if outcome.killed then
    self:awardKill(target)
  else
    local splitLine = Abilities.onHit(self, target)
    if splitLine then self.log:add(splitLine) end
  end
end

-- Attempts to cast a known spell, optionally at a target monster. Returns
-- true and logs its effect on success; on failure logs why and leaves all
-- state - mana included - untouched.
function Game:castSpell(key, target)
  self:provoke(target)
  local success, lines = Spells.cast(self, self.player, key, target)
  self.log:addAll(lines)
  if success then self:emitNoise(self.player.x, self.player.y, Noise.SPELL) end
  return success
end

-- Hurls the inventory item at `index` at a monster. The item always leaves
-- the inventory on a successful throw, whatever it did on arrival.
function Game:throwAt(index, target)
  local item = self.player.inventory[index]
  if not item then return false end
  self:provoke(target)
  local success, lines = Throwing.resolve(self, self.player, item, target)
  if success then
    table.remove(self.player.inventory, index)
    self:emitNoise(self.player.x, self.player.y, Noise.THROW)
  end
  self.log:addAll(lines)
  return success
end

-- Throws a net from the inventory at `index` at a battered monster instead
-- of finishing it off in melee (see captives.lua). The net always leaves
-- the inventory once thrown, whether it actually holds the target or not;
-- a genuine catch removes the target from level.entities without ever
-- routing through Game:awardKill, so it earns no xp, essence, quest credit
-- or faction kill penalty - only a captive left standing on the floor.
function Game:captureAt(index, target)
  local item = self.player.inventory[index]
  if not item then return false end
  self:provoke(target)
  local success, lines = Captives.resolve(self, self.player, item, target)
  if success then
    table.remove(self.player.inventory, index)
    self:emitNoise(self.player.x, self.player.y, Noise.THROW)
    self:cleanupDead()
  end
end

function Game:openDoor(x, y)
  local map = self.level.map
  if map:get(x, y) == Tiles.DOOR_LOCKED then
    for i, item in ipairs(self.player.inventory) do
      if item.kind == Items.KEY then
        table.remove(self.player.inventory, i)
        map:set(x, y, Tiles.DOOR_OPEN)
        self.log:add("you unlock the door")
        return true
      end
    end
    self.log:add("the door is locked")
    return true
  end
  map:set(x, y, Tiles.DOOR_OPEN)
  self.log:add("you open the door")
  return true
end

function Game:triggerTrap(trap)
  trap.revealed = true
  self.level.map:set(trap.x, trap.y, Tiles.TRAP)
  if trap.effect == "dart" then
    local dmg = 3 + self.depth // 2
    self.player.hp = self.player.hp - dmg
    self.log:add(string.format("a dart trap hits you for %d", dmg))
  elseif trap.effect == "poison" then
    Status.apply(self.player, Status.POISON, 5, 2)
    self.log:add("you stumble into a poison trap")
  else
    local x, y = self:randomFloorCell()
    if x then
      self.player.x, self.player.y = x, y
      self.log:add("a trap flings you across the level")
    end
  end
end

function Game:pickupHere()
  for i = #self.level.floorItems, 1, -1 do
    local ground = self.level.floorItems[i]
    if ground.x == self.player.x and ground.y == self.player.y then
      self.player.inventory[#self.player.inventory + 1] = ground.item
      self.log:add("you pick up " .. Identify.label(self.identify, ground.item))
      table.remove(self.level.floorItems, i)
    end
  end
end

function Game:movePlayer(dx, dy)
  local nx, ny = self.player.x + dx, self.player.y + dy
  local map = self.level.map
  if Tiles.isClosedDoor(map:get(nx, ny)) then
    return self:openDoor(nx, ny)
  end
  local target = self.level:entityAt(nx, ny)
  if target then
    self:playerAttack(target)
    return true
  end
  if map:isWalkable(nx, ny) then
    self.player.x, self.player.y = nx, ny
    local trap = self.level:trapAt(nx, ny)
    if trap and not trap.revealed then self:triggerTrap(trap) end
    self:pickupHere()
    return true
  end
  return false
end

function Game:useItem(index)
  local item = self.player.inventory[index]
  if not item then return false end
  if item.kind == Items.POTION or item.kind == Items.SCROLL then
    self.log:addAll(Effects.apply(item.effect, self, self.player, item))
    Identify.reveal(self.identify, item)
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.FOOD then
    self.player.satiation = self.player.satiation + item.nutrition
    self.log:add("you eat the " .. item.name)
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.WEAPON or item.kind == Items.ARMOR or item.kind == Items.RING then
    Items.useFromInventory(self.player, index)
    self.log:add("you equip " .. Identify.label(self.identify, item))
  else
    return false
  end
  return true
end

function Game:descend()
  if self.player.x ~= self.level.downX or self.player.y ~= self.level.downY then return false end
  self.depth = self.depth + 1
  self.level = self.dungeon:get(self.depth)
  self.player.x, self.player.y = self.level.upX, self.level.upY
  self.log:add("you descend to depth " .. self.depth)
  self:computeVisible()
  return true
end

function Game:ascend()
  if self.player.x ~= self.level.upX or self.player.y ~= self.level.upY then return false end
  if self.depth <= 1 then
    self.log:add("you climb toward the surface")
    return true
  end
  self.depth = self.depth - 1
  self.level = self.dungeon:get(self.depth)
  self.player.x, self.player.y = self.level.downX, self.level.downY
  self.log:add("you climb to depth " .. self.depth)
  self:computeVisible()
  return true
end

-- Autopilot.

function Game:findInInventory(predicate)
  for i, item in ipairs(self.player.inventory) do
    if predicate(item) then return i end
  end
  return nil
end

function Game:adjacentMonster()
  for _, dir in ipairs(MONSTER_DIRS) do
    local monster = self.level:entityAt(self.player.x + dir[1], self.player.y + dir[2])
    if monster then return monster end
  end
  return nil
end

function Game:playerPathTo(tx, ty)
  local hasKey = self:hasKey()
  return Astar.find(self.level.map, self.player.x, self.player.y, tx, ty, function(x, y)
    if x == tx and y == ty then return false end
    if not self.level.map:isPassable(x, y, hasKey) then return true end
    return self.level:entityAt(x, y) ~= nil
  end)
end

-- First step of the shortest route to the nearest monster the player can
-- actually reach, so blockers standing between the player and the stairs get
-- hunted down. Ties break on ascending monster id for determinism.
function Game:reachableMonsterStep()
  local bestLen, bestId, step = math.huge, math.huge, nil
  for _, monster in ipairs(self.level.entities) do
    local path = self:playerPathTo(monster.x, monster.y)
    if path and #path >= 2 then
      if #path < bestLen or (#path == bestLen and monster.id < bestId) then
        bestLen, bestId, step = #path, monster.id, path[2]
      end
    end
  end
  return step
end

-- First step toward the nearest not-yet-explored walkable cell via a BFS that
-- routes around monsters. Lets the autopilot discover a way onward when the
-- direct path to the stairs is temporarily blocked.
function Game:exploreStep()
  local map = self.level.map
  local hasKey = self:hasKey()
  local start = map:index(self.player.x, self.player.y)
  local came = { [start] = start }
  local queue = { { self.player.x, self.player.y, start } }
  local head = 1
  while head <= #queue do
    local cell = queue[head]
    head = head + 1
    local cx, cy, idx = cell[1], cell[2], cell[3]
    if idx ~= start and not self.level.explored[idx] and map:isWalkable(cx, cy) then
      local cursor = idx
      while came[cursor] ~= start do
        cursor = came[cursor]
      end
      local stepX = (cursor - 1) % map.width + 1
      local stepY = (cursor - 1) // map.width + 1
      return sign(stepX - self.player.x), sign(stepY - self.player.y)
    end
    for _, dir in ipairs(MONSTER_DIRS) do
      local nx, ny = cx + dir[1], cy + dir[2]
      if map:inBounds(nx, ny) and map:isPassable(nx, ny, hasKey)
        and not self.level:entityAt(nx, ny) then
        local nIdx = map:index(nx, ny)
        if not came[nIdx] then
          came[nIdx] = idx
          queue[#queue + 1] = { nx, ny, nIdx }
        end
      end
    end
  end
  return nil
end

function Game:anyMonsterVisible()
  for _, monster in ipairs(self.level.entities) do
    if self.visible[self.level.map:index(monster.x, monster.y)] then return true end
  end
  return false
end

-- Inventory index of the single best equipment upgrade to put on this turn, or
-- nil. Weapons and armour compare on power, rings on attack plus defence.
function Game:bestUpgrade()
  local player = self.player
  local weaponPower = player.weapon and player.weapon.power or 0
  local armorPower = player.armor and player.armor.power or 0
  local ringValue = player.ring and (player.ring.attack + player.ring.defense) or 0
  for i, item in ipairs(player.inventory) do
    if item.kind == Items.WEAPON and item.power > weaponPower then return i end
  end
  for i, item in ipairs(player.inventory) do
    if item.kind == Items.ARMOR and item.power > armorPower then return i end
  end
  for i, item in ipairs(player.inventory) do
    if item.kind == Items.RING and (item.attack + item.defense) > ringValue then return i end
  end
  return nil
end

function Game:choosePlayerAction()
  local player = self.player
  if not self:anyMonsterVisible() then
    local upgrade = self:bestUpgrade()
    if upgrade then self:useItem(upgrade); return end
  end
  if player.hp < player.maxHp // 3 then
    local potion = self:findInInventory(function(item)
      return item.kind == Items.POTION and item.effect == "heal"
    end)
    if potion then self:useItem(potion); return end
  end
  if player.satiation < 150 then
    local food = self:findInInventory(function(item) return item.kind == Items.FOOD end)
    if food then self:useItem(food); return end
  end
  local target = self:adjacentMonster()
  if target then
    self:movePlayer(sign(target.x - player.x), sign(target.y - player.y))
    return
  end
  if player.x == self.level.downX and player.y == self.level.downY then
    self:descend()
    return
  end
  local path = self:playerPathTo(self.level.downX, self.level.downY)
  if path and #path >= 2 then
    self:movePlayer(path[2].x - player.x, path[2].y - player.y)
    return
  end
  local hunt = self:reachableMonsterStep()
  if hunt then
    self:movePlayer(hunt.x - player.x, hunt.y - player.y)
    return
  end
  local ex, ey = self:exploreStep()
  if ex then self:movePlayer(ex, ey) end
end

function Game:hungerTorchTick()
  self.player.satiation = self.player.satiation - 1
  if self.player.satiation <= 0 then
    self.player.satiation = 0
    self.player.hp = self.player.hp - 1
    self.log:add("you are starving")
  end
  if self.player.light.fuel > 0 then
    self.player.light.fuel = self.player.light.fuel - 1
  end
end

function Game:endPlayerTurn()
  Scheduler.spend(self.player)
  self:hungerTorchTick()
  self.turn = self.turn + 1
  self:computeVisible()
end

function Game:autoStep()
  self:runToPlayer()
  if not self.player:isAlive() then return end
  self.log:addAll(Status.tick(self.player))
  if not self.player:isAlive() then return end
  if Status.skipsTurn(self.player) then
    self.log:add("you are stunned")
  else
    self:choosePlayerAction()
  end
  self:endPlayerTurn()
end

function Game:render()
  return Render.frame(self)
end

function Game:toData()
  return {
    seed = self.seed,
    depth = self.depth,
    turn = self.turn,
    rng = self.rng:serialize(),
    identify = self.identify,
    dungeon = self.dungeon:toData(),
    player = self.player:toData(),
    playerExtra = { satiation = self.player.satiation, light = self.player.light },
    log = self.log:toData(),
  }
end

function Game.fromData(snapshot)
  local game = setmetatable({}, Game)
  game.seed = snapshot.seed
  game.depth = snapshot.depth
  game.turn = snapshot.turn
  game.rng = Rng.deserialize(snapshot.rng)
  game.identify = snapshot.identify
  game.dungeon = Dungeon.fromData(snapshot.dungeon)
  game.level = game.dungeon:get(game.depth)
  game.player = Entity.fromData(snapshot.player)
  game.player.satiation = snapshot.playerExtra.satiation
  game.player.light = snapshot.playerExtra.light
  game.log = MessageLog.fromData(snapshot.log)
  game.visible = {}
  game:computeVisible()
  return game
end

function Game:save(path)
  Serialize.saveFile(path, self:toData())
end

function Game.load(path)
  return Game.fromData(Serialize.loadFile(path))
end

return Game
