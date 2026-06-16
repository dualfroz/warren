-- Cross-run bones: the moment a run ends in death (see warren.lua's --meta
-- path and Game:graveEntry), a grave entry is appended to meta.lua's
-- persistent save - what the fallen was still carrying, and how deep they
-- got. From the very next run on, Builder.build may roll one of those
-- graves onto a floor at or shallower than where it was dug (bones drift
-- upward over time, never down - see Graves.eligibleFor) as an inert
-- floorItem, drawn dead last of all so a run without any recorded deaths
-- (or one played without --meta at all) makes no extra rng draw and its
-- floor layouts stay byte-identical to before this module existed.
--
-- Unlike mimics.lua's disguise, a grave marker is honest about what it is -
-- disturbing it (Game:pickupHere, mirroring Game:triggerMimic) wakes a
-- vengeful shade rather than pretending to be ordinary loot. The shade's
-- hp and attack scale with how much the fallen was carrying at death, and
-- felling it in turn pays out a fraction of that same hoard - a richer
-- death makes for a tougher fight and a richer reward, but always strictly
-- less than what was actually lost.

local Entity = require("entity")
local Factions = require("factions")

local Graves = {}

-- Oldest graves fall off once a save accumulates more than this many, so a
-- long-lived meta file never grows without bound.
Graves.MAX_RECORDED = 20

-- Appends `entry` (see Game:graveEntry) to meta.graves, most recent first,
-- trimming anything past Graves.MAX_RECORDED.
function Graves.record(meta, entry)
  meta.graves = meta.graves or {}
  table.insert(meta.graves, 1, entry)
  while #meta.graves > Graves.MAX_RECORDED do
    table.remove(meta.graves)
  end
end

-- Graves eligible to be rolled onto `depth`: any dug at that depth or
-- deeper. A grave dug on floor 7 can still turn up waiting on floor 4, but
-- a floor 2 grave never surfaces on floor 7 - bones drift shallower with
-- time, never the other way around.
function Graves.eligibleFor(graves, depth)
  local eligible = {}
  if not graves then return eligible end
  for _, grave in ipairs(graves) do
    if grave.depth >= depth then eligible[#eligible + 1] = grave end
  end
  return eligible
end

-- The inert floorItem a builder drops for a rolled grave: visibly a grave
-- from the moment it is seen (no disguise to unmask), carrying just enough
-- of the fallen's own data for Graves.reveal to build their shade later.
function Graves.floorItem(grave)
  return {
    kind = "grave", grave = true, name = "a weathered grave marker", glyph = "b",
    graveClass = grave.className, graveGold = grave.gold, graveEssence = grave.essence,
  }
end

-- The hostile shade a grave marker becomes the instant it is disturbed:
-- hp and attack both scale with the wealth it is guarding, capped so even
-- the richest grave never spawns something the player cannot fight back
-- against. Mirrors Mimics.reveal's shape (a fresh monster entity, tagged so
-- awardKill and corpses.lua both know to treat it specially).
function Graves.reveal(id, x, y, ground)
  local gold = ground.graveGold or 0
  local essence = ground.graveEssence or 0
  local wealth = gold + essence * 2
  local bonusHp = math.min(20, wealth // 8)
  local bonusAttack = math.min(6, wealth // 30)
  local entity = Entity.new({
    id = id, x = x, y = y,
    glyph = "G", name = "vengeful shade", kind = "monster",
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

-- Flat xp reward for felling a revealed shade - kept separate from
-- Monsters.xpFor exactly like Mimics.xpFor, since a shade is never a
-- member of the wild bestiary Monsters.forDepth draws its per-floor
-- population from.
function Graves.xpFor()
  return 12
end

-- What a felled shade actually leaves behind: half the gold and a third of
-- the essence the fallen was carrying at the moment of death - the rest is
-- gone for good, so a grave is always a net loss across the two runs it
-- touches, never a way to launder wealth forward.
function Graves.lootFor(entity)
  local gold = (entity.graveGold or 0) // 2
  local essence = (entity.graveEssence or 0) // 3
  return gold, essence
end

return Graves
