local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Status = require("status")
local Monsters = require("monsters")
local Game = require("game")
local Shrines = require("shrines")
local Skills = require("skills")
local Companions = require("companions")
local Quests = require("quests")
local Factions = require("factions")
local Encumbrance = require("encumbrance")
local Nodes = require("nodes")
local Corpses = require("corpses")
local Durability = require("durability")

local ok, eq, contains, arena, stagedGame, padWith = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame, helpers.padWith

local tests = helpers.suite()

function tests.autopilotPraysAtAnUnspentShrineWhenAffordable()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.gold = 50
  game.level.shrines = { { x = 5, y = 5, kind = Shrines.WAR, uses = 0 } }
  game:choosePlayerAction()
  eq(game.level.shrines[1].uses, 1, "the autopilot prays at an unspent shrine it stands on")
  ok(game.player.gold < 50, "the autopilot's prayer spends the shrine's price")
end

function tests.autopilotSkipsAnAlreadyUsedShrine()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.gold = 50
  game.level.shrines = { { x = 5, y = 5, kind = Shrines.WAR, uses = 1 } }
  game:choosePlayerAction()
  eq(game.level.shrines[1].uses, 1, "the autopilot never re-prays at a shrine it has already used")
end

function tests.deterministicPlaythrough()
  local a = Game.new(1337)
  local b = Game.new(1337)
  for _ = 1, 120 do
    if a.player:isAlive() then a:autoStep() end
    if b.player:isAlive() then b:autoStep() end
  end
  eq(a:render(), b:render(), "same seed yields the same playthrough")
  eq(a.player.hp, b.player.hp, "same seed yields the same player hp")
  eq(a.depth, b.depth, "same seed yields the same depth")
  local c = Game.new(4242)
  for _ = 1, 120 do if c.player:isAlive() then c:autoStep() end end
  ok(a:render() ~= c:render(), "a different seed diverges")
end

function tests.autoplayDescends()
  local function playout(seed)
    local game = Game.new(seed)
    for _ = 1, 600 do
      if not game.player:isAlive() then break end
      game:autoStep()
    end
    return game
  end
  local run = playout(2025)
  ok(run.depth >= 3, "the autopilot descends several levels")
  local again = playout(2025)
  eq(again.depth, run.depth, "the autopilot reaches the same depth on the same seed")
  eq(again.turn, run.turn, "the autopilot takes the same number of turns")
end

function tests.wonGameHaltsTheAutopilot()
  local game = Game.new(7)
  game.won = true
  local turnBefore = game.turn
  game:autoStep()
  eq(game.turn, turnBefore, "autoStep is a no-op once the game is already won")
end

function tests.autopilotFetchesTheAmuletAndWins()
  local function playout(seed)
    local game = Game.new(seed, { maxDepth = 3 })
    for _ = 1, 900 do
      if not game.player:isAlive() or game.won then break end
      game:autoStep()
    end
    return game
  end
  local run = playout(67)
  ok(run.player:isAlive(), "the autopilot survives the round trip on this seed")
  eq(run.won, true, "the autopilot retrieves the amulet and escapes")
  eq(run.depth, 1, "winning leaves the player back at depth 1")
  ok(run:hasAmulet(), "the amulet is still in the winning player's inventory")
  local again = playout(67)
  eq(again.turn, run.turn, "the winning playthrough takes the same number of turns on the same seed")
end

function tests.autopilotLearnsSkillsAutomaticallyAsPointsAllow()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skillPoints = 1
  game:choosePlayerAction()
  ok(Skills.has(game.player, "cleave"),
    "the autopilot spends a banked point on the first level-eligible skill in class order")
  eq(game.player.skillPoints, 0, "learning the skill spends the banked point")
end

function tests.autopilotHarvestsAnOreVeinWhenIdleAndStandingOnIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y = 5, 5
  game.level.nodes = { ore }
  local before = game.player.essence
  game:choosePlayerAction()
  eq(ore.charges, Nodes.MAX_CHARGES - 1, "the autopilot harvests an unspent vein it stands on")
  ok(game.player.essence > before, "the autopilot's harvest actually pays out essence")
end

function tests.autopilotSkipsAFallowNode()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y, ore.charges = 5, 5, 0
  game.level.nodes = { ore }
  game:choosePlayerAction()
  eq(ore.charges, 0, "the autopilot never touches a fallow node")
end

function tests.autopilotButchersAFreshCorpseWhenIdleAndStandingOnIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  local before = #game.player.inventory
  game:choosePlayerAction()
  eq(#game.level.corpses, 0, "the autopilot butchers a fresh corpse it stands on")
  eq(#game.player.inventory, before + 1, "the autopilot's butchering actually yields food")
end

function tests.autopilotLeavesARottenCorpseAloneRatherThanRiskingPoison()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  game.level.corpses[1].decay = Corpses.ROT_TURNS
  game:choosePlayerAction()
  eq(#game.level.corpses, 1, "the autopilot never touches a rotten corpse")
  ok(not Status.has(game.player, Status.POISON), "the autopilot never risks poisoning itself on rotten meat")
end

function tests.autopilotAcceptsAnUnclaimedBountyForFreeWithoutSkippingItsTurn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.questBoards = { { x = 5, y = 5, claimed = false, quest = Quests.generate(Rng.new(2), 4, 10) } }
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 5, 1)
  game.level.entities = { orc }
  local hpBefore = orc.hp
  game:choosePlayerAction()
  ok(game.player.quest ~= nil, "the autopilot binds itself to a bounty it stands on")
  eq(game.level.questBoards[1].claimed, true, "the board is claimed once the autopilot steps onto it")
  ok(orc.hp < hpBefore, "accepting the bounty costs no action, so the same turn still lands an attack")
end

function tests.autopilotSkipsAnAlreadyClaimedBoard()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.questBoards = { { x = 5, y = 5, claimed = true, quest = Quests.generate(Rng.new(2), 4, 10) } }
  game:choosePlayerAction()
  eq(game.player.quest, nil, "the autopilot never binds to an already claimed board")
end

function tests.autopilotDoesNotStackASecondBountyWhileOneIsActive()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local held = Quests.generate(Rng.new(1), 4, 10)
  game.player.quest = held
  game.level.questBoards = { { x = 5, y = 5, claimed = false, quest = Quests.generate(Rng.new(2), 4, 10) } }
  game:choosePlayerAction()
  eq(game.player.quest, held, "the autopilot keeps its held bounty rather than swapping to a new one")
  eq(game.level.questBoards[1].claimed, false, "a board it cannot bind to stays unclaimed for later")
end

function tests.autopilotDropsCheapestJunkWhenOverloadedAndSafe()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  game.level.entities = {}
  game.player.inventory = {}
  padWith(game.player, 3)
  local amulet, key = Items.amulet(), Items.key()
  game.player.inventory[#game.player.inventory + 1] = amulet
  game.player.inventory[#game.player.inventory + 1] = key
  local countBefore = #game.player.inventory
  eq(game:encumbranceTier(), Encumbrance.OVERLOADED, "the staged inventory is overloaded before the autopilot acts")
  game:choosePlayerAction()
  eq(#game.player.inventory, countBefore - 1, "the autopilot sheds exactly one item while overloaded and safe")
  ok(contains(game.log:last(), "drop"), "the shed item is logged as a drop")
  ok(game:findInInventory(function(item) return item == amulet end) ~= nil, "the amulet is never sacrificed to encumbrance")
  ok(game:findInInventory(function(item) return item == key end) ~= nil, "a key is never sacrificed to encumbrance")
end

function tests.autopilotRepairsBrokenGearAutomaticallyWhenAffordable()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  game.player.weapon.durability = 0
  game.player.gold = 1000
  game.level.entities = {}
  game:choosePlayerAction()
  eq(game.player.weapon.durability, Durability.MAX,
    "the autopilot repairs a broken weapon on sight once it can afford to")
end

function tests.autopilotOpensAnUnlockedChestOnSightButSkipsALockedOneWithNoKeyOrPick()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chest = { x = 3, y = 6, locked = false, trapped = false, opened = false, loot = { Items.gold(5) } }
  game.level.chests = { chest }
  game:choosePlayerAction()
  eq(chest.opened, true, "the autopilot opens a free chest the instant it stands on one")

  local lockedGame = stagedGame(1, arena(21, 11), 3, 6)
  local locked = { x = 3, y = 6, locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
  lockedGame.level.chests = { locked }
  local beforeX, beforeY = lockedGame.player.x, lockedGame.player.y
  lockedGame:choosePlayerAction()
  eq(locked.opened, false, "the autopilot never gambles a lock it has neither a key nor a lockpick for")
  ok(lockedGame.player.x ~= beforeX or lockedGame.player.y ~= beforeY,
    "the autopilot still makes progress toward the stairs instead of parking on an unopenable chest")
end

function tests.autopilotHiresACarriedContractWhenNoHirelingIsYetUnderContract()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.entities = {}
  game.player.inventory = { Items.contract("skirmisher") }
  game:choosePlayerAction()
  eq(#game.player.inventory, 0, "the autopilot uses a carried contract on sight when no hireling is yet under contract")
  local hired = false
  for _, e in ipairs(game.level.entities) do
    if e.kind == "hireling" then hired = true end
  end
  ok(hired, "the autopilot's contract use actually hires the mercenary")
end

function tests.choosePlayerActionNeverAttacksItsOwnBondedCompanionEvenWithNothingElseToDo()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local hpBefore = hound.hp
  game:choosePlayerAction()
  eq(hound.hp, hpBefore, "the autopilot never bumps its own companion into a melee attack")
end

function tests.autopilotNetsABatteredAdjacentMonsterInsteadOfFinishingItInMeleeWhenCarryingANet()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 5, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.net()
  game.rng = Rng.new(2)
  game:choosePlayerAction()
  eq(#game.level.captives, 1, "the autopilot nets the battered adjacent monster instead of finishing it off")
  eq(#game.level.entities, 0, "the netted monster is removed from the level's entities")
end

function tests.autopilotSellsAHeldCaptiveOnSight()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  game.level.captives = { { x = 5, y = 5, species = "rat", faction = Factions.VERMIN, name = "rat", value = 5 } }
  local goldBefore = game.player.gold
  game:choosePlayerAction()
  eq(#game.level.captives, 0, "the autopilot cashes in a held captive on sight")
  eq(game.player.gold, goldBefore + 5, "the autopilot sells rather than ransoms or interrogates on its own")
end

function tests.choosePlayerActionEntersAWellHealedRiftUnderfootButSkipsItWhenBadlyHurt()
  local hurt = stagedGame(1, arena(21, 11), 5, 5)
  hurt.level.rifts = { { x = 5, y = 5 } }
  hurt.player.inventory[#hurt.player.inventory + 1] = Items.riftstone()
  hurt.player.hp = math.floor(hurt.player.maxHp * 0.5)
  hurt:choosePlayerAction()
  eq(hurt.rift or false, false, "the autopilot never spends a shard while badly hurt")

  local healthy = stagedGame(1, arena(21, 11), 5, 5)
  healthy.level.rifts = { { x = 5, y = 5 } }
  healthy.player.inventory[#healthy.player.inventory + 1] = Items.riftstone()
  healthy:choosePlayerAction()
  eq(healthy.rift, true, "the autopilot crosses a rift underfoot on sight while at good health")
end

function tests.choosePlayerActionStepsThroughAndThenExitsARiftUnderAutopilot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.rifts = { { x = 5, y = 5 } }
  game.player.inventory[#game.player.inventory + 1] = Items.riftstone()
  game:choosePlayerAction()
  ok(game.rift, "the autopilot has crossed into the pocket floor")
  game.player.x, game.player.y = game.level.downX, game.level.downY
  game:choosePlayerAction()
  eq(game.rift, false, "standing at the pocket floor's own exit, the autopilot immediately steps back out")
end

return tests
