local helpers = require("helpers")
local Rng = require("rng")
local Level = require("level")
local Builder = require("builder")
local Game = require("game")
local Crafting = require("crafting")
local Quests = require("quests")
local Factions = require("factions")
local Items = require("items")
local Render = require("render")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.questGenerateProducesACullBounty()
  local bounty = Quests.generate(Rng.new(2), 4, 10)
  eq(bounty.kind, Quests.CULL, "this seed at depth 4 rolls a cull bounty")
  eq(bounty.species, "necromancer", "the cull bounty's target species is fixed by the seed")
  eq(bounty.need, 4, "the cull bounty's tally is fixed by the seed")
  eq(bounty.have, 0, "a freshly generated cull bounty starts at zero progress")
  eq(bounty.rewardGold, 47, "reward gold scales with the generating depth")
  eq(bounty.rewardXp, 26, "reward xp scales with the generating depth")
  eq(Quests.describe(bounty), "cull 4 necromancer (0/4)", "describe renders the cull bounty's live progress")
end

function tests.questGenerateProducesAHoardBounty()
  local bounty = Quests.generate(Rng.new(1), 4, 10)
  eq(bounty.kind, Quests.HOARD, "this seed at depth 4 rolls a hoard bounty")
  eq(bounty.need, 120, "the hoard bounty's absolute gold target scales with depth")
  eq(Quests.describe(bounty), "amass 120 gold", "describe renders the hoard bounty's target")
end

function tests.questGenerateProducesADepthBountyClampedToMaxDepth()
  local shallow = Quests.generate(Rng.new(5), 4, 10)
  eq(shallow.kind, Quests.DEPTH, "this seed at depth 4 rolls a depth bounty")
  eq(shallow.need, 6, "an unclamped depth bounty targets a few floors further down")
  local nearBottom = Quests.generate(Rng.new(5), 9, 10)
  eq(nearBottom.kind, Quests.DEPTH, "the same seed at depth 9 also rolls a depth bounty")
  eq(nearBottom.need, 10, "a depth bounty that would exceed the dungeon's floor is clamped to it")
end

function tests.questAcceptBindsThePlayerAndClaimsTheBoard()
  local player = { quest = nil }
  local board = { x = 5, y = 5, claimed = false, quest = Quests.generate(Rng.new(2), 4, 10) }
  local success, line = Quests.accept(player, board)
  eq(success, true, "accepting an unclaimed bounty while unbound succeeds")
  eq(player.quest, board.quest, "the player is bound to the board's exact bounty")
  eq(board.claimed, true, "the board is claimed the instant its bounty is taken")
  ok(line:find("necromancer") ~= nil, "the acceptance line names the bounty struck")
end

function tests.questAcceptFailsWhenAlreadyHoldingOne()
  local existing = Quests.generate(Rng.new(1), 4, 10)
  local player = { quest = existing }
  local board = { x = 5, y = 5, claimed = false, quest = Quests.generate(Rng.new(2), 4, 10) }
  local success = Quests.accept(player, board)
  eq(success, false, "a player already bound to a bounty cannot bind to a second")
  eq(player.quest, existing, "the player's original bounty is untouched")
  eq(board.claimed, false, "the untaken board stays unclaimed")
end

function tests.questAcceptFailsOnAnAlreadyClaimedBoard()
  local player = { quest = nil }
  local board = { x = 5, y = 5, claimed = true, quest = Quests.generate(Rng.new(2), 4, 10) }
  local success = Quests.accept(player, board)
  eq(success, false, "a board already claimed grants no second bounty")
  eq(player.quest, nil, "the player stays unbound")
end

function tests.questRegisterKillIncrementsOnlyMatchingSpeciesWhileActive()
  local player = { quest = { kind = Quests.CULL, species = "rat", need = 3, have = 0 } }
  Quests.registerKill(player, "goblin")
  eq(player.quest.have, 0, "a kill of an unrelated species does not advance the tally")
  Quests.registerKill(player, "rat")
  Quests.registerKill(player, "rat")
  eq(player.quest.have, 2, "kills of the target species advance the tally")
  Quests.registerKill(player, "rat")
  Quests.registerKill(player, "rat")
  eq(player.quest.have, 3, "the tally never climbs past the bounty's required count")
end

function tests.questResolvedDetectsEachKindsCompletion()
  local culler = { quest = { kind = Quests.CULL, need = 3, have = 2 }, gold = 0 }
  eq(Quests.resolved(culler, 1), false, "a cull short of its tally is not resolved")
  culler.quest.have = 3
  eq(Quests.resolved(culler, 1), true, "a cull at its tally is resolved")

  local hoarder = { quest = { kind = Quests.HOARD, need = 100 }, gold = 40 }
  eq(Quests.resolved(hoarder, 1), false, "a hoard short of its gold target is not resolved")
  hoarder.gold = 100
  eq(Quests.resolved(hoarder, 1), true, "a hoard at its gold target is resolved")

  local pactbound = { quest = { kind = Quests.DEPTH, need = 5 }, gold = 0 }
  eq(Quests.resolved(pactbound, 4), false, "a depth pact short of its floor is not resolved")
  eq(Quests.resolved(pactbound, 5), true, "a depth pact met at its floor is resolved")

  eq(Quests.resolved({ quest = nil, gold = 0 }, 5), false, "a player with no bounty is never resolved")
end

function tests.gameResolveQuestPaysOutAndClearsAFulfilledBounty()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.quest = { kind = Quests.CULL, species = "rat", need = 1, have = 1, rewardGold = 30, rewardXp = 15 }
  local goldBefore, essenceBefore = game.player.gold, game.player.essence
  local resolved = game:resolveQuest()
  eq(resolved, true, "resolveQuest reports the payout it made")
  eq(game.player.gold, goldBefore + 30, "the bounty's gold reward is paid")
  eq(game.player.essence, essenceBefore + Crafting.essenceFor(15), "the bounty's xp reward also converts to essence")
  eq(game.player.quest, nil, "a resolved bounty frees the player to bind another")
end

function tests.gameResolveQuestIsANoOpOnAnUnmetBounty()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.quest = { kind = Quests.CULL, species = "rat", need = 3, have = 1, rewardGold = 30, rewardXp = 15 }
  local goldBefore = game.player.gold
  local resolved = game:resolveQuest()
  eq(resolved, false, "resolveQuest reports nothing was paid out")
  eq(game.player.gold, goldBefore, "no gold changes hands on an unmet bounty")
  ok(game.player.quest ~= nil, "the unmet bounty stays bound to the player")
end

function tests.gameTryAcceptQuestBindsAndLogsWhenStandingOnAnUnclaimedBoard()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local board = { x = 5, y = 5, claimed = false, quest = Quests.generate(Rng.new(2), 4, 10) }
  local success = game:tryAcceptQuest(board)
  eq(success, true, "tryAcceptQuest binds the player to the board it stands on")
  eq(game.player.quest.kind, Quests.CULL, "the bound bounty matches the board's own")
  eq(board.claimed, true, "the board is spent on acceptance")
end

function tests.questBoardRendersItsGlyphAndFlipsOnceClaimed()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local board = { x = 5, y = 6, claimed = false, quest = Quests.generate(Rng.new(2), 4, 10) }
  game.level.questBoards = { board }
  game:computeVisible()
  eq(helpers.glyphAt(game, 5, 6), Render.glyphs.board, "an unclaimed bounty board renders its glyph")
  board.claimed = true
  eq(helpers.glyphAt(game, 5, 6), Render.glyphs.claimedBoard, "a claimed bounty board renders a different glyph")
  ok(Render.glyphs.board ~= Items.glyphs[Items.TOME], "an open board never looks like a tome")
  ok(Render.glyphs.claimedBoard ~= Items.glyphs[Items.RING], "a claimed board never looks like a ring")
end

function tests.questFieldsSurviveSerialization()
  local level = arena(21, 11)
  level.questBoards = { { x = 4, y = 4, claimed = true, quest = Quests.generate(Rng.new(2), 4, 10) } }
  local restored = Level.fromData(level:toData())
  eq(#restored.questBoards, 1, "the quest board list survives a level round trip")
  eq(restored.questBoards[1].claimed, true, "a board's claimed flag survives a round trip")
  eq(restored.questBoards[1].quest.kind, Quests.CULL, "a board's bounty kind survives a round trip")
  eq(restored.questBoards[1].quest.need, 4, "a board's bounty tally survives a round trip")

  local game = Game.new(6)
  game.player.quest = { kind = Quests.HOARD, need = 200, rewardGold = 50, rewardXp = 20 }
  local path = os.tmpname()
  game:save(path)
  local restoredGame = Game.load(path)
  os.remove(path)
  eq(restoredGame.player.quest.kind, Quests.HOARD, "the player's own bound bounty survives a save/load round trip")
  eq(restoredGame.player.quest.need, 200, "the bound bounty's target survives a save/load round trip")
end

function tests.questBoardsStayOffTheEntranceFloor()
  for seed = 1, 5 do
    local level = Builder.build(1, Rng.new(seed), {})
    eq(#level.questBoards, 0, "no bounty board appears on the entrance floor")
  end
end

function tests.gameResolveQuestTracksQuestsCompletedForMetaStats()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.quest = { kind = Quests.CULL, species = "rat", need = 1, have = 0, rewardGold = 30, rewardXp = 15 }
  game:resolveQuest()
  eq(game.stats.questsCompleted, 0, "an unmet bounty does not count toward quests completed")
  game.player.quest = { kind = Quests.CULL, species = "rat", need = 1, have = 1, rewardGold = 30, rewardXp = 15 }
  game:resolveQuest()
  eq(game.stats.questsCompleted, 1, "resolving a bounty counts toward quests completed")
end

function tests.resolveQuestNudgesMerchantReputationUpward()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.quest = { kind = Quests.CULL, species = "rat", need = 1, have = 1, rewardGold = 30, rewardXp = 15 }
  game:resolveQuest()
  eq(Factions.reputationFor(game.player, Factions.MERCHANT), 3, "turning in a bounty pads the merchant guild's opinion of the player")
end

return tests
