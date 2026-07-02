-- Progression that survives a single run: a "renown" currency banked when a
-- run ends (in death or victory), scored from that run's own tally, plus
-- achievements unlocked once a run's tally crosses a fixed threshold and
-- permanent perks bought with banked renown. Meta state lives in its own
-- save file (see warren.lua's --meta flag), entirely separate from a
-- mid-run save (serialize.lua/game.lua toData) - a run ending in death still
-- destroys that run's save, but its renown and any newly met achievement
-- persist into the next one.
--
-- A perk is applied once, in Game.new, before options.class runs (see
-- Meta.applyAll's caller) so a class delta always lands on top of whatever a
-- perk already raised - the same ordering classes.lua itself relies on for
-- its own one-time deltas.

local SaveGame = require("savegame")
local Ascension = require("ascension")
local Streaks = require("streaks")

local Meta = {}

-- Real feature history, oldest first: graves and the leaderboard arrived
-- after the original renown/achievements/perks core, and runHistory (for
-- Streaks) after that - so a meta file written before either feature landed
-- is missing those fields, not just hypothetically but in practice for any
-- save from before this module tracked them.
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

-- Each condition reads a run's own metaStats snapshot (see Game:metaStats):
-- deepestDepth, kills, bossKills, questsCompleted, artifactsFound,
-- vaultsOpened, setPiecesFound, chestsOpened, won - plus, for the rare
-- condition that needs more than a single run's own tally can offer, the
-- persistent meta state itself, already updated with this very run's own
-- outcome by the time Meta.recordRun evaluates any of these.
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
  -- Needs meta.runHistory (see streaks.lua), already carrying this very run
  -- as its newest entry - a win right after a loss, not just any win.
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

-- Loads meta state from `path`, or a fresh state if the file does not exist
-- yet (a player's first run). A file that exists but fails to parse or fails
-- its checksum is corruption, not a first run - that gets a warning on
-- stderr rather than silently discarding banked renown and achievements, but
-- still hands back a fresh state so the caller always has something to play
-- with. Fields missing on an older-version save default in via MetaSave's
-- migration chain; fields missing despite matching CURRENT_VERSION (a
-- hand-edited or partially-written file that still happens to parse and
-- checksum) default in here as a second line of defense.
function Meta.load(path)
  local data, err = MetaSave.load(path)
  if not data then
    if err ~= "missing" then
      io.stderr:write("warning: meta file " .. path .. " is " .. err .. "; starting fresh\n")
    end
    return Meta.new()
  end
  -- graves, leaderboard and runHistory are not re-defaulted here: MetaSave's
  -- migration chain above already guarantees them on anything that reaches
  -- this point. The base fields below predate versioning itself (there is no
  -- earlier step that could have filled them), so they keep their own
  -- fallback against a hand-edited or partially-written file that still
  -- parses and checksums.
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

-- Renown a single completed run banks, from its own tally alone: depth
-- reached, bosses felled, bounties resolved, vaults cracked open, set
-- pieces gathered, chests cracked open, and - far above any of those -
-- escaping with the Amulet. Any ascension.lua mutator active for the run
-- (stats.mutators, see Game:metaStats) then tops that base score up by its
-- own renown bonus percentage, rewarding the extra risk taken on.
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

-- Folds a finished run's stats into the persistent meta state: banks its
-- renown, advances the run/win/best-depth tallies, and unlocks any
-- achievement whose condition the run's tally satisfies for the first time.
-- Returns the newly unlocked achievement names, in catalog order, so a
-- caller (warren.lua) can announce them; an achievement already owned from an
-- earlier run is silently skipped rather than re-announced.
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

-- Spends renown to permanently unlock perk `key`. Fails without spending
-- anything given an unknown key, a perk already owned, or too little banked
-- renown; returns (false, reason) in each case.
function Meta.purchase(meta, key)
  local def = Meta.byKey[key]
  if not def then return false, "no such perk" end
  if meta.perks[key] then return false, "already owned" end
  if meta.renown < def.cost then return false, "not enough renown" end
  meta.renown = meta.renown - def.cost
  meta.perks[key] = true
  return true, "unlocked " .. def.name
end

-- Applies every perk `meta` already owns to a freshly created player, in
-- catalog order. Meant to run once in Game.new, before any class delta.
function Meta.applyAll(meta, player)
  for _, def in ipairs(Meta.PERKS) do
    if meta.perks[def.key] then def.apply(player) end
  end
end

return Meta
