local SaveGame = require("savegame")
local Ascension = require("ascension")
local Streaks = require("streaks")

local Meta = {}

local MetaSave = SaveGame.new({
  [1] = function(data)
    data.graves = data.graves or {}
    data.leaderboard = data.leaderboard or {}
    return data
  end,
  [2] = function(data)
    data.runHistory = data.runHistory or {}
    return data
  end,
})

Meta.PERKS = {
  { key = "vigor", name = "Vigor", cost = 30, apply = function(player)
      player.maxHp = player.maxHp + 5
      player.hp = player.hp + 5
    end },
  { key = "purse", name = "Deep Pockets", cost = 20, apply = function(player)
      player.gold = player.gold + 25
    end },
  { key = "focus", name = "Arcane Focus", cost = 25, apply = function(player)
      player.maxMana = player.maxMana + 5
      player.mana = player.mana + 5
    end },
  { key = "keeneye", name = "Keen Eye", cost = 40, apply = function(player)
      player.baseAttack = player.baseAttack + 1
      player.attack = player.attack + 1
    end },
  { key = "tough", name = "Thick Hide", cost = 40, apply = function(player)
      player.baseDefense = player.baseDefense + 1
      player.defense = player.defense + 1
    end },
  { key = "lightbearer", name = "Lightbearer", cost = 25, apply = function(player)
      player.light.fuel = player.light.fuel + 200
      player.light.radius = player.light.radius + 1
    end },
}

Meta.byKey = {}
for _, def in ipairs(Meta.PERKS) do
  Meta.byKey[def.key] = def
end

Meta.ACHIEVEMENTS = {
  { key = "first_blood", name = "First Blood", condition = function(stats) return stats.kills >= 1 end },
  { key = "boss_slayer", name = "Boss Slayer", condition = function(stats) return stats.bossKills >= 1 end },
  { key = "deep_delver", name = "Deep Delver", condition = function(stats) return stats.deepestDepth >= 5 end },
  { key = "bounty_hunter", name = "Bounty Hunter", condition = function(stats) return stats.questsCompleted >= 3 end },
  { key = "artificer", name = "Artificer", condition = function(stats) return stats.artifactsFound >= 1 end },
  { key = "vault_breaker", name = "Vault Breaker", condition = function(stats) return (stats.vaultsOpened or 0) >= 1 end },
  { key = "set_collector", name = "Set Collector", condition = function(stats) return (stats.setPiecesFound or 0) >= 3 end },
  { key = "amulet_bearer", name = "Amulet Bearer", condition = function(stats) return stats.won end },
  { key = "hoarder", name = "Hoarder", condition = function(stats) return (stats.chestsOpened or 0) >= 3 end },
  { key = "comeback", name = "Comeback", condition = function(stats, meta)
      local h = meta.runHistory
      return stats.won == true and #h >= 2 and h[#h] == true and h[#h - 1] == false
    end },
}

function Meta.new()
  return {
    renown = 0, totalRuns = 0, wins = 0, bestDepth = 0,
    achievements = {}, perks = {}, graves = {}, leaderboard = {}, runHistory = {},
  }
end

function Meta.load(path)
  local data, err = MetaSave.load(path)
  if not data then
    if err ~= "missing" then
      io.stderr:write("warning: meta file " .. path .. " is " .. err .. "; starting fresh\n")
    end
    return Meta.new()
  end
  data.renown = data.renown or 0
  data.totalRuns = data.totalRuns or 0
  data.wins = data.wins or 0
  data.bestDepth = data.bestDepth or 0
  data.achievements = data.achievements or {}
  data.perks = data.perks or {}
  return data
end

function Meta.save(meta, path)
  MetaSave.save(path, meta)
end

function Meta.renownFor(stats)
  local total = stats.deepestDepth * 4 + stats.bossKills * 15 + stats.questsCompleted * 8
    + (stats.vaultsOpened or 0) * 10 + (stats.setPiecesFound or 0) * 3 + (stats.chestsOpened or 0) * 2
  if stats.won then total = total + 100 end
  local bonusPercent = Ascension.renownBonusPercent(stats.mutators)
  if bonusPercent > 0 then
    total = total + (total * bonusPercent) // 100
  end
  return total
end

function Meta.recordRun(meta, stats)
  meta.totalRuns = meta.totalRuns + 1
  if stats.won then meta.wins = meta.wins + 1 end
  if stats.deepestDepth > meta.bestDepth then meta.bestDepth = stats.deepestDepth end
  meta.renown = meta.renown + Meta.renownFor(stats)
  Streaks.record(meta.runHistory, stats.won == true)
  local unlocked = {}
  for _, ach in ipairs(Meta.ACHIEVEMENTS) do
    if not meta.achievements[ach.key] and ach.condition(stats, meta) then
      meta.achievements[ach.key] = true
      unlocked[#unlocked + 1] = ach.name
    end
  end
  return unlocked
end

function Meta.isOwned(meta, key)
  return meta.perks[key] == true
end

function Meta.purchase(meta, key)
  local def = Meta.byKey[key]
  if not def then return false, "no such perk" end
  if meta.perks[key] then return false, "already owned" end
  if meta.renown < def.cost then return false, "not enough renown" end
  meta.renown = meta.renown - def.cost
  meta.perks[key] = true
  return true, "unlocked " .. def.name
end

function Meta.applyAll(meta, player)
  for _, def in ipairs(Meta.PERKS) do
    if meta.perks[def.key] then def.apply(player) end
  end
end

return Meta
