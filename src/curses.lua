-- Malevolent gear rolled as the dark mirror of affixes.lua's beneficial
-- prefixes. A cursed weapon, suit of armor, bow or ring looks completely
-- ordinary on the ground and in the pack - its stat penalty is already
-- folded into item.power/item.range at generation time, so nothing
-- downstream needs to know an item is cursed to use its numbers correctly.
-- Putting one on binds it in place: trying to swap it out for something
-- else fails and reveals the curse right there, the same "you find out by
-- trying" moment as a classic roguelike's stuck cursed ring. This is a
-- different curse from shrines.lua's: that one is a temporary status
-- inflicted the instant a prayer backfires, this one travels with a
-- specific item and needs a specific remedy - a scroll of remove curse, or
-- a prayer at a shrine of fortune - to lift.

local Curses = {}

Curses.WEAKNESS = "weakness"
Curses.BRITTLE = "brittle"
Curses.FAULTY = "faulty"
Curses.AFFLICTION = "affliction"

-- The four wearable slots a curse can ever occupy, in a fixed order so
-- "the earliest cursed slot" always means the same thing across callers.
Curses.SLOTS = { "weapon", "armor", "ring", "bow" }

Curses.pool = {
  weapon = { { key = Curses.WEAKNESS, powerPenalty = 2 } },
  armor = { { key = Curses.BRITTLE, powerPenalty = 2 } },
  bow = { { key = Curses.FAULTY, powerPenalty = 1, rangePenalty = 2 } },
  ring = { { key = Curses.AFFLICTION, drain = 1 } },
}

Curses.CHANCE_NUMERATOR = 1
Curses.CHANCE_DENOMINATOR = 8

-- Rolls a curse for a freshly generated `slot` item, or nil most of the
-- time. Weapons and armor should only ever be offered here when they did
-- not already land a beneficial affix (see builder.lua's rollItem), so a
-- single drop is never simultaneously a blessing and a curse.
function Curses.roll(rng, slot)
  local pool = Curses.pool[slot]
  if not pool then return nil end
  if not rng:chance(Curses.CHANCE_NUMERATOR, Curses.CHANCE_DENOMINATOR) then return nil end
  return pool[rng:range(1, #pool)]
end

-- Binds `curse` onto `item`, silently folding its stat penalty into the
-- item's own numbers. The curse itself stays hidden (curseRevealed false)
-- until reveal() is called by a discovery path.
function Curses.afflict(item, curse)
  item.cursed = true
  item.curseKind = curse.key
  item.curseRevealed = false
  if curse.powerPenalty then
    item.cursePenalty = curse.powerPenalty
    item.power = math.max(0, item.power - curse.powerPenalty)
  end
  if curse.rangePenalty then
    item.curseRangePenalty = curse.rangePenalty
    item.range = math.max(1, item.range - curse.rangePenalty)
  end
  if curse.drain then
    item.curseDrain = curse.drain
  end
  return item
end

function Curses.isCursed(item)
  return item ~= nil and item.cursed == true
end

function Curses.isRevealed(item)
  return item ~= nil and item.curseRevealed == true
end

function Curses.reveal(item)
  if item then item.curseRevealed = true end
end

-- True once whatever `entity` currently has worn in `slot` is cursed.
function Curses.isBoundIn(entity, slot)
  return Curses.isCursed(entity[slot])
end

-- Refuses to let go of a bound item: reveals the curse the instant the
-- wearer discovers it - the whole point of the mechanic is finding out by
-- trying - and reports false so the caller can leave the replacement
-- sitting in the pack instead of swapping it in. An empty or clean slot
-- always succeeds without side effects.
function Curses.tryRelease(entity, slot)
  local item = entity[slot]
  if not Curses.isCursed(item) then return true end
  Curses.reveal(item)
  return false
end

-- Undoes `item`'s curse in place: restores whatever power/range it cost,
-- drops the drain, and clears every curse field so the piece swaps out
-- normally from here on. No-op (returns false) on clean or absent gear.
function Curses.cleanse(item)
  if not Curses.isCursed(item) then return false end
  if item.cursePenalty then
    item.power = item.power + item.cursePenalty
    item.cursePenalty = nil
  end
  if item.curseRangePenalty then
    item.range = item.range + item.curseRangePenalty
    item.curseRangePenalty = nil
  end
  item.curseDrain = nil
  item.cursed = nil
  item.curseKind = nil
  item.curseRevealed = nil
  return true
end

-- Lifts every curse currently worn by `entity` across all four slots,
-- returning how many pieces were cleansed - 0 when none of its gear was
-- cursed to begin with, so callers can report "nothing to cleanse".
function Curses.cleanseWorn(entity)
  local count = 0
  for _, slot in ipairs(Curses.SLOTS) do
    if Curses.cleanse(entity[slot]) then count = count + 1 end
  end
  return count
end

-- Reveals the first still-hidden curse among `entity`'s worn gear, in
-- Curses.SLOTS order, and returns the item it found - or nil once nothing
-- worn is hiding a curse anymore.
function Curses.revealFirstUnknown(entity)
  for _, slot in ipairs(Curses.SLOTS) do
    local item = entity[slot]
    if Curses.isCursed(item) and not Curses.isRevealed(item) then
      Curses.reveal(item)
      return item
    end
  end
  return nil
end

-- The hit points a cursed ring bleeds from its wearer this round. Only a
-- ring's affliction drains on a timer - weapon, armor and bow curses are a
-- flat, one-time stat tax instead - so this is the only per-turn cost the
-- whole system has.
function Curses.drainAmount(entity)
  local ring = entity.ring
  if ring and ring.curseDrain then return ring.curseDrain end
  return 0
end

-- Display name for `item`: an unrevealed curse hides behind the item's
-- ordinary name exactly like a clean piece, a revealed one is prefixed so
-- the player never again mistakes it for something safe to swap out.
function Curses.label(item, name)
  if Curses.isCursed(item) and Curses.isRevealed(item) then
    return "cursed " .. name
  end
  return name
end

return Curses
