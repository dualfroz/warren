local Monsters = require("monsters")
local Bosses = require("bosses")

local Compendium = {}

Compendium.FLAVOR = {
  rat = "Bold enough to bite an ankle, never bold enough to fight fair.",
  bat = "Flits erratically through the dark on a course only it can hear.",
  kobold = "Travels in twos and threes; alone it barely has the nerve to bite.",
  goblin = "Quick with a rusty blade, quicker to run once its pack scatters.",
  archer = "A skeleton archer, more patient dead than most men are living.",
  orc = "Broad-shouldered muscle with no plan beyond the next swing.",
  wretch = "Something that used to be a person, now just hungry and afraid.",
  troll = "Wounds close almost as fast as they open; fire is the only argument it respects.",
  mage = "A dark mage who traded caution for whatever is behind that door.",
  dragon = "Young enough to still be reckless, old enough to already breathe fire.",
  zombie = "Shambles forward on rot and spite alone.",
  slime = "Splits when struck; killing one carelessly just makes two problems.",
  footpad = "Light-fingered and lighter on its feet - it wants your purse, not a fight.",
  shaman = "Chants curses from a safe distance and flees the moment that fails.",
  necromancer = "Would rather raise a friend from your kills than make one of its own.",
  cleric = "Keeps its allies standing longer than they have any right to.",
  chieftain = "Rallies its kin with a bellow that carries through the whole floor.",
  shopkeeper = "Minds its own business and its stock, right up until you take both.",
  warlord = "The Orc Warlord, whose rage only sharpens the longer a fight runs.",
  lich = "The Lich, a will that outlasted its own body decades ago.",
  bonequeen = "The Bone Queen, who never lacks for company - the dead keep answering her call.",
}

function Compendium.new()
  return { seen = {}, kills = {} }
end

function Compendium.noteSighting(compendium, speciesKey)
  if not speciesKey or compendium.seen[speciesKey] then return false end
  compendium.seen[speciesKey] = true
  return true
end

function Compendium.noteKill(compendium, speciesKey)
  if not speciesKey then return end
  compendium.kills[speciesKey] = (compendium.kills[speciesKey] or 0) + 1
end

function Compendium.killCount(compendium, speciesKey)
  return compendium.kills[speciesKey] or 0
end

function Compendium.hasSeen(compendium, speciesKey)
  return compendium.seen[speciesKey] == true
end

function Compendium.entries(compendium)
  local rows = {}
  for _, spec in ipairs(Monsters.species) do
    rows[#rows + 1] = {
      key = spec.key, name = spec.name, flavor = Compendium.FLAVOR[spec.key],
      seen = Compendium.hasSeen(compendium, spec.key),
      kills = Compendium.killCount(compendium, spec.key),
    }
  end
  for _, spec in ipairs(Bosses.catalog) do
    local key = "boss_" .. spec.key
    rows[#rows + 1] = {
      key = key, name = spec.name, flavor = Compendium.FLAVOR[spec.key],
      seen = Compendium.hasSeen(compendium, key),
      kills = Compendium.killCount(compendium, key),
    }
  end
  return rows
end

return Compendium
