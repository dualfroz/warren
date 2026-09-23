local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Game = require("game")
local Curses = require("curses")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.cursesRollRespectsItsOneInEightChanceAcrossSeedsAndKnownSlots()
  local hit, miss = false, false
  for seed = 1, 60 do
    local curse = Curses.roll(Rng.new(seed), "weapon")
    if curse then hit = true else miss = true end
    if hit and miss then break end
  end
  ok(hit, "a weapon curse fires on at least one seed in the first 60")
  ok(miss, "a weapon curse also misses on at least one seed in the first 60")
  eq(Curses.roll(Rng.new(1), "amulet"), nil, "an unsupported slot never rolls a curse")
end

function tests.cursesAfflictFoldsThePenaltyIntoTheItemAndKeepsItHidden()
  local weapon = Items.weapon("dagger", 5)
  Curses.afflict(weapon, Curses.pool.weapon[1])
  eq(weapon.power, 3, "a weakness curse folds its penalty directly into the weapon's power")
  eq(weapon.cursed, true, "the item is marked cursed")
  eq(weapon.curseRevealed, false, "the curse starts hidden")
  eq(weapon.name, "dagger", "an unrevealed curse never touches the item's displayed name")

  local bow = Items.bow("short bow", 2, 5)
  Curses.afflict(bow, Curses.pool.bow[1])
  eq(bow.power, 1, "a faulty curse also taxes a bow's power")
  eq(bow.range, 3, "a faulty curse shortens a bow's range")

  local ring = Items.ring("ring of power", 1, 1)
  Curses.afflict(ring, Curses.pool.ring[1])
  eq(ring.attack, 1, "an affliction curse leaves a ring's own stats untouched")
  eq(ring.curseDrain, 1, "an affliction curse instead sets a per-turn drain")
end

function tests.cursesAfflictNeverDropsPowerOrRangeBelowItsFloor()
  local dagger = Items.weapon("dagger", 1)
  Curses.afflict(dagger, { key = "test", powerPenalty = 5 })
  eq(dagger.power, 0, "power never drops below zero even with an oversized penalty")

  local bow = Items.bow("short bow", 2, 1)
  Curses.afflict(bow, { key = "test", rangePenalty = 5 })
  eq(bow.range, 1, "range never drops below one even with an oversized penalty")
end

function tests.cursesIsCursedAndIsRevealedReadEmptyOrCleanGearSafely()
  eq(Curses.isCursed(nil), false, "a nil slot is never cursed")
  local clean = Items.weapon("sword", 4)
  eq(Curses.isCursed(clean), false, "a plain item is never cursed")
  eq(Curses.isRevealed(clean), false, "a plain item has nothing to reveal")
  Curses.afflict(clean, Curses.pool.weapon[1])
  eq(Curses.isCursed(clean), true, "afflict marks the item cursed")
  eq(Curses.isRevealed(clean), false, "afflict alone does not reveal the curse")
  Curses.reveal(clean)
  eq(Curses.isRevealed(clean), true, "reveal flips the item to known")
  Curses.reveal(nil)
  ok(true, "revealing a nil item is a safe no-op")
end

function tests.cursesIsBoundInChecksASpecificEquippedSlot()
  local entity = { weapon = Items.weapon("sword", 4), armor = nil }
  eq(Curses.isBoundIn(entity, "weapon"), false, "a clean equipped weapon is not bound")
  eq(Curses.isBoundIn(entity, "armor"), false, "an empty slot is never bound")
  Curses.afflict(entity.weapon, Curses.pool.weapon[1])
  eq(Curses.isBoundIn(entity, "weapon"), true, "a cursed equipped weapon reads as bound")
end

function tests.cursesTryReleaseRevealsAndRefusesABoundSlotButPassesACleanOne()
  local entity = { weapon = Items.weapon("sword", 4) }
  eq(Curses.tryRelease(entity, "weapon"), true, "a clean weapon releases without resistance")
  eq(Curses.tryRelease(entity, "armor"), true, "an empty slot always releases")
  Curses.afflict(entity.weapon, Curses.pool.weapon[1])
  eq(Curses.tryRelease(entity, "weapon"), false, "a bound weapon refuses to release")
  eq(Curses.isRevealed(entity.weapon), true, "the failed release reveals the curse")
end

function tests.cursesCleanseUndoesThePenaltyAndClearsEveryField()
  local weapon = Items.weapon("dagger", 5)
  Curses.afflict(weapon, Curses.pool.weapon[1])
  eq(Curses.cleanse(weapon), true, "cleansing a cursed weapon reports success")
  eq(weapon.power, 5, "cleansing restores the weapon's original power")
  eq(weapon.cursed, nil, "cleansing clears the cursed flag")
  eq(weapon.curseKind, nil, "cleansing clears the curse kind")
  eq(weapon.curseRevealed, nil, "cleansing clears the revealed flag")
  eq(weapon.cursePenalty, nil, "cleansing clears the stored penalty")
  eq(Curses.cleanse(weapon), false, "cleansing an already-clean item is a no-op")

  local ring = Items.ring("ring of power", 0, 0)
  Curses.afflict(ring, Curses.pool.ring[1])
  Curses.cleanse(ring)
  eq(ring.curseDrain, nil, "cleansing a ring also drops its drain")
end

function tests.cursesCleanseWornLiftsEveryCursedSlotAndCountsThem()
  local entity = {
    weapon = Curses.afflict(Items.weapon("dagger", 5), Curses.pool.weapon[1]),
    armor = Items.armor("leather armor", 1),
    ring = Curses.afflict(Items.ring("ring of power", 0, 0), Curses.pool.ring[1]),
  }
  eq(Curses.cleanseWorn(entity), 2, "cleanseWorn reports exactly the cursed pieces it lifted")
  eq(Curses.isCursed(entity.weapon), false, "the cursed weapon is clean afterward")
  eq(Curses.isCursed(entity.ring), false, "the cursed ring is clean afterward")
  eq(Curses.cleanseWorn(entity), 0, "a second pass finds nothing left to cleanse")
end

function tests.cursesRevealFirstUnknownFindsEarliestSlotAndAdvances()
  local entity = {
    weapon = Curses.afflict(Items.weapon("dagger", 5), Curses.pool.weapon[1]),
    armor = Curses.afflict(Items.armor("leather armor", 1), Curses.pool.armor[1]),
  }
  local first = Curses.revealFirstUnknown(entity)
  eq(first, entity.weapon, "weapon slot order comes before armor")
  eq(Curses.isRevealed(entity.weapon), true, "the found curse is now revealed")
  local second = Curses.revealFirstUnknown(entity)
  eq(second, entity.armor, "the next call advances to the still-hidden armor curse")
  eq(Curses.revealFirstUnknown(entity), nil, "nothing left hidden once both are revealed")
end

function tests.cursesDrainAmountOnlyReadsACursedRing()
  local entity = {}
  eq(Curses.drainAmount(entity), 0, "no ring means no drain")
  entity.weapon = Curses.afflict(Items.weapon("dagger", 5), Curses.pool.weapon[1])
  eq(Curses.drainAmount(entity), 0, "a cursed weapon never drains hp")
  entity.ring = Items.ring("ring of power", 0, 0)
  eq(Curses.drainAmount(entity), 0, "a clean ring drains nothing")
  Curses.afflict(entity.ring, Curses.pool.ring[1])
  eq(Curses.drainAmount(entity), 1, "a cursed ring's affliction drains its fixed amount")
end

function tests.cursesLabelHidesUntilRevealedThenPrefixes()
  local weapon = Items.weapon("dagger", 5)
  eq(Curses.label(weapon, "dagger"), "dagger", "a clean item's label is untouched")
  Curses.afflict(weapon, Curses.pool.weapon[1])
  eq(Curses.label(weapon, "dagger"), "dagger", "an unrevealed curse still hides behind the plain label")
  Curses.reveal(weapon)
  eq(Curses.label(weapon, "dagger"), "cursed dagger", "a revealed curse prefixes the label")
end

function tests.gameEquippingOverABoundCursedWeaponFailsAndRevealsTheCurse()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.weapon = Curses.afflict(Items.weapon("dagger", 2), Curses.pool.weapon[1])
  game.player.inventory = { Items.weapon("sword", 4) }
  local before = game.player.weapon
  eq(game:useItem(1), false, "equipping a new weapon over a bound one fails")
  ok(game.player.weapon == before, "the bound weapon stays equipped")
  eq(Curses.isRevealed(before), true, "the failed swap reveals the curse")
  eq(#game.player.inventory, 1, "the replacement weapon stays in the pack, never spent")
  ok(contains(game.log:last(), "will not come off"), "the log explains the weapon is stuck")
end

function tests.gameEquippingAFreshCurseHidesItUntilYouTryToTakeItOff()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local cursedRing = Curses.afflict(Items.ring("ring of power", 1, 1), Curses.pool.ring[1])
  game.player.inventory = { cursedRing }
  ok(game:useItem(1), "equipping an empty slot with a cursed item still succeeds")
  ok(game.player.ring == cursedRing, "the cursed ring is now equipped")
  ok(not contains(game.log:last(), "cursed"), "the equip message never spoils an unrevealed curse")
end

function tests.gameRemoveCurseScrollLiftsEveryCurseCurrentlyWorn()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.ring = Curses.afflict(Items.ring("ring of power", 0, 0), Curses.pool.ring[1])
  game.player.inventory = { Items.scroll("removecurse") }
  ok(game:useItem(1), "reading the scroll succeeds")
  eq(Curses.isCursed(game.player.ring), false, "the worn ring's curse is lifted")
  ok(contains(game.log:last(), "lifts"), "the log reports the cleansing")
end

function tests.cursedFieldsSurviveSerialization()
  local game = Game.new(3)
  game.player.ring = Curses.afflict(Items.ring("ring of power", 1, 1), Curses.pool.ring[1])
  Curses.reveal(game.player.ring)
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.ring.cursed, true, "a cursed ring's flag survives a save/load round trip")
  eq(restored.player.ring.curseDrain, 1, "a cursed ring's drain survives a save/load round trip")
  eq(restored.player.ring.curseRevealed, true, "a revealed curse stays revealed after reload")
end

return tests
