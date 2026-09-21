local Curses = {}

Curses.WEAKNESS = "weakness"
Curses.BRITTLE = "brittle"
Curses.FAULTY = "faulty"
Curses.AFFLICTION = "affliction"

Curses.SLOTS = { "weapon", "armor", "ring", "bow" }

Curses.pool = {
  weapon = { { key = Curses.WEAKNESS, powerPenalty = 2 } },
  armor = { { key = Curses.BRITTLE, powerPenalty = 2 } },
  bow = { { key = Curses.FAULTY, powerPenalty = 1, rangePenalty = 2 } },
  ring = { { key = Curses.AFFLICTION, drain = 1 } },
}

Curses.CHANCE_NUMERATOR = 1
Curses.CHANCE_DENOMINATOR = 8

function Curses.roll(rng, slot)
  local pool = Curses.pool[slot]
  if not pool then return nil end
  if not rng:chance(Curses.CHANCE_NUMERATOR, Curses.CHANCE_DENOMINATOR) then return nil end
  return pool[rng:range(1, #pool)]
end

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

function Curses.isBoundIn(entity, slot)
  return Curses.isCursed(entity[slot])
end

function Curses.tryRelease(entity, slot)
  local item = entity[slot]
  if not Curses.isCursed(item) then return true end
  Curses.reveal(item)
  return false
end

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

function Curses.cleanseWorn(entity)
  local count = 0
  for _, slot in ipairs(Curses.SLOTS) do
    if Curses.cleanse(entity[slot]) then count = count + 1 end
  end
  return count
end

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

function Curses.drainAmount(entity)
  local ring = entity.ring
  if ring and ring.curseDrain then return ring.curseDrain end
  return 0
end

function Curses.label(item, name)
  if Curses.isCursed(item) and Curses.isRevealed(item) then
    return "cursed " .. name
  end
  return name
end

return Curses
