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
  self.log:addAll(lines)
  return success
end

-- Looses an arrow from the player's equipped bow at a monster. The arrow
-- always leaves the quiver on a successful shot, whatever it did on arrival.
function Game:fireAt(target)
  self:provoke(target)
  local success, lines = Ranged.fire(self, self.player, target)
  self.log:addAll(lines)
  if success then self:emitNoise(self.player.x, self.player.y, Noise.RANGED) end
  return success
end

-- Spends gold to smooth over the player's standing with `faction` (see
-- factions.lua): cools a grudge, or pads an existing friendship, by a fixed
-- amount. The asking price climbs the deeper the relationship has soured.
function Game:appeaseFaction(faction)
  local success, cost = Factions.appease(self.player, faction)
  if success then
    self.log:add(string.format("your tribute smooths things over with the %s (%d gold)", faction, cost))
  elseif cost == 0 then
    self.log:add(string.format("the %s already think as well of you as they're going to", faction))
  else
    self.log:add(string.format("you need %d gold to make peace with the %s", cost, faction))
  end
  return success
end

-- Prays at the shrine standing under the player, spending its gold price for
-- a shot at a permanent blessing (or, with rising odds the more this altar
-- has already been used, a curse instead). Returns false without any state
-- change when there is no shrine here or its price cannot be met.
function Game:prayAt(shrine)
  local success, lines = Shrines.pray(self, shrine)
  self.log:addAll(lines)
  return success
end

-- Swings the player's equipped pick at whatever lies one step away in
-- (dx, dy): a plain wall or the rubble left by an earlier swing. Returns
-- false without spending the swing when there is no pick readied or the
-- target cell has nothing left to dig (open floor, a vault door, out of
-- bounds); otherwise always spends one use of the pick's durability, even on
-- an unlucky cave-in that costs hp instead of progress (see digging.lua).
function Game:dig(dx, dy)
  if not self.player.pick then
    self.log:add("you have nothing to dig with")
    return false
  end
  local nx, ny = self.player.x + dx, self.player.y + dy
  if not Digging.canDig(self.level.map, nx, ny) then
    self.log:add("there is nothing here to dig")
    return false
  end
  self.log:add(Digging.swing(self, self.player, nx, ny))
  local brokenLine = Digging.wearPick(self.player)
  if brokenLine then self.log:add(brokenLine) end
  self:emitNoise(nx, ny, Noise.DIG)
  return true
end

-- Harvests whatever resource node stands under the player: an ore vein pays
-- out essence, a gem seam yields a raw gem, both free of any gold cost -
-- unlike a shrine's prayer, the only thing rationing this is the node's own
-- charges (see nodes.lua). Returns false without state change when there is
-- no node here or it has already been picked dry this trip.
function Game:harvestNode()
  local node = self.level:nodeAt(self.player.x, self.player.y)
  if not node then
    self.log:add("there is nothing here to harvest")
    return false
  end
  local success, line = Nodes.harvest(self, node)
  self.log:add(line)
  return success
end

-- Butchers whatever corpse lies under the player into raw meat (Items.FOOD),
-- eaten later exactly like a found ration - unless the corpse has already
-- gone past its rot threshold (corpses.lua), in which case it poisons the
-- player instead. Either way the corpse itself is spent in one stroke.
-- Returns false without state change when there is nothing here to carve.
function Game:butcherCorpse()
  local corpse = self.level:corpseAt(self.player.x, self.player.y)
  if not corpse then
    self.log:add("there is nothing here to butcher")
    return false
  end
  self.log:add(Corpses.butcher(self, corpse))
  return true
end

-- Raises whatever fresh corpse lies under the player into a temporary
-- skeletal thrall (see reanimation.lua), spending both the corpse and a
-- bite of sanity in one stroke - a deliberate trade the autopilot never
-- makes on its own, unlike Game:butcherCorpse's free meal, so this is only
-- ever called directly. Returns false without state change when there is
-- no corpse here or Reanimation.raise itself refuses the attempt.
function Game:raiseCorpse()
  local corpse = self.level:corpseAt(self.player.x, self.player.y)
  if not corpse then
    self.log:add("there is nothing here to raise")
    return false
  end
  local thrall, failMsg = Reanimation.raise(self, corpse)
  if not thrall then
    self.log:add(failMsg)
    return false
  end
  self.log:add("bones knit and rise - your " .. thrall.name .. " answers the call")
  return true
end

-- Carves whatever fresh corpse lies under the player for the herb its own
-- kind carries (see scavenging.lua) instead of a meal or a thrall - a third
-- deliberate trade for the same tile, only ever called directly like
-- Game:raiseCorpse, never by the autopilot. Returns false without state
-- change when there is no corpse here or Scavenging.harvest itself refuses.
function Game:scavengeCorpse()
  local corpse = self.level:corpseAt(self.player.x, self.player.y)
  if not corpse then
    self.log:add("there is nothing here to scavenge")
    return false
  end
  local harvested, message = Scavenging.harvest(self, corpse)
  self.log:add(message)
  return harvested
end

-- Opens whatever chest stands under the player. An unlocked one (or one
-- already forced open) yields its hoard outright; a locked one first tries
-- a carried key, exactly like Game:openDoor's own certain trade, and only
-- falls back to a lockpick gamble (Chests.pick, which risks springing a
-- trapped lock) once no key can be found. Returns false without state
-- change when there is nothing here to open, it is already empty, or it is
-- locked with neither a key nor a lockpick on hand.
function Game:openChest()
  local chest = self.level:chestAt(self.player.x, self.player.y)
  if not chest then
    self.log:add("there is nothing here to open")
    return false
  end
  if chest.opened then
    self.log:add("this chest is already empty")
    return false
  end
  local success, line
  if not Chests.isLocked(chest) then
    success, line = Chests.open(self.player, chest)
  else
    success, line = Chests.unlockWithKey(self.player, chest)
    if not success then success, line = Chests.pick(self, chest) end
  end
  self.log:add(line)
  if success then self.stats.chestsOpened = self.stats.chestsOpened + 1 end
  return success
end

-- Frees whatever captive stands under the player back to its own kind for
-- nothing but goodwill (see Captives.ransom) - the one resolution that can
-- pull a wary tribal faction (factions.lua's neutralFactions) back out of
-- open hostility rather than deepening it further. Returns false without
-- state change when there is no captive here.
function Game:ransomCaptive()
  local captive = self.level:captiveAt(self.player.x, self.player.y)
  if not captive then
    self.log:add("there is nothing here to ransom")
    return false
  end
  Captives.ransom(self.level, self.player, captive)
  self.log:add(string.format("you release %s - the %s think a little better of you for it", captive.name, captive.faction))
  return true
end

-- Sells whatever captive stands under the player for gold at its own
-- faction's expense (see Captives.sell). Returns false without state change
-- when there is no captive here.
function Game:sellCaptive()
  local captive = self.level:captiveAt(self.player.x, self.player.y)
  if not captive then
    self.log:add("there is nothing here to sell")
    return false
  end
  local paid = Captives.sell(self.level, self.player, captive)
  self.log:add(string.format("you trade %s away for %d gold", captive.name, paid))
  return true
end

-- Interrogates whatever captive stands under the player instead of ransoming
-- or selling it (see Captives.interrogate): no gold, no reputation swing,
-- just every currently-hidden secret door on this floor found outright plus
-- a trickle of essence. Returns false without state change when there is no
-- captive here.
function Game:interrogateCaptive()
  local captive = self.level:captiveAt(self.player.x, self.player.y)
  if not captive then
    self.log:add("there is nothing here to interrogate")
    return false
  end
  local revealed = Captives.interrogate(self.level, self.player, captive)
  self.log:add(string.format("%s breaks - %d hidden door%s in this floor give themselves away",
    captive.name, #revealed, #revealed == 1 and "" or "s"))
  return true
end

-- Binds the player to `board`'s bounty for free, logging the pact struck or
-- the reason it could not be. See Quests.accept for the acceptance rules.
function Game:tryAcceptQuest(board)
  local success, line = Quests.accept(self.player, board)
  self.log:add(line)
  return success
end

-- Pays out the player's active bounty the moment it is fulfilled, granting
-- gold, xp and essence in one stroke and freeing the player to bind another.
-- A no-op with no active bounty or one still unmet.
function Game:resolveQuest()
  local bounty = self.player.quest
  if not bounty or not Quests.resolved(self.player, self.depth) then return false end
  self.player.gold = self.player.gold + bounty.rewardGold
  self.log:addAll(Progression.grantXp(self.player, bounty.rewardXp))
  self.player.essence = self.player.essence + Crafting.essenceFor(bounty.rewardXp)
  self.player.quest = nil
  self.stats.questsCompleted = self.stats.questsCompleted + 1
  Factions.adjust(self.player, Factions.MERCHANT, 3)
  self.log:add(string.format("the bounty resolves: %d gold and %d xp", bounty.rewardGold, bounty.rewardXp))
  return true
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

-- Springs `trap` on `victim`, whoever that is: reveals it on the map and
-- resolves its effect against that entity's own stats and position. Kept
-- generic so a player-planted trap kit (Game:useItem's Items.KIT branch)
-- harms a monster exactly as a builder-placed one harms the player.
function Game:springTrap(trap, victim)
  trap.revealed = true
  self.level.map:set(trap.x, trap.y, Tiles.TRAP)
  local isPlayer = victim == self.player
  local name = isPlayer and "you" or victim.name
  if trap.effect == "dart" then
    local dmg = 3 + self.depth // 2
    victim.hp = victim.hp - dmg
    self.log:add(isPlayer and string.format("a dart trap hits you for %d", dmg)
      or string.format("a dart trap hits %s for %d", name, dmg))
  elseif trap.effect == "poison" then
    Status.apply(victim, Status.POISON, 5, 2)
    self.log:add(isPlayer and "you stumble into a poison trap"
      or string.format("%s stumbles into a poison trap", name))
  elseif trap.effect == "confuse" then
    Status.apply(victim, Status.CONFUSE, 6, 1)
    self.log:add(isPlayer and "a cloud of disorienting spores bursts around you"
      or string.format("a cloud of disorienting spores bursts around %s", name))
  elseif trap.effect == "blind" then
    Status.apply(victim, Status.BLIND, 6, 1)
    self.log:add(isPlayer and "a flash of searing light leaves you blind"
      or string.format("a flash of searing light leaves %s blind", name))
  elseif trap.effect == "stun" then
    Status.apply(victim, Status.STUN, 2, 1)
    self.log:add(isPlayer and "a jolt of current locks up your muscles"
      or string.format("a jolt of current locks up %s's muscles", name))
  else
    local x, y = self:randomFloorCell()
    if x then
      victim.x, victim.y = x, y
      self.log:add(isPlayer and "a trap flings you across the level"
        or string.format("a trap flings %s across the level", name))
    end
  end
end

function Game:triggerTrap(trap)
  self:springTrap(trap, self.player)
end

-- Attempts to disarm `trap`, already noticed (see disarm.lua's Disarm.sweep,
-- rolled once per turn in Game:endPlayerTurn) but not yet sprung. Refuses
-- outright, without even risking a spring, against a trap never detected or
-- one already triggered - there is nothing left here to disarm.
function Game:disarmTrap(trap)
  if not trap or not trap.detected or trap.revealed then
    self.log:add("there is nothing here you have noticed to disarm")
    return false
  end
  local success, line = Disarm.attempt(self, trap)
  if success then self.log:add(line) end
  return success
end

-- Throws `lever`, a no-op once it has already been thrown. The instant this
-- pull completes every lever sharing its vault id, the shared door swings
-- open (its tile flips to a plain open door - see Vaults.pull) and the run's
-- vault tally advances for meta scoring; otherwise the lever just clunks
-- into its pulled state.
function Game:pullLever(lever)
  local pulled, door = Vaults.pull(self.level, lever)
  if not pulled then return false end
  self.level.map:set(lever.x, lever.y, Tiles.LEVER_PULLED)
  if door then
    door.opened = true
    self.level.map:set(door.x, door.y, Tiles.DOOR_OPEN)
    self.stats.vaultsOpened = self.stats.vaultsOpened + 1
    self.log:add("the vault door grinds open")
  else
    self.log:add("you pull the lever - it clunks into place")
  end
  return true
end

-- A priced ware is only free for the taking once its shopkeeper is dead;
-- otherwise it charges the stamped price and is left on the ground when the
-- player cannot afford it yet (they simply walk past it).
function Game:wardedByLiveKeeper(ground)
  if not ground.price then return false end
  local keeper = self.level:entityById(ground.shopId)
  return keeper ~= nil and keeper:isAlive()
end

-- Player-facing wrapper so callers never need to know encumbrance.lua works
-- entirely off entity.inventory/entity.level rather than any saved field.
function Game:encumbranceTier()
  return Encumbrance.tierFor(self.player)
end

function Game:pickupHere()
  local tierBefore = self:encumbranceTier()
  for i = #self.level.floorItems, 1, -1 do
    local ground = self.level.floorItems[i]
    if ground.x == self.player.x and ground.y == self.player.y then
      local item = ground.item
      if item.mimic then
        table.remove(self.level.floorItems, i)
        self:triggerMimic(ground)
      elseif item.grave then
        table.remove(self.level.floorItems, i)
        self:triggerGrave(ground)
      elseif item.kind == Items.GOLD then
        self.player.gold = self.player.gold + item.amount
        self.log:add("you find " .. item.amount .. " gold")
        table.remove(self.level.floorItems, i)
      elseif self:wardedByLiveKeeper(ground) then
        local paid = Shop.buy(self, ground)
        if paid then
          self.log:add(string.format("you buy %s for %d gold",
            Identify.label(self.identify, item), paid))
          table.remove(self.level.floorItems, i)
        end
      elseif item.kind == Items.AMMO then
        local stack = self:findInInventory(function(existing)
          return existing.kind == Items.AMMO and existing.name == item.name
        end)
        if stack then
          self.player.inventory[stack].count = self.player.inventory[stack].count + item.count
        else
          self.player.inventory[#self.player.inventory + 1] = item
        end
        self.log:add(string.format("you pick up %d %s", item.count, item.name))
        table.remove(self.level.floorItems, i)
      else
        if item.artifact then self.stats.artifactsFound = self.stats.artifactsFound + 1 end
        if item.set then self.stats.setPiecesFound = self.stats.setPiecesFound + 1 end
        self.player.inventory[#self.player.inventory + 1] = item
        self.log:add("you pick up " .. Identify.label(self.identify, item))
        table.remove(self.level.floorItems, i)
      end
    end
  end
  local tierAfter = self:encumbranceTier()
  if tierAfter ~= tierBefore and tierAfter ~= Encumbrance.LIGHT then
    if tierAfter == Encumbrance.OVERLOADED then
      self.log:add("you are overloaded and moving sluggishly")
    else
      self.log:add("your pack grows heavy")
    end
  end
end

-- Unmasks a disguised floorItem the moment the player reaches for it:
-- drops the real hostile monster in its place (already hunting, never
-- dormant - see stealth.lua's header for why a builder-placed wild
-- monster differs) and lands one free ambush swing through combat.lua,
-- so the surprise still respects the player's defense and resistances
-- instead of being a flat, unavoidable trap tick.
function Game:triggerMimic(ground)
  local mimic = Mimics.reveal(self:nextMonsterId(), ground.x, ground.y, self.depth)
  mimic.awareness = Stealth.HUNTING
  self.level.entities[#self.level.entities + 1] = mimic
  self.log:add(ground.item.name .. " was a mimic!")
  local outcome = Combat.attack(mimic, self.player, self:monsterDamageMultiplier())
  Momentum.onDamaged(self.player)
  self.log:add(string.format("it lashes out at you for %d damage", outcome.damage))
  local broke = Durability.wearArmor(self.player)
  if broke then self.log:add(broke) end
end

-- Wakes the vengeful shade sleeping under a disturbed grave marker (see
-- graves.lua): unlike a mimic's disguise, the marker never hid what it
-- was, but stepping onto it is still a mistake the same instant Game:
-- pickupHere makes it - one free ambush swing through combat.lua before
-- the shade settles into an ordinary chase on its own turns from then on.
function Game:triggerGrave(ground)
  local shade = Graves.reveal(self:nextMonsterId(), ground.x, ground.y, ground)
  shade.awareness = Stealth.HUNTING
  self.level.entities[#self.level.entities + 1] = shade
  self.log:add("the grave stirs - a vengeful shade rises!")
  local outcome = Combat.attack(shade, self.player, self:monsterDamageMultiplier())
  Momentum.onDamaged(self.player)
  self.log:add(string.format("it lashes out at you for %d damage", outcome.damage))
  local broke = Durability.wearArmor(self.player)
  if broke then self.log:add(broke) end
end

-- Discards an inventory item onto the floor at the player's feet: the
-- opposite of pickupHere, needed once a hoard grows heavier than is
-- comfortable to carry (see encumbrance.lua). Equipped gear never reaches
-- this path - it always trades in place through items.equipWeapon and
-- friends - so this only ever touches the loose inventory array.
function Game:dropItem(index)
  local item = self.player.inventory[index]
  if not item then return nil end
  table.remove(self.player.inventory, index)
  self.level.floorItems[#self.level.floorItems + 1] = { x = self.player.x, y = self.player.y, item = item }
  self.log:add("you drop " .. Identify.label(self.identify, item))
  return item
end

-- The cheapest inventory item that is safe to shed first when overloaded:
-- never the amulet (the entire point of a run) or a key (worthless to a
-- shop and needed right where it was found). Returns nil if nothing but
-- those two remains.
function Game:cheapestDroppableItem()
  local bestIndex, bestPrice
  for i, item in ipairs(self.player.inventory) do
    if item.kind ~= Items.AMULET and item.kind ~= Items.KEY then
      local price = Shop.priceOf(item)
      if not bestPrice or price < bestPrice then
        bestIndex, bestPrice = i, price
      end
    end
  end
  return bestIndex
end

-- Sells an inventory item back to the economy at half its catalog price.
function Game:sellItem(index)
  local item = self.player.inventory[index]
  local value = Shop.sell(self, index)
  if value then
    self.log:add(string.format("you sell %s for %d gold", Identify.label(self.identify, item), value))
  end
  return value
end

-- Spends gold to restore whichever of the player's weapon, armor or bow sits
-- in `slotName` back to full durability (see durability.lua), folding its
-- power back into attack/defense if wear had already broken it.
function Game:repairEquipped(slotName)
  local item = self.player[slotName]
  local success, result = Durability.repair(self.player, slotName)
  if success then
    self.log:add(string.format("you repair your %s for %d gold", item.name, result))
  else
    self.log:add("cannot repair: " .. result)
  end
  return success
end

-- The first of weapon/armor/bow, in that priority order, that has been worn
-- clean through to uselessness - never a merely dinged one still pulling its
-- weight, so the autopilot only ever reaches for its purse over gear that
-- has actually stopped working.
function Game:brokenEquippedSlot()
  for _, slot in ipairs({ "weapon", "armor", "bow" }) do
    local item = self.player[slot]
    if item and Durability.isBroken(item) then return slot end
  end
  return nil
end

-- Taking a warded item without paying: the item is stolen outright and its
-- shopkeeper turns permanently hostile, chasing the player like any monster.
function Game:stealFromShop(index)
  local ground = self.level.floorItems[index]
  if not ground or not self:wardedByLiveKeeper(ground) then return false end
  self.player.inventory[#self.player.inventory + 1] = ground.item
  local keeper = self.level:entityById(ground.shopId)
  keeper.hostile = true
  Factions.adjust(self.player, Factions.MERCHANT, -20)
  self.log:add("you steal " .. Identify.label(self.identify, ground.item) ..
    "! the shopkeeper turns on you")
  table.remove(self.level.floorItems, index)
  return true
end

-- Resolves a crafting target: "weapon"/"armor" reach the currently equipped
-- piece (which has left the inventory array entirely - see items.equipWeapon/
-- equipArmor), anything else is an inventory index.
function Game:resolveGear(target)
  if target == "weapon" then return self.player.weapon end
  if target == "armor" then return self.player.armor end
  return self.player.inventory[target]
end

function Game:forgeGem(element)
  local ok, result = Crafting.forge(self.player, element)
  if not ok then
    self.log:add("cannot forge: " .. result)
    return false
  end
  self.player.inventory[#self.player.inventory + 1] = result
  self.log:add("you forge a " .. result.name)
  return true
end

function Game:mergeGemsAt(indexA, indexB)
  local gemA, gemB = self.player.inventory[indexA], self.player.inventory[indexB]
  if not gemA or not gemB or gemA.kind ~= Items.GEM or gemB.kind ~= Items.GEM or indexA == indexB then
    return false
  end
  local success, reason, merged = Crafting.mergeGems(gemA, gemB)
  if not success then
    self.log:add("cannot merge gems: " .. reason)
    return false
  end
  local hi, lo = math.max(indexA, indexB), math.min(indexA, indexB)
  table.remove(self.player.inventory, hi)
  table.remove(self.player.inventory, lo)
  self.player.inventory[#self.player.inventory + 1] = merged
  self.log:add("you merge two gems into a " .. merged.name)
  return true
end

function Game:socketItem(target, gemIndex)
  local item = self:resolveGear(target)
  local gem = self.player.inventory[gemIndex]
  if not item or not gem or gem.kind ~= Items.GEM then return false end
  local success, reason = Crafting.socket(self.player, item, gem)
  if not success then
    self.log:add("cannot socket: " .. reason)
    return false
  end
  table.remove(self.player.inventory, gemIndex)
  self.log:add("you socket a " .. gem.name .. " into your " .. item.name)
  return true
end

-- Socketing a rune never removes it from the game the way a failed gem
-- socket attempt would leave the gem untouched in inventory - the rune is
-- always spent once it joins the chain, whether or not that completes a
-- runeword, since there is no "wrong" rune to protect the player from (see
-- Runewords.socket).
function Game:socketRune(target, runeIndex)
  local item = self:resolveGear(target)
  local rune = self.player.inventory[runeIndex]
  if not item or not rune or rune.kind ~= Items.RUNE then return false end
  local success, reason = Runewords.socket(item, rune)
  if not success then
    self.log:add("cannot socket rune: " .. reason)
    return false
  end
  table.remove(self.player.inventory, runeIndex)
  local word = Runewords.activeWord(item)
  if word then
    self.log:add("the runes align into " .. word.name .. "! your " .. item.name .. " hums with power")
  else
    self.log:add("you socket a " .. rune.name .. " into your " .. item.name)
  end
  return true
end

function Game:temperItem(target)
  local item = self:resolveGear(target)
  if not item then return false end
  local success, reason = Crafting.temper(self.player, item)
  if not success then
    self.log:add("cannot temper: " .. reason)
    return false
  end
  self.log:add("you temper your " .. item.name)
  return true
end

function Game:enchantItem(target, affixKey)
  local item = self:resolveGear(target)
  if not item then return false end
  local success, reason = Crafting.enchant(self.player, item, affixKey)
  if not success then
    self.log:add("cannot enchant: " .. reason)
    return false
  end
  self.log:add("you enchant your " .. item.name)
  return true
end

function Game:disenchantItem(target)
  local item = self:resolveGear(target)
  if not item then return false end
  local success, refund = Crafting.disenchant(self.player, item)
  if not success then
    self.log:add("cannot disenchant: " .. refund)
    return false
  end
  self.log:add(string.format("you disenchant %s for %d essence", item.name, refund))
  return true
end

-- Combines the two carried herbs at indexA and indexB into whichever potion
-- Alchemy.brew resolves the pair to. Both herbs are spent regardless of the
-- outcome - a botched brew that curdles is not a free retry, and vents its
-- fumes as a gas hazard right underfoot instead of handing back a potion.
function Game:brewAt(indexA, indexB)
  if not self.level:cauldronAt(self.player.x, self.player.y) then
    self.log:add("there is no cauldron here")
    return false
  end
  if indexA == indexB then return false end
  local herbA, herbB = self.player.inventory[indexA], self.player.inventory[indexB]
  if not herbA or not herbB or herbA.kind ~= Items.HERB or herbB.kind ~= Items.HERB then
    self.log:add("you need two herbs to brew")
    return false
  end
  local hi, lo = math.max(indexA, indexB), math.min(indexA, indexB)
  table.remove(self.player.inventory, hi)
  table.remove(self.player.inventory, lo)
  local potion = Alchemy.brew(herbA.herb, herbB.herb)
  if not potion then
    Hazards.spawnGas(self.level, self.player.x, self.player.y, 3, 2)
    self.log:add(string.format("the %s and %s curdle into choking fumes", herbA.name, herbB.name))
    return false
  end
  Identify.reveal(self.identify, potion)
  self.player.inventory[#self.player.inventory + 1] = potion
  self.log:add("you brew " .. potion.name)
  return true
end

-- Companions, hirelings and thralls are all player-owned allies (see
-- Game:onActorDeath), never a valid melee target for the player's own bump-
-- attack or autopilot targeting - both Game:movePlayer and Game:adjacentMonster
-- below share this one check so neither can turn "walk into your own hound"
-- into an accidental kill.
local function isPlayerAlly(entity)
  return entity.kind == "companion" or entity.kind == "hireling" or entity.kind == "thrall"
end

local CONFUSE_DIRS = {
  { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

-- Whether `dx, dy` (the direction the player actually typed, or the one
-- autopilot's own targeting picked) gets overridden by a random one of the
-- 8 compass directions this call - the confusion-lands roll only ever fires
-- once per Game:movePlayer, never re-rolled mid-call. Confusion strikes
-- before Game:movePlayer even looks at what's in the chosen direction, so a
-- stumble can just as easily open a door, bump a rival into a fight, shove a
-- block, or walk the player straight onto a trap as a deliberate move would.
local function confusionRedirect(self, dx, dy)
  if not Status.has(self.player, Status.CONFUSE) then return dx, dy, false end
  if not self.rng:chance(Status.CONFUSE_NUMERATOR, Status.CONFUSE_DENOMINATOR) then
    return dx, dy, false
  end
  local dir = CONFUSE_DIRS[self.rng:range(1, #CONFUSE_DIRS)]
  return dir[1], dir[2], true
end

-- `stumbled` (below) is what makes a confused player's failed lurch still
-- cost a turn: an ordinary bump into a wall or an unpushable block returns
-- false and Game:manualStep spends nothing, exactly as a rejected typed
-- command should, but a confused player who meant to go one way and staggered
-- into a wall instead still acted - the turn is spent on the stumble itself,
-- not on whatever (if anything) it accomplished.
function Game:movePlayer(dx, dy)
  local stumbled
  dx, dy, stumbled = confusionRedirect(self, dx, dy)
  if stumbled then self.log:add("your senses reel and you stumble sideways") end
  local nx, ny = self.player.x + dx, self.player.y + dy
  local map = self.level.map
  if Tiles.isClosedDoor(map:get(nx, ny)) then
    return self:openDoor(nx, ny)
  end
  local target = self.level:entityAt(nx, ny)
  if target and not isPlayerAlly(target) then
    self:playerAttack(target)
    return true
  end
  if not target then
    local block = self.level:blockAt(nx, ny)
    if block then
      local pushed, line = Blocks.push(self.level, block, dx, dy)
      if not pushed then return stumbled end
      self.log:add(line)
      Blocks.updateGates(self.level)
    end
  end
  if map:isWalkable(nx, ny) then
    if target then
      target.x, target.y = self.player.x, self.player.y
      self.log:add("you swap places with your " .. target.name)
    end
    self.player.x, self.player.y = nx, ny
    local trap = self.level:trapAt(nx, ny)
    if trap and not trap.revealed and not Status.has(self.player, Status.LEVITATE) then
      self:triggerTrap(trap)
    end
    self:checkTerrainFor(self.player, dx, dy)
    local lever = self.level:vaultLeverAt(nx, ny)
    if lever then self:pullLever(lever) end
    self:pickupHere()
    return true
  end
  return stumbled
end

function Game:useItem(index)
  local item = self.player.inventory[index]
  if not item then return false end
  if item.kind == Items.POTION or item.kind == Items.SCROLL then
    self.log:addAll(Effects.apply(item.effect, self, self.player, item))
    Identify.reveal(self.identify, item)
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.FOOD then
    local bloated = Hunger.eat(self.player, item.nutrition)
    if bloated then
      self.log:add("you force down the " .. item.name .. " past comfort and feel bloated")
    else
      self.log:add("you eat the " .. item.name)
    end
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.WEAPON or item.kind == Items.ARMOR or item.kind == Items.RING
    or item.kind == Items.BOW then
    local slot = slotByItemKind[item.kind]
    if not Curses.tryRelease(self.player, slot) then
      self.log:add("the " .. Curses.label(self.player[slot], Identify.label(self.identify, self.player[slot])) ..
        " will not come off!")
      return false
    end
    Items.useFromInventory(self.player, index)
    self.log:add("you equip " .. Curses.label(item, Identify.label(self.identify, item)))
    if item.set then
      local count = Sets.equippedCounts(self.player)[item.set]
      local bonus = Sets.bonusFor(item.set, count)
      if bonus then
        self.log:add("the " .. Sets.byKey[item.set].name .. " set (" .. count .. " pieces) awakens")
      end
    end
  elseif item.kind == Items.TOME then
    if Spells.learn(self.player, item.spell) then
      self.log:add("you learn " .. Spells.catalog[item.spell].name)
    else
      self.log:add("you already know that spell")
    end
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.CHARM then
    local companion = Companions.summon(self, item.companion)
    if not companion then return false end
    self.log:add("your " .. companion.name .. " bonds to you")
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.CONTRACT then
    local hireling = Mercenaries.hire(self, item.hireling)
    if not hireling then return false end
    self.log:add("your " .. hireling.name .. " joins you for hire")
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.KIT then
    if self.level:trapAt(self.player.x, self.player.y) then
      self.log:add("there is already a trap here")
      return false
    end
    self.level.traps[#self.level.traps + 1] = {
      x = self.player.x, y = self.player.y, effect = item.effect, revealed = false, placedByPlayer = true,
    }
    self.log:add("you plant a " .. item.name)
    table.remove(self.player.inventory, index)
  elseif item.kind == Items.PICK then
    Items.useFromInventory(self.player, index)
    self.log:add("you ready your " .. item.name)
  else
    return false
  end
  return true
end

-- Removes the currently-live nemesis (nemesis.lua) from the floor about to
-- be left and escalates its grudge, so Game:nemesisArrive rebuilds it
-- stronger on the other side of the stairwell. Unlike every other hostile
-- (level.lua's own header: a revisited floor keeps its exact state, dead
-- monsters and all), a nemesis is never left behind - it always follows.
function Game:nemesisFollow()
  for i, entity in ipairs(self.level.entities) do
    if entity.nemesis then
      table.remove(self.level.entities, i)
      Nemesis.escalate(self.nemesis)
      return
    end
  end
end

-- Rolls a brand new nemesis into being from whichever hostile was already
-- hunting the player on the floor just cleared. Only tried on the way down
-- (Game:descend) and only while no nemesis is following yet - ordinary
-- backtracking upstairs never manufactures one.
function Game:nemesisTryEmerge()
  if not self.rng:chance(Nemesis.CHANCE_NUMERATOR, Nemesis.CHANCE_DENOMINATOR) then return end
  local hunter = Nemesis.pickHunter(self.level, self.player)
  if not hunter then return end
  for i, entity in ipairs(self.level.entities) do
    if entity == hunter then
      table.remove(self.level.entities, i)
      break
    end
  end
  self.nemesis = Nemesis.beginFrom(hunter)
end

-- Drops the pursuing nemesis onto whichever floor Game:descend/ascend has
-- just switched self.level/self.depth to. A no-op without one following.
function Game:nemesisArrive()
  if not self.nemesis then return end
  local x, y = self:randomFloorCell()
  if not x then return end
  local entity = Nemesis.spawn(self.nemesis, self:nextMonsterId(), x, y, self.depth)
  entity.awareness = Stealth.HUNTING
  self.level.entities[#self.level.entities + 1] = entity
  self.log:add(entity.name .. " has followed you")
end

local ALLY_CARRY_KINDS = { companion = true, hireling = true, thrall = true }
local ALLY_CARRY_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- Pulls every living player-aligned ally (companion/hireling/thrall) off
-- `fromLevel`'s own entities list, ready to be handed to
-- Game:plantCarriedAllies once self.level/self.player.x/y already point at
-- the destination. companions.lua/mercenaries.lua/reanimation.lua's own
-- module comments describe a bonded ally as persisting "across the whole
-- run" (or, for a hireling, demanding its wage "for as long as it lives") -
-- without this pair, every one of them was actually abandoned in place the
-- instant the player took a single flight of stairs or crossed a rift,
-- silently contradicting that promise. Mirrors Game:nemesisFollow's own
-- table.remove-while-scanning shape, just for up to three kinds at once
-- instead of one flagged entity.
function Game:detachCarriedAllies(fromLevel)
  local carried = {}
  for i = #fromLevel.entities, 1, -1 do
    local entity = fromLevel.entities[i]
    if ALLY_CARRY_KINDS[entity.kind] and entity:isAlive() then
      table.remove(fromLevel.entities, i)
      carried[#carried + 1] = entity
    end
  end
  return carried
end

-- Re-plants entities Game:detachCarriedAllies pulled off the old floor onto
-- self.level, each on the first free cell around the player's new position -
-- the same 8-directional, first-free-cell convention Companions.summon/
-- Mercenaries.hire/Reanimation.raise already use to place a brand new one -
-- falling back to Game:randomFloorCell (the same primitive Game:nemesisArrive
-- uses) only if every adjacent cell is blocked, so an ally is never simply
-- lost for want of room next to the stairs.
function Game:plantCarriedAllies(carried)
  for _, ally in ipairs(carried) do
    local placed = false
    for _, dir in ipairs(ALLY_CARRY_DIRS) do
      local x, y = self.player.x + dir[1], self.player.y + dir[2]
      if self.level.map:isWalkable(x, y) and not self.level:entityAt(x, y) then
        ally.x, ally.y = x, y
        placed = true
        break
      end
    end
    if not placed then
      local x, y = self:randomFloorCell()
      if x then ally.x, ally.y = x, y; placed = true end
    end
    if placed then
      self.level.entities[#self.level.entities + 1] = ally
      self.log:add("your " .. ally.name .. " follows you")
    end
  end
end

function Game:descend()
  if self.rift then return false end
  if self.player.x ~= self.level.downX or self.player.y ~= self.level.downY then return false end
  if self.depth >= self.maxDepth then
    self.log:add("the stairwell ends in solid rock here")
    return false
  end
  if self.nemesis then self:nemesisFollow() else self:nemesisTryEmerge() end
  local carriedAllies = self:detachCarriedAllies(self.level)
  self.depth = self.depth + 1
  self.level = self.dungeon:get(self.depth)
  self.player.x, self.player.y = self.level.upX, self.level.upY
  if self.depth > self.deepestDepth then self.deepestDepth = self.depth end
  self.log:add("you descend to depth " .. self.depth)
  self:nemesisArrive()
  self:plantCarriedAllies(carriedAllies)
  self:computeVisible()
  return true
end

function Game:ascend()
  if self.rift then return false end
  if self.player.x ~= self.level.upX or self.player.y ~= self.level.upY then return false end
  if self.depth <= 1 then
    if self:hasAmulet() then
      self.won = true
      self.log:add("you escape the dungeon with the Amulet of Warren - you win!")
    else
      self.log:add("you climb toward the surface")
    end
    return true
  end
  if self.nemesis then self:nemesisFollow() end
  local carriedAllies = self:detachCarriedAllies(self.level)
  self.depth = self.depth - 1
  self.level = self.dungeon:get(self.depth)
  self.player.x, self.player.y = self.level.downX, self.level.downY
  self.log:add("you climb to depth " .. self.depth)
  self:nemesisArrive()
  self:plantCarriedAllies(carriedAllies)
  self:computeVisible()
  return true
end

-- Crosses the rift the player is currently standing on (see branches.lua),
-- swapping the run's active level for that rift's own pocket floor. The
-- pocket floor is generated once per origin depth and cached on
-- self.riftLevels exactly like self.dungeon caches every main-track floor,
-- so leaving and coming back always finds it exactly as it was left, dead
-- monsters and all - and only the very first crossing of a given rift spends
-- the one carried shard the stabilization costs; every crossing after that,
-- in either direction, is free. Returns false without side effects when the
-- player is not standing on a rift, is already across one, or (on a first
-- crossing only) is not carrying a shard to spend.
function Game:enterRift()
  if self.rift then return false end
  local rift = self.level:riftAt(self.player.x, self.player.y)
  if not rift then return false end
  self.riftLevels = self.riftLevels or {}
  local firstCrossing = self.riftLevels[self.depth] == nil
  if firstCrossing then
    local shardIndex = self:findInInventory(function(item) return item.kind == Items.RIFTSTONE end)
    if not shardIndex then return false end
    table.remove(self.player.inventory, shardIndex)
    self.riftLevels[self.depth] = Branches.build(self.seed, self.depth, self.dungeon.options)
  end
  local carriedAllies = self:detachCarriedAllies(self.level)
  self.riftReturn = { level = self.level, depth = self.depth, x = self.player.x, y = self.player.y }
  self.level = self.riftLevels[self.depth]
  self.rift = true
  self.player.x, self.player.y = self.level.upX, self.level.upY
  self.log:add(firstCrossing and "the shard crumbles to dust as you step through the rift"
    or "you step through the stabilized rift once more")
  self:plantCarriedAllies(carriedAllies)
  self:computeVisible()
  return true
end

-- Steps back out of a rift crossing at its own pocket floor's downX/downY
-- (Branches.build reuses an ordinary Builder.build floor's ordinary "stairs
-- down" pair as the one way back rather than inventing a second tile kind),
-- restoring the exact main-track level, depth and position Game:enterRift
-- saved before the crossing. Returns false without effect when the player is
-- not currently across a rift, or has not yet reached its own exit point.
function Game:exitRift()
  if not self.rift then return false end
  if self.player.x ~= self.level.downX or self.player.y ~= self.level.downY then return false end
  local carriedAllies = self:detachCarriedAllies(self.level)
  self.level = self.riftReturn.level
  self.depth = self.riftReturn.depth
  self.player.x, self.player.y = self.riftReturn.x, self.riftReturn.y
  self.rift = false
  self.riftReturn = nil
  self.log:add("you step back through the rift, blinking in familiar torchlight")
  self:plantCarriedAllies(carriedAllies)
  self:computeVisible()
  return true
end

-- Starts a Horde Arena trial for the run in progress: swaps the player's
-- current level for a fresh closed arena (see horde.lua's own header for
-- why this can bypass dungeon.lua/builder.lua entirely and still work with
-- every existing turn system unmodified) and spawns its first wave through
-- the very same Horde.tick that clears each wave after it. The dungeon
-- floor left behind is simply abandoned - descending is not something an
-- arena run does, only Game:endPlayerTurn's escalating waves. A bonded
-- companion/hireling/thrall is not abandoned along with it though: the same
-- detachCarriedAllies/plantCarriedAllies pair Game:descend/ascend/enterRift/
-- exitRift already use follows the player in here too, planted around the
-- arena's centre anchor (cx, cy) rather than left to die alone on a floor
-- the run can never return to - an ally bonded specifically to fight beside
-- the player has the most reason to stand with them in a survival trial.
function Game:startHorde()
  local carriedAllies = self:detachCarriedAllies(self.level)
  local map, cx, cy = Horde.buildArena(self.rng, Horde.WIDTH, Horde.HEIGHT)
  self.level = Level.new({ depth = self.depth, generator = "horde", map = map })
  self.player.x, self.player.y = cx, cy
  self.horde = Horde.newState()
  self:plantCarriedAllies(carriedAllies)
  local line = Horde.tick(self)
  if line then self.log:add(line) end
  self:computeVisible()
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
    if monster and not isPlayerAlly(monster) then return monster end
  end
  return nil
end

function Game:playerPathTo(tx, ty)
  local hasKey = self:hasKey()
  return Astar.find(self.level.map, self.player.x, self.player.y, tx, ty, function(x, y)
    if x == tx and y == ty then return false end
    if not self.level.map:isPassable(x, y, hasKey) then return true end
    if self.level:blockAt(x, y) then return true end
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

-- Only true hostiles (isPlayerAlly's same companion/hireling/thrall
-- allowlist that Game:movePlayer's own bump-attack already respects) -
-- unlike Game:anyMonsterVisible above, which choosePlayerAction uses to gate
-- inventory downtime and deliberately treats ANY visible entity as "not
-- safe to fiddle right now". Game:autoExplore needs the narrower question:
-- a loyal ally standing in plain sight next to the player it always follows
-- must never interrupt an autoexplore run on its own.
function Game:anyHostileVisible()
  for _, entity in ipairs(self.level.entities) do
    if not isPlayerAlly(entity) and self.visible[self.level.map:index(entity.x, entity.y)] then
      return true
    end
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

-- The first not-yet-known skill of the player's class whose level requirement
-- is already met, or nil. Learning costs no turn, so the autopilot spends
-- any banked skill point the moment it can, in the tree's fixed order.
function Game:nextLearnableSkill()
  local player = self.player
  if not player.class or (player.skillPoints or 0) <= 0 then return nil end
  for _, key in ipairs(Skills.forClass(player.class)) do
    if not Skills.has(player, key) then
      local def = Skills.active[key] or Skills.passive[key]
      if player.level >= def.reqLevel then return key end
    end
  end
  return nil
end

function Game:hasCompanion()
  for _, entity in ipairs(self.level.entities) do
    if entity.kind == "companion" and entity:isAlive() then return true end
  end
  return false
end

function Game:hasHireling()
  for _, entity in ipairs(self.level.entities) do
    if entity.kind == "hireling" and entity:isAlive() then return true end
  end
  return false
end

-- Voluntary, penalty-free release of the live hireling, if any - contrast
-- Mercenaries.payWage's desertion, which fires on its own once loyalty
-- bottoms out from missed wages rather than on the player's own say-so.
function Game:dismissHireling()
  local name = Mercenaries.dismiss(self)
  if not name then
    self.log:add("you have no one under contract to release")
    return false
  end
  self.log:add("you release your " .. name .. " from service")
  return true
end

function Game:choosePlayerAction()
  local player = self.player
  local learnable = self:nextLearnableSkill()
  if learnable then self:learnSkill(learnable) end
  if not player.quest then
    local board = self.level:questBoardAt(player.x, player.y)
    if board and not board.claimed then self:tryAcceptQuest(board) end
  end
  if not self:anyMonsterVisible() then
    local upgrade = self:bestUpgrade()
    if upgrade then self:useItem(upgrade); return end
    if not self:hasCompanion() then
      local charm = self:findInInventory(function(item) return item.kind == Items.CHARM end)
      if charm then self:useItem(charm); return end
    end
    if not self:hasHireling() then
      local contract = self:findInInventory(function(item) return item.kind == Items.CONTRACT end)
      if contract then self:useItem(contract); return end
    end
    -- Only ever risks a shrine's first, cheapest, least cursed-prone prayer:
    -- the autopilot is not greedy enough to keep re-praying at rising odds.
    local shrine = self.level:shrineAt(player.x, player.y)
    if shrine and shrine.uses == 0 and player.gold >= Shrines.costFor(shrine) then
      self:prayAt(shrine)
      return
    end
    -- Restores whatever gear has actually stopped working the moment the
    -- purse can cover it, same "take it as soon as it's affordable" spirit
    -- as the shrine check just above.
    local brokenSlot = self:brokenEquippedSlot()
    if brokenSlot and player.gold >= Durability.repairCost(player[brokenSlot]) then
      self:repairEquipped(brokenSlot)
      return
    end
    -- Free income with no downside, so the autopilot takes it on sight
    -- rather than weighing it like a shrine's costed, risky prayer.
    local node = self.level:nodeAt(player.x, player.y)
    if node and not Nodes.isFallow(node) then
      self:harvestNode()
      return
    end
    -- Free protein with no gold cost, so the autopilot butchers a corpse on
    -- sight same as it strip-mines a node - but only while the meat is
    -- still good; a rotten one it leaves alone rather than poisoning itself
    -- for nothing.
    local corpse = self.level:corpseAt(player.x, player.y)
    if corpse and not Corpses.isRotten(corpse) then
      self:butcherCorpse()
      return
    end
    -- A chest is worth cracking on sight exactly like the node and corpse
    -- above, but only once it can actually be: an unlocked one is free
    -- money, and a locked one is only ever tried with a key or lockpick
    -- already in hand (see Game:openChest). Skipping a locked chest with
    -- neither on hand keeps the autopilot from parking on it and burning
    -- every remaining turn on a lock it has no way to open.
    local chest = self.level:chestAt(player.x, player.y)
    if chest and not chest.opened and (not Chests.isLocked(chest) or self:hasKey()
      or self:findInInventory(function(item) return item.kind == Items.LOCKPICK end)) then
      self:openChest()
      return
    end
    -- A held captive is worth cashing in on sight exactly like the chest
    -- above: the autopilot always takes the plain gold of Game:sellCaptive
    -- rather than gambling on Game:ransomCaptive's goodwill or
    -- Game:interrogateCaptive's map intel, neither of which it is smart
    -- enough here to weigh against the other.
    local captive = self.level:captiveAt(player.x, player.y)
    if captive then
      self:sellCaptive()
      return
    end
    -- A rift crossing is only ever attempted at good health: its own pocket
    -- floor is deliberately tuned harder than the main-track floor the rift
    -- itself sits on (see branches.lua), so the autopilot never spends its
    -- one shard gambling into a fight it is not ready for.
    if player.hp >= player.maxHp * 0.8 and self:enterRift() then
      return
    end
    -- Sheds the cheapest thing it is hauling once genuinely overloaded, but
    -- only in this same downtime window as the checks above - never instead
    -- of fighting or fleeing, since a visible monster always skips this
    -- whole block.
    if self:encumbranceTier() == Encumbrance.OVERLOADED then
      local junk = self:cheapestDroppableItem()
      if junk then self:dropItem(junk); return end
    end
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
    -- A carried net beats the killing blow once the target is already
    -- battered down to Captives.eligible's own threshold: a capture forgoes
    -- this kill's xp and essence, but a live captive can still be cashed in
    -- for gold moments later (see the sell-on-sight check above), so this is
    -- a trade the autopilot is always willing to make rather than a strict
    -- loss.
    if Captives.eligible(target) then
      local net = self:findInInventory(function(item) return item.kind == Items.NET end)
      if net then
        self:captureAt(net, target)
        return
      end
    end
    self:movePlayer(sign(target.x - player.x), sign(target.y - player.y))
    return
  end

  -- Across a rift, the only objective is its own pocket floor's exit: never
  -- the main track's descend/ascend goals below, which Game:descend and
  -- Game:ascend both refuse outright for as long as self.rift holds anyway.
  if self.rift then
    if player.x == self.level.downX and player.y == self.level.downY then
      self:exitRift()
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
    return
  end

  -- Once the amulet is in hand the objective flips: every remaining step
  -- heads for the up stairs instead of the down stairs, floor by floor.
  local goalX, goalY = self.level.downX, self.level.downY
  if self:hasAmulet() then
    goalX, goalY = self.level.upX, self.level.upY
    if player.x == goalX and player.y == goalY then
      self:ascend()
      return
    end
  elseif self.depth < self.maxDepth and player.x == goalX and player.y == goalY then
    self:descend()
    return
  end
  local path = self:playerPathTo(goalX, goalY)
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
  if not Hunger.suppressesRegen(self.player) then
    local ringRegen = Artifacts.ringRegen(self.player) + Sets.regenAmount(self.player)
    if ringRegen > 0 then
      self.player.hp = math.min(self.player.maxHp, self.player.hp + ringRegen)
    end
    local weatherRegen = Atmosphere.regenBonus(self.level.weather)
    if weatherRegen > 0 then
      self.player.hp = math.min(self.player.maxHp, self.player.hp + weatherRegen)
    end
  end
  local curseDrain = Curses.drainAmount(self.player)
  if curseDrain > 0 then
    self.player.hp = self.player.hp - curseDrain
    self.log:add("a cursed affliction saps your strength")
  end
  local diseaseLine = Disease.tick(self.player)
  if diseaseLine then self.log:add(diseaseLine) end
  local hungerLine = Hunger.tick(self.player)
  if hungerLine then self.log:add(hungerLine) end
  if self.player.light.fuel > 0 then
    self.player.light.fuel = self.player.light.fuel - 1
  end
  if self.player.mana < self.player.maxMana then
    self.player.mana = self.player.mana + 1
  end
end

function Game:endPlayerTurn()
  self.turnState = nil
  Scheduler.spend(self.player)
  self:hungerTorchTick()
  Hazards.step(self.level, self.rng)
  Nodes.step(self.level)
  Corpses.step(self.level)
  for _, trap in ipairs(Disarm.sweep(self.level, self.rng, self.player.x, self.player.y)) do
    self.log:add("you notice a hidden trap nearby")
  end
  for _, door in ipairs(Secrets.sweep(self.level, self.rng, self.player.x, self.player.y)) do
    self.log:add("you notice a hidden door in the wall")
  end
  local eventLine = Events.step(self.level, self.rng)
  if eventLine then self.log:add(eventLine) end
  Skills.tickCooldowns(self.player)
  self:resolveQuest()
  self.turn = self.turn + 1
  if self.turn % Mercenaries.WAGE_INTERVAL == 0 then
    local wageLine = Mercenaries.payWage(self)
    if wageLine then self.log:add(wageLine) end
  end
  self:computeVisible()
  local sanityLine = Sanity.tick(self)
  if sanityLine then self.log:add(sanityLine) end
  if Sanity.rollScream(self.rng, self) then
    self.log:add("a scream of raw terror tears from your throat")
  end
  if self.horde then
    local hordeLine = Horde.tick(self)
    if hordeLine then self.log:add(hordeLine) end
  end
end

-- Spends a skill point to permanently learn `key`, gated by class, level and
-- point balance (see skills.lua). Free of any turn cost.
function Game:learnSkill(key)
  local success, message = Skills.learn(self.player, key)
  if message then self.log:add(message) end
  return success
end

-- Attempts to use the active skill `key`, forwarding any extra arguments
-- (a target monster, or two for multishot) straight to skills.lua.
function Game:useSkill(key, ...)
  local success, lines = Skills.use(self, key, ...)
  self.log:addAll(lines)
  return success
end

-- Shared head of any player turn, whether the autopilot or a typed command
-- is about to decide what happens next: runs every other actor up to the
-- player, ticks the status/water/hazard afflictions that land on the
-- player's own turn boundary, and rolls the stun/panic checks that can
-- consume the turn before any action is even chosen. Returns "halt" once
-- play cannot continue this call (already won, or dead at any point along
-- the way - the caller must not act or spend a turn), "skip" once the turn
-- is already spent on a stun or a panic scream, or "ready" once the caller
-- is clear to choose and perform an action of its own.
--
-- Cached on self.turnState until Game:endPlayerTurn clears it, so calling
-- this more than once before a turn is actually spent - the one new
-- situation Game:manualStep introduces, since a rejected typed command
-- spends no turn and its caller is free to just try again - never re-rolls
-- the stun/panic check or re-ticks poison, fire or hunger a second time for
-- a turn the player has not actually finished taking yet. Game:autoStep
-- never revisits an unspent turn this way, so the cache is invisible to it.
function Game:beginTurn()
  if self.turnState then return self.turnState end
  if self.won then self.turnState = "halt"; return "halt" end
  self:runToPlayer()
  if not self.player:isAlive() then self.turnState = "halt"; return "halt" end
  self.log:addAll(Status.tick(self.player))
  if not self.player:isAlive() then self.turnState = "halt"; return "halt" end
  Conductivity.tick(self.level, self.player)
  local hazardLine = Hazards.afflict(self.level, self.player)
  if hazardLine then self.log:add(hazardLine) end
  if not self.player:isAlive() then self.turnState = "halt"; return "halt" end
  if Status.skipsTurn(self.player) then
    self.log:add("you are stunned")
    self.turnState = "skip"
  elseif Sanity.rollPanic(self.rng, self.player) then
    self.log:add("terror seizes you and the turn slips away")
    self.turnState = "skip"
  else
    self.turnState = "ready"
  end
  return self.turnState
end

function Game:autoStep()
  local state = self:beginTurn()
  if state == "halt" then return end
  if state == "ready" then self:choosePlayerAction() end
  self:endPlayerTurn()
end

-- Human-driven counterpart to Game:autoStep: runs the exact same pre-turn
-- checks, then hands `text` to commands.lua instead of letting
-- choosePlayerAction decide on its own. Returns (consumesTurn, message) from
-- Commands.apply so a caller (warren.lua's --play REPL, or a test driving a
-- fixed script of commands) can tell a wasted keystroke from a turn the
-- world actually answered. A stun or panic rolled during beginTurn still
-- spends the turn and ends it exactly like autoStep, without ever looking at
-- `text` - the player was never in control of that turn to begin with.
function Game:manualStep(text)
  local state = self:beginTurn()
  if state == "halt" then return false, "there is nothing left to do" end
  if state == "skip" then
    self:endPlayerTurn()
    return true, nil
  end
  local consumesTurn, message = Commands.apply(self, text)
  -- "explore" (Game:autoExplore, wired up in commands.lua) can advance and
  -- close several turns entirely on its own inside this one call, unlike
  -- every other handler here which only ever acts within the single turn
  -- already opened above - self.turnState is already nil by the time it
  -- returns, so this must not end an already-ended turn a second time - and
  -- must never end one at all if the very last thing that happened was a
  -- halt (self.turnState == "halt"), exactly like Game:autoStep and this
  -- same function's own "halt" branch above never do either. Every other
  -- command leaves turnState exactly as beginTurn set it above ("ready"),
  -- so the extra check below is a no-op for them.
  if consumesTurn and self.turnState == "ready" then self:endPlayerTurn() end
  return consumesTurn, message
end

local EXPLORE_STEP_CAP = 2000

-- Repeats Game:exploreStep/Game:movePlayer turn after turn inside a single
-- call, the way autoexplore works in most other roguelikes, instead of
-- making the player retype "explore" once per step. Built on the exact same
-- beginTurn/endPlayerTurn pair Game:autoStep already drives, so monster AI,
-- status ticks and hazards all run normally on every turn it takes - the
-- only difference from a hand-typed run of single moves is that this stops
-- itself the instant something worth the player's attention shows up,
-- rather than walking on regardless. Returns (consumesTurn, message) in the
-- exact same shape every Commands.apply handler does: consumesTurn is true
-- iff at least one turn was actually spent, so "already interrupted before
-- moving at all" and "an ordinary rejected command" both read the same way
-- to a caller that only checks that first value.
function Game:autoExplore()
  local steps = 0
  while steps < EXPLORE_STEP_CAP do
    if self:anyHostileVisible() then
      if steps == 0 then return false, "a monster is already in sight" end
      return true, "you stop exploring - a monster is in sight"
    end
    local hpBefore = self.player.hp
    local state = self:beginTurn()
    if state == "halt" then
      if steps == 0 then return false, "there is nothing left to do" end
      return true, "you stop exploring"
    end
    if state == "ready" then
      local ex, ey = self:exploreStep()
      if not ex then
        if steps == 0 then return false, "there is nothing left to explore" end
        -- beginTurn above already ran this turn's monster moves and status
        -- ticks for real, even though there turns out to be nothing left to
        -- walk toward - so, unlike the steps == 0 case above (nothing at
        -- all has happened yet, left dangling for a retry within the same
        -- still-open turn, exactly like a rejected command), this turn must
        -- still be closed out properly rather than abandoned half-finished.
        self:endPlayerTurn()
        return true, "you have finished exploring"
      end
      self:movePlayer(ex, ey)
    end
    self:endPlayerTurn()
    steps = steps + 1
    if self.player.hp < hpBefore then
      return true, "you stop exploring - you have taken damage"
    end
  end
  return true, "you stop exploring - that is far enough for now"
end

local REST_STEP_CAP = 500

-- Repeats a do-nothing turn (Handlers.wait's own move) inside a single call
-- until the player's hp is back to full, the way "rest" works in most other
-- roguelikes, instead of making the player retype "wait" once per turn.
-- Built on the same beginTurn/endPlayerTurn pair Game:autoExplore already
-- drives, so status ticks, hazards and the passive hp regen sources that
-- actually restore hp (a regen ring or artifact, Status.REGEN, favorable
-- weather - see Game:hungerTorchTick and Status.tick) all run exactly as
-- they would turn by turn. Stops itself the instant a hostile comes into
-- sight, the player's hp actually drops, or two full turns in a row pass
-- with the player's hp completely unchanged - the last case catches the
-- common situation where none of those regen sources are active at all, so
-- waiting here would otherwise never do anything but burn turns up to the
-- safety cap below. Returns (consumesTurn, message) in the exact same shape
-- every other handler in commands.lua does, exactly like Game:autoExplore.
--
-- The "no progress" check deliberately waits for a *second* completed turn
-- (steps > 1) rather than judging the very first one: Game:manualStep (the
-- only caller a real player's typed "rest" ever goes through) already calls
-- Game:beginTurn once of its own, before Commands.apply even runs, to check
-- whether the turn is allowed to start at all - so by the time this loop's
-- own first Game:beginTurn call runs, self.turnState may already be primed
-- from that earlier call, and it is a no-op cache hit rather than a fresh
-- tick (see Game:beginTurn's own comment). Any regen this call's Status.tick
-- and Game:hungerTorchTick would otherwise have produced already landed on
-- self.player.hp *before* this function's very first hpBefore snapshot was
-- even taken, so a first-iteration hp==hpBefore reading is inconclusive, not
-- proof that nothing is healing the player - judging it anyway would have
-- reported a perfectly working regen ring as "nothing here is healing you"
-- after a single real turn every time rest is typed in the actual game.
-- Every iteration from the second one on always starts with self.turnState
-- already nil (this loop's own prior Game:endPlayerTurn call clears it), so
-- its own Game:beginTurn call is always a fresh tick there - reliable either
-- way this function is entered, direct or through Game:manualStep.
function Game:restUntilHealed()
  if self.player.hp >= self.player.maxHp then
    return false, "you are already at full health"
  end
  local steps = 0
  while steps < REST_STEP_CAP do
    if self:anyHostileVisible() then
      if steps == 0 then return false, "a monster is already in sight" end
      return true, "you stop resting - a monster is in sight"
    end
    local hpBefore = self.player.hp
    local state = self:beginTurn()
    if state == "halt" then
      if steps == 0 then return false, "there is nothing left to do" end
      return true, "you stop resting"
    end
    self:endPlayerTurn()
    steps = steps + 1
    if self.player.hp >= self.player.maxHp then
      return true, "you rest until your wounds close"
    end
    if self.player.hp < hpBefore then
      return true, "you stop resting - you have taken damage"
    end
    if steps > 1 and self.player.hp == hpBefore then
      return true, "you stop resting - nothing here is healing you"
    end
  end
  return true, "you stop resting - that is far enough for now"
end

local TRAVEL_STEP_CAP = 500

-- Repeats Game:playerPathTo/Game:movePlayer turn after turn toward a fixed
-- destination inside a single call, the way "travel"/autotravel works in
-- most other roguelikes (DCSS's `>`, Brogue's travel cursor) - instead of
-- making the player retype a direction once per step to walk back to a spot
-- they already know is safe (the stairs they just left behind). Built on the
-- exact same beginTurn/endPlayerTurn pair Game:autoExplore/Game:restUntilHealed
-- already drive, so monster AI, status ticks and hazards all run normally on
-- every turn it takes. Reuses Game:playerPathTo, the same pathfinder
-- choosePlayerAction already relies on to walk the autopilot toward the
-- stairs turn by turn - this only exposes that existing primitive to a typed
-- command instead of teaching a second way to path anywhere. Stops itself
-- the instant a hostile comes into sight, the player's hp actually drops, the
-- destination is reached, or the route becomes blocked (a monster or a
-- spawned block stepped onto the only way through). Returns (consumesTurn,
-- message) in the exact same shape every other Commands.apply handler does.
function Game:travelTo(tx, ty)
  if self.player.x == tx and self.player.y == ty then
    return false, "you are already there"
  end
  if not self:playerPathTo(tx, ty) then
    return false, "you cannot find a path there"
  end
  local steps = 0
  while steps < TRAVEL_STEP_CAP do
    if self:anyHostileVisible() then
      if steps == 0 then return false, "a monster is already in sight" end
      return true, "you stop traveling - a monster is in sight"
    end
    local hpBefore = self.player.hp
    local state = self:beginTurn()
    if state == "halt" then
      if steps == 0 then return false, "there is nothing left to do" end
      return true, "you stop traveling"
    end
    if state == "ready" then
      local path = self:playerPathTo(tx, ty)
      if not path or #path < 2 then
        -- beginTurn above already ran this turn's monster moves and status
        -- ticks for real (see Game:autoExplore's own "nothing left to
        -- explore" branch for the identical reasoning), so unlike the
        -- steps == 0 case below - where nothing has happened yet and the
        -- turn is left open for a retry, exactly like a rejected command -
        -- a route that only went dead after steps have already been taken
        -- must close out the turn that already ran rather than abandon it
        -- half-finished.
        if steps == 0 then return false, "you cannot find a path there" end
        self:endPlayerTurn()
        return true, "you stop traveling - the way is blocked"
      end
      self:movePlayer(path[2].x - self.player.x, path[2].y - self.player.y)
    end
    self:endPlayerTurn()
    steps = steps + 1
    if self.player.x == tx and self.player.y == ty then
      return true, "you arrive"
    end
    if self.player.hp < hpBefore then
      return true, "you stop traveling - you have taken damage"
    end
  end
  return true, "you stop traveling - that is far enough for now"
end

function Game:render()
  return Render.frame(self)
end

function Game:toData()
  return {
    seed = self.seed,
    depth = self.depth,
    turn = self.turn,
    won = self.won,
    monsterSeq = self.monsterSeq,
    deepestDepth = self.deepestDepth,
    stats = self.stats,
    rng = self.rng:serialize(),
    identify = self.identify,
    dungeon = self.dungeon:toData(),
    player = self.player:toData(),
    playerExtra = {
      satiation = self.player.satiation, sanity = self.player.sanity, light = self.player.light,
      level = self.player.level, xp = self.player.xp, xpNext = self.player.xpNext,
      mana = self.player.mana, maxMana = self.player.maxMana, spellsKnown = self.player.spellsKnown,
      gold = self.player.gold, essence = self.player.essence,
      class = self.player.class, skills = self.player.skills,
      skillPoints = self.player.skillPoints, skillCooldowns = self.player.skillCooldowns,
      quest = self.player.quest, reputation = self.player.reputation,
      pendingPoisonBlade = self.player.pendingPoisonBlade,
    },
    log = self.log:toData(),
    compendium = self.compendium,
    ascension = self.ascension,
    nemesis = self.nemesis,
    rift = self.rift or false,
    riftLevels = Branches.levelsToData(self.riftLevels),
    riftReturn = self.riftReturn and {
      depth = self.riftReturn.depth, x = self.riftReturn.x, y = self.riftReturn.y,
    } or nil,
    -- The arena itself lives outside self.dungeon (see Game:startHorde), so
    -- without its own snapshot here a mid-arena save would resume from
    -- self.dungeon:get(self.depth) instead - the ordinary floor the arena
    -- replaced, abandoned but still cached. horde.wave rides along in the
    -- same field, since a restored arena with no wave counter would strand
    -- the player once the surviving wave dies with nothing left to trigger
    -- the next one.
    horde = self.horde,
    hordeLevel = self.horde and self.level:toData() or nil,
  }
end

-- Expects a complete, current-shape snapshot: every field GameSave's
-- migration chain owns (essence, the skill-tree fields, reputation, sanity,
-- stats.vaultsOpened/setPiecesFound - see the migrations above) must already
-- be present. Game.load guarantees that by running GameSave.load first;
-- Game:toData()'s own output always has them too. A handful of unversioned
-- fields (won, monsterSeq, deepestDepth, the whole stats table) keep their
-- own "or" defaults here since they can be missing outright rather than just
-- missing individual leaves, which the migration chain does not model.
function Game.fromData(snapshot)
  local game = setmetatable({}, Game)
  game.seed = snapshot.seed
  game.depth = snapshot.depth
  game.turn = snapshot.turn
  game.won = snapshot.won or false
  game.monsterSeq = snapshot.monsterSeq or 0
  game.deepestDepth = snapshot.deepestDepth or snapshot.depth
  game.stats = snapshot.stats or {
    kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, vaultsOpened = 0,
    setPiecesFound = 0,
  }
  game.rng = Rng.deserialize(snapshot.rng)
  game.identify = snapshot.identify
  game.dungeon = Dungeon.fromData(snapshot.dungeon)
  game.maxDepth = Builder.maxDepth(game.dungeon.options)
  game.rift = snapshot.rift or false
  game.riftLevels = Branches.levelsFromData(snapshot.riftLevels)
  game.riftReturn = snapshot.riftReturn and {
    depth = snapshot.riftReturn.depth, x = snapshot.riftReturn.x, y = snapshot.riftReturn.y,
    level = game.dungeon:get(snapshot.riftReturn.depth),
  } or nil
  game.horde = snapshot.horde
  game.level = game.horde and Level.fromData(snapshot.hordeLevel)
    or (game.rift and game.riftLevels[game.depth] or game.dungeon:get(game.depth))
  game.player = Entity.fromData(snapshot.player)
  game.player.satiation = snapshot.playerExtra.satiation
  game.player.sanity = snapshot.playerExtra.sanity
  game.player.light = snapshot.playerExtra.light
  game.player.level = snapshot.playerExtra.level
  game.player.xp = snapshot.playerExtra.xp
  game.player.xpNext = snapshot.playerExtra.xpNext
  game.player.mana = snapshot.playerExtra.mana
  game.player.maxMana = snapshot.playerExtra.maxMana
  game.player.spellsKnown = snapshot.playerExtra.spellsKnown
  game.player.gold = snapshot.playerExtra.gold
  game.player.essence = snapshot.playerExtra.essence
  game.player.class = snapshot.playerExtra.class
  game.player.skills = snapshot.playerExtra.skills
  game.player.skillPoints = snapshot.playerExtra.skillPoints
  game.player.skillCooldowns = snapshot.playerExtra.skillCooldowns
  game.player.quest = snapshot.playerExtra.quest
  game.player.reputation = snapshot.playerExtra.reputation
  game.player.pendingPoisonBlade = snapshot.playerExtra.pendingPoisonBlade
  game.log = MessageLog.fromData(snapshot.log)
  game.compendium = snapshot.compendium or Compendium.new()
  game.ascension = snapshot.ascension or {}
  game.nemesis = snapshot.nemesis
  game.visible = {}
  game:computeVisible()
  return game
end

function Game:save(path)
  GameSave.save(path, self:toData())
end

function Game.load(path)
  local data, err = GameSave.load(path)
  if not data then
    error("cannot load save " .. path .. ": " .. err)
  end
  return Game.fromData(data)
end

return Game
