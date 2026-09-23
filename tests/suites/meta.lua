local helpers = require("helpers")
local Monsters = require("monsters")
local Serialize = require("serialize")
local Game = require("game")
local Meta = require("meta")
local Compendium = require("compendium")
local Graves = require("graves")
local Leaderboard = require("leaderboard")
local Streaks = require("streaks")

local eq, arena, stagedGame = helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.metaFreshStateHasNoRenownRunsOrAchievements()
  local meta = Meta.new()
  eq(meta.renown, 0, "a fresh meta state banks no renown")
  eq(meta.totalRuns, 0, "a fresh meta state has recorded no runs")
  eq(meta.wins, 0, "a fresh meta state has recorded no wins")
  eq(meta.bestDepth, 0, "a fresh meta state has no best depth yet")
  eq(next(meta.achievements), nil, "a fresh meta state has unlocked nothing")
  eq(next(meta.perks), nil, "a fresh meta state owns no perks")
end

function tests.metaRenownForScalesWithDepthBossesAndQuestsAndAddsAWinBonus()
  local base = Meta.renownFor({ deepestDepth = 3, bossKills = 0, questsCompleted = 0, won = false })
  eq(base, 12, "renown scales with deepest depth alone")
  local withBosses = Meta.renownFor({ deepestDepth = 3, bossKills = 2, questsCompleted = 0, won = false })
  eq(withBosses, base + 30, "each felled boss adds a fixed renown bonus")
  local withQuests = Meta.renownFor({ deepestDepth = 3, bossKills = 0, questsCompleted = 4, won = false })
  eq(withQuests, base + 32, "each resolved bounty adds a fixed renown bonus")
  local won = Meta.renownFor({ deepestDepth = 3, bossKills = 0, questsCompleted = 0, won = true })
  eq(won, base + 100, "escaping with the amulet adds a large flat bonus")
end

function tests.metaRecordRunBanksRenownAndAdvancesTallies()
  local meta = Meta.new()
  Meta.recordRun(meta, { deepestDepth = 4, kills = 2, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = false })
  eq(meta.totalRuns, 1, "recordRun advances the run tally")
  eq(meta.wins, 0, "an unwon run does not advance the win tally")
  eq(meta.bestDepth, 4, "recordRun raises the best depth to this run's own")
  eq(meta.renown, Meta.renownFor({ deepestDepth = 4, bossKills = 0, questsCompleted = 0, won = false }),
    "recordRun banks exactly the renown this run's tally is worth")
  Meta.recordRun(meta, { deepestDepth = 2, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = true })
  eq(meta.totalRuns, 2, "a second run advances the run tally again")
  eq(meta.wins, 1, "a won run advances the win tally")
  eq(meta.bestDepth, 4, "a shallower later run does not lower the best depth")
end

function tests.metaRecordRunUnlocksMatchingAchievementsOnlyOnce()
  local meta = Meta.new()
  local stats = { deepestDepth = 5, kills = 1, bossKills = 1, questsCompleted = 3, artifactsFound = 1, won = true }
  local unlocked = Meta.recordRun(meta, stats)
  table.sort(unlocked)
  local expected = { "Amulet Bearer", "Artificer", "Boss Slayer", "Bounty Hunter", "Deep Delver", "First Blood" }
  table.sort(expected)
  eq(table.concat(unlocked, ","), table.concat(expected, ","),
    "a run meeting every threshold unlocks every achievement at once")
  for _, key in ipairs({ "first_blood", "boss_slayer", "deep_delver", "bounty_hunter", "artificer", "amulet_bearer" }) do
    eq(meta.achievements[key], true, key .. " is marked unlocked")
  end
  local again = Meta.recordRun(meta, stats)
  eq(#again, 0, "an already-unlocked achievement is not re-announced on a later run")
end

function tests.metaPurchaseSpendsRenownAndMarksThePerkOwned()
  local meta = Meta.new()
  meta.renown = 30
  local success, message = Meta.purchase(meta, "vigor")
  eq(success, true, "purchase succeeds with enough banked renown")
  eq(message, "unlocked Vigor", "purchase reports the perk it unlocked")
  eq(meta.renown, 0, "purchase spends exactly the perk's cost")
  eq(Meta.isOwned(meta, "vigor"), true, "the purchased perk is marked owned")
end

function tests.metaPurchaseFailsWithoutEnoughRenown()
  local meta = Meta.new()
  meta.renown = 5
  local success, message = Meta.purchase(meta, "vigor")
  eq(success, false, "purchase fails without enough banked renown")
  eq(message, "not enough renown", "purchase explains why it failed")
  eq(meta.renown, 5, "a failed purchase spends nothing")
end

function tests.metaPurchaseFailsForAnAlreadyOwnedPerk()
  local meta = Meta.new()
  meta.renown = 100
  Meta.purchase(meta, "vigor")
  local renownAfterFirst = meta.renown
  local success, message = Meta.purchase(meta, "vigor")
  eq(success, false, "purchase refuses to sell the same perk twice")
  eq(message, "already owned", "purchase explains why it failed")
  eq(meta.renown, renownAfterFirst, "a refused repurchase spends nothing further")
end

function tests.metaPurchaseFailsForAnUnknownPerk()
  local meta = Meta.new()
  meta.renown = 100
  local success, message = Meta.purchase(meta, "not_a_real_perk")
  eq(success, false, "purchase fails for a key outside the catalog")
  eq(message, "no such perk", "purchase explains why it failed")
  eq(meta.renown, 100, "a failed purchase spends nothing")
end

function tests.metaApplyAllAppliesEveryOwnedPerkToAFreshPlayer()
  local meta = Meta.new()
  meta.renown = 200
  Meta.purchase(meta, "vigor")
  Meta.purchase(meta, "purse")
  local game = Game.new(1, { meta = meta })
  eq(game.player.maxHp, 30 + 5, "the owned vigor perk raises max hp before class deltas")
  eq(game.player.hp, 30 + 5, "the owned vigor perk raises current hp to match")
  eq(game.player.gold, 20 + 25, "the owned deep pockets perk raises starting gold")
  local plain = Game.new(1)
  eq(plain.player.maxHp, 30, "a game started without a meta table gets no perk bonus")
end

function tests.metaAppliedPerksLandBeneathAClassDelta()
  local meta = Meta.new()
  meta.renown = 200
  Meta.purchase(meta, "vigor")
  local game = Game.new(1, { meta = meta, class = "fighter" })
  eq(game.player.maxHp, 30 + 5 + 8, "a fighter's class bonus stacks on top of an owned perk's bonus")
end

function tests.metaLoadReturnsFreshStateForAMissingFile()
  local meta = Meta.load("/tmp/warren_meta_does_not_exist_12345.sav")
  eq(meta.renown, 0, "loading a missing meta file yields a fresh state")
  eq(meta.totalRuns, 0, "a freshly defaulted meta state has recorded no runs")
end

function tests.metaSaveLoadRoundTrip()
  local meta = Meta.new()
  meta.renown = 42
  Meta.recordRun(meta, { deepestDepth = 6, kills = 5, bossKills = 1, questsCompleted = 2, artifactsFound = 1, won = false })
  Meta.purchase(meta, "focus")
  local path = os.tmpname()
  Meta.save(meta, path)
  local restored = Meta.load(path)
  os.remove(path)
  eq(restored.renown, meta.renown, "renown survives a save/load round trip")
  eq(restored.totalRuns, meta.totalRuns, "run tally survives a save/load round trip")
  eq(restored.bestDepth, meta.bestDepth, "best depth survives a save/load round trip")
  eq(restored.achievements.boss_slayer, true, "achievements survive a save/load round trip")
  eq(restored.perks.focus, true, "owned perks survive a save/load round trip")
end

function tests.gameMetaStatsFieldsSurviveSerialization()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game:playerAttack(rat)
  game.deepestDepth = 3
  local restored = Game.fromData(game:toData())
  eq(restored.stats.kills, game.stats.kills, "the kill tally survives a save/load round trip")
  eq(restored.deepestDepth, game.deepestDepth, "the deepest depth survives a save/load round trip")
  local snapshot = restored:metaStats()
  eq(snapshot.kills, 1, "metaStats reads the restored kill tally")
  eq(snapshot.deepestDepth, 3, "metaStats reads the restored deepest depth")
end

function tests.metaRenownForScalesWithVaultsOpened()
  local base = Meta.renownFor({ deepestDepth = 3, bossKills = 0, questsCompleted = 0, vaultsOpened = 0, won = false })
  local withVault = Meta.renownFor({ deepestDepth = 3, bossKills = 0, questsCompleted = 0, vaultsOpened = 2, won = false })
  eq(withVault, base + 20, "each opened vault adds a fixed renown bonus")
end

function tests.metaRecordRunUnlocksVaultBreakerOnceAVaultOpens()
  local meta = Meta.new()
  local stats = {
    deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0,
    artifactsFound = 0, vaultsOpened = 1, won = false,
  }
  local unlocked = Meta.recordRun(meta, stats)
  eq(unlocked[1], "Vault Breaker", "opening a vault for the first time unlocks Vault Breaker")
  eq(meta.achievements.vault_breaker, true, "vault_breaker is marked unlocked")
  local again = Meta.recordRun(meta, stats)
  eq(#again, 0, "an already-unlocked Vault Breaker is not re-announced on a later run")
end

function tests.gameReusesThePassedMetaSCompendiumByReference()
  local meta = Meta.new()
  local game = Game.new(1, { meta = meta })
  local orc = Monsters.create(Monsters.byKey.orc, 1, game.player.x + 1, game.player.y, 1)
  game.level.entities = { orc }
  game:awardKill(orc)
  eq(Compendium.killCount(meta.compendium, "orc"), 1,
    "a kill recorded mid-run is already sitting in the exact meta table warren.lua will save back out")
end

function tests.metaRenownForScalesWithSetPiecesFound()
  local base = Meta.renownFor({ deepestDepth = 3, bossKills = 0, questsCompleted = 0, setPiecesFound = 0, won = false })
  local withPieces = Meta.renownFor({ deepestDepth = 3, bossKills = 0, questsCompleted = 0, setPiecesFound = 2, won = false })
  eq(withPieces, base + 6, "each set piece found adds a fixed renown bonus")
end

function tests.metaRecordRunUnlocksSetCollectorOnceThreePiecesFound()
  local meta = Meta.new()
  local stats = {
    deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0,
    artifactsFound = 0, vaultsOpened = 0, setPiecesFound = 3, won = false,
  }
  local unlocked = Meta.recordRun(meta, stats)
  eq(unlocked[1], "Set Collector", "finding three set pieces in a run unlocks Set Collector")
  eq(meta.achievements.set_collector, true, "set_collector is marked unlocked")
  local again = Meta.recordRun(meta, stats)
  eq(#again, 0, "an already-unlocked Set Collector is not re-announced on a later run")
end

function tests.metaGravesFieldDefaultsToEmptyAndSurvivesASaveLoadRoundTrip()
  local fresh = Meta.load("/tmp/warren_meta_does_not_exist_98765.sav")
  eq(#fresh.graves, 0, "a freshly defaulted meta state has no recorded graves")
  local meta = Meta.new()
  Graves.record(meta, { className = "rogue", depth = 4, gold = 30, essence = 2, turn = 15 })
  local path = os.tmpname()
  Meta.save(meta, path)
  local restored = Meta.load(path)
  os.remove(path)
  eq(#restored.graves, 1, "a recorded grave survives a save/load round trip")
  eq(restored.graves[1].className, "rogue", "a restored grave keeps its own fallen class")
  eq(restored.graves[1].depth, 4, "a restored grave keeps its own depth")
end

function tests.metaRenownForAddsTheAscensionBonusOnTopOfTheBaseScore()
  local stats = { deepestDepth = 5, bossKills = 0, questsCompleted = 0, won = false }
  local base = Meta.renownFor(stats)
  stats.mutators = { "famine" }
  eq(Meta.renownFor(stats), base + (base * 10) // 100, "famine's 10% renown bonus is added on top of the base score")
  stats.mutators = { "famine", "nightblind" }
  eq(Meta.renownFor(stats), base + (base * 20) // 100, "two mutators' renown bonuses sum before being applied")
end

function tests.metaLeaderboardFieldDefaultsToEmptyAndSurvivesASaveLoadRoundTrip()
  local fresh = Meta.load("/tmp/warren_meta_does_not_exist_55511.sav")
  eq(#fresh.leaderboard, 0, "a freshly defaulted meta state has an empty leaderboard")
  local meta = Meta.new()
  Leaderboard.record(meta.leaderboard, { score = 250, className = "mage", depth = 4, turn = 88, won = false, seed = 7 })
  local path = os.tmpname()
  Meta.save(meta, path)
  local restored = Meta.load(path)
  os.remove(path)
  eq(#restored.leaderboard, 1, "a recorded leaderboard entry survives a save/load round trip")
  eq(restored.leaderboard[1].score, 250, "a restored entry keeps its own score")
  eq(restored.leaderboard[1].className, "mage", "a restored entry keeps its own class")
end

function tests.metaRecordRunFeedsStreaksAndRunHistorySurvivesASaveLoadRoundTrip()
  local fresh = Meta.load("/tmp/warren_meta_does_not_exist_71234.sav")
  eq(#fresh.runHistory, 0, "a freshly defaulted meta state has an empty run history")
  local meta = Meta.new()
  Meta.recordRun(meta, { deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = true })
  Meta.recordRun(meta, { deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = false })
  eq(#meta.runHistory, 2, "each recorded run appends exactly one entry to the history")
  local currentLength, currentOutcome = Streaks.current(meta.runHistory)
  eq(currentLength, 1, "the most recent recorded run is a fresh streak of one")
  eq(currentOutcome, false, "the most recent recorded run was a loss")
  local path = os.tmpname()
  Meta.save(meta, path)
  local restored = Meta.load(path)
  os.remove(path)
  eq(#restored.runHistory, 2, "run history survives a save/load round trip")
  eq(restored.runHistory[1], true, "the oldest entry keeps its own outcome")
  eq(restored.runHistory[2], false, "the newest entry keeps its own outcome")
end

function tests.metaRecordRunUnlocksComebackOnlyAfterALossThenAWin()
  local meta = Meta.new()
  Meta.recordRun(meta, { deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = false })
  eq(meta.achievements.comeback, nil, "a lone loss cannot unlock a comeback")
  Meta.recordRun(meta, { deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = true })
  eq(meta.achievements.comeback, true, "winning right after a loss unlocks the comeback")
end

function tests.metaRecordRunDoesNotUnlockComebackOnAFirstEverWinOrAWinAfterAWin()
  local isolated = Meta.new()
  Meta.recordRun(isolated, { deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = true })
  eq(isolated.achievements.comeback, nil, "a first-ever run that wins has no prior loss to come back from")

  local streak = Meta.new()
  Meta.recordRun(streak, { deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = true })
  Meta.recordRun(streak, { deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = true })
  eq(streak.achievements.comeback, nil, "a win right after another win is not a comeback")
end

function tests.metaLoadUpgradesALegacyPreEnvelopeFileWithoutLosingItsRenown()
  local path = os.tmpname()
  Serialize.saveFile(path, {
    renown = 77, totalRuns = 3, wins = 1, bestDepth = 4,
    achievements = { boss_slayer = true }, perks = { vigor = true },
  })
  local meta = Meta.load(path)
  os.remove(path)
  eq(meta.renown, 77, "renown from a pre-envelope legacy file is not discarded")
  eq(meta.achievements.boss_slayer, true, "achievements from a legacy file survive the upgrade")
  eq(#meta.graves, 0, "graves defaults in for a file predating the graves feature")
  eq(#meta.leaderboard, 0, "leaderboard defaults in for a file predating the leaderboard feature")
  eq(#meta.runHistory, 0, "runHistory defaults in for a file predating streaks")
end

function tests.metaLoadStartsFreshWithoutCrashingOnACorruptedFile()
  local path = os.tmpname()
  local meta = Meta.new()
  meta.renown = 500
  Meta.save(meta, path)
  local file = assert(io.open(path, "r"))
  local text = file:read("a")
  file:close()
  local tampered = text:gsub("500", "999", 1)
  local out = assert(io.open(path, "w"))
  out:write(tampered)
  out:close()
  local restored = Meta.load(path)
  os.remove(path)
  eq(restored.renown, 0, "a checksum-broken meta file starts fresh rather than trusting tampered renown")
end

return tests
