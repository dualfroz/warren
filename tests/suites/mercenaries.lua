local helpers = require("helpers")
local Items = require("items")
local Status = require("status")
local Monsters = require("monsters")
local Level = require("level")
local Game = require("game")
local Stealth = require("stealth")
local Mercenaries = require("mercenaries")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.mercenaryHireTakesOnAKnownRosterEntryAdjacentToThePlayer()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  ok(sellsword ~= nil, "hiring a valid roster key succeeds next to the player")
  eq(sellsword.kind, "hireling", "a hired mercenary is tagged with the hireling kind")
  eq(math.max(math.abs(sellsword.x - 5), math.abs(sellsword.y - 5)), 1, "the hireling lands adjacent to the player")
  eq(sellsword.loyalty, Mercenaries.START_LOYALTY, "a freshly hired mercenary starts at full loyalty")
  eq(sellsword.wage, Mercenaries.byKey.sellsword.wage, "the hireling carries its roster wage")
end

function tests.mercenaryHireRejectsAnUnknownRosterKey()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  eq(Mercenaries.hire(game, "dragon"), nil, "an unknown roster key hires nobody")
  eq(#game.level.entities, 0, "no entity is added for an unknown roster key")
end

function tests.mercenaryHireReplacesAnEarlierHireling()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local first = Mercenaries.hire(game, "sellsword")
  local second = Mercenaries.hire(game, "medic")
  ok(not first:isAlive(), "hiring a new mercenary retires the earlier one")
  ok(second:isAlive(), "the freshly hired mercenary is alive")
  local alive = 0
  for _, e in ipairs(game.level.entities) do
    if e.kind == "hireling" and e:isAlive() then alive = alive + 1 end
  end
  eq(alive, 1, "only one hireling is ever alive at a time")
end

function tests.mercenaryAttacksAdjacentHostileMonsterAndCanKillIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  local rat = Monsters.create(Monsters.byKey.rat, 50, sellsword.x + 1, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local xpBefore = game.player.xp
  Mercenaries.act(game, sellsword)
  ok(rat.hp <= 0, "a sellsword's hit kills the weak rat standing next to it")
  ok(game.player.xp > xpBefore, "the player is credited xp for its hireling's kill")
end

function tests.mercenaryAdvancesOnAVisibleMonsterItCannotYetReach()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  local orc = Monsters.create(Monsters.byKey.orc, 50, sellsword.x + 5, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX = sellsword.x
  Mercenaries.act(game, sellsword)
  ok(sellsword.x > startX, "the hireling closes the distance to a monster it can see but not reach")
end

function tests.mercenaryIgnoresAMonsterBeyondItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local medic = Mercenaries.hire(game, "medic")
  local orc = Monsters.create(Monsters.byKey.orc, 50, 19, 9, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX, startY = medic.x, medic.y
  Mercenaries.act(game, medic)
  eq(medic.x, startX, "a monster far outside sight range does not pull the hireling off course (x)")
  eq(medic.y, startY, "a monster far outside sight range does not pull the hireling off course (y)")
end

function tests.mercenaryActBlindedHirelingOnlyDetectsAnAdjacentHostileNotOneWithinItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  local farOrc = Monsters.create(Monsters.byKey.orc, 50, sellsword.x + 5, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = farOrc
  Status.apply(sellsword, Status.BLIND, 6, 1)
  local startX = sellsword.x
  Mercenaries.act(game, sellsword)
  eq(sellsword.x, startX, "a blinded hireling loses a sighting well within its listed sight radius")

  local rat = Monsters.create(Monsters.byKey.rat, 51, sellsword.x + 1, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local ratHpBefore = rat.hp
  Mercenaries.act(game, sellsword)
  ok(rat.hp < ratHpBefore, "a blinded hireling still fights a hostile once it stands adjacent")
end

function tests.mercenaryActAttackingAnAdjacentMonsterEmitsNoiseThatCanStirADormantBystander()
  local stirred = false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local sellsword = Mercenaries.hire(game, "sellsword")
    local target = Monsters.create(Monsters.byKey.rat, 50, sellsword.x + 1, sellsword.y, 1)
    local bystander = Monsters.create(Monsters.byKey.orc, 51, sellsword.x + 4, sellsword.y, 1)
    bystander.awareness = Stealth.DORMANT
    game.level.entities[#game.level.entities + 1] = target
    game.level.entities[#game.level.entities + 1] = bystander
    Mercenaries.act(game, sellsword)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a hireling's own melee is exactly as loud as a companion's or the player's")
end

function tests.mercenaryFollowsThePlayerWhenNoMonsterIsVisible()
  local game = stagedGame(1, arena(21, 11), 10, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  sellsword.x, sellsword.y = 3, 5
  local startDist = math.abs(sellsword.x - game.player.x)
  Mercenaries.act(game, sellsword)
  ok(math.abs(sellsword.x - game.player.x) < startDist, "a hireling with no monster in sight closes in on the player")
end

function tests.mercenaryActConfusedHirelingSometimesStumblesInsteadOfFightingAnAdjacentHostile()
  local sawAttack, sawStumble = false, false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local sellsword = Mercenaries.hire(game, "sellsword")
    local rat = Monsters.create(Monsters.byKey.rat, 50, sellsword.x + 1, sellsword.y, 1)
    game.level.entities[#game.level.entities + 1] = rat
    Status.apply(sellsword, Status.CONFUSE, 5, 1)
    local hpBefore = rat.hp
    Mercenaries.act(game, sellsword)
    if rat.hp < hpBefore then
      sawAttack = true
    else
      sawStumble = true
    end
    if sawAttack and sawStumble then break end
  end
  ok(sawAttack, "a confused hireling's roll sometimes lets it fight an adjacent hostile as normal")
  ok(sawStumble, "a confused hireling's roll sometimes overrides even a point-blank attack")
end

function tests.fieldMedicMendsThePlayerWhenIdle()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.hp = game.player.maxHp - 5
  local medic = Mercenaries.hire(game, "medic")
  local before = game.player.hp
  Mercenaries.act(game, medic)
  eq(game.player.hp, before + Mercenaries.byKey.medic.heal, "a field medic mends its employer each idle turn")
end

function tests.mercenaryStopsChasingAndFollowingOnceSulking()
  local game = stagedGame(1, arena(21, 11), 10, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  sellsword.loyalty = Mercenaries.SULKING_THRESHOLD
  sellsword.x, sellsword.y = 3, 5
  local startX, startY = sellsword.x, sellsword.y
  Mercenaries.act(game, sellsword)
  eq(sellsword.x, startX, "a sulking hireling does not close in on the player it cannot reach (x)")
  eq(sellsword.y, startY, "a sulking hireling does not close in on the player it cannot reach (y)")
end

function tests.mercenaryStillFightsAnAdjacentHostileEvenWhileSulking()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  sellsword.loyalty = 0
  local rat = Monsters.create(Monsters.byKey.rat, 50, sellsword.x + 1, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  Mercenaries.act(game, sellsword)
  ok(rat.hp <= 0, "a sulking hireling still fights whatever already stands next to it")
end

function tests.mercenaryPayWagePaysWhenAffordableAndRestoresLoyalty()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  sellsword.loyalty = 50
  game.player.gold = 100
  local line = Mercenaries.payWage(game)
  eq(game.player.gold, 100 - sellsword.wage, "an affordable wage is deducted from the wallet")
  eq(sellsword.loyalty, 50 + Mercenaries.LOYALTY_GAIN_PAID, "paying the wage restores some loyalty")
  ok(contains(line, "pay"), "a paid wage is logged as a payment")
end

function tests.mercenaryPayWageShortsAndDropsLoyaltyWhenGoldIsShort()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  game.player.gold = 0
  local line = Mercenaries.payWage(game)
  eq(game.player.gold, 0, "an unaffordable wage never touches the wallet")
  eq(sellsword.loyalty, Mercenaries.START_LOYALTY - Mercenaries.LOYALTY_LOSS_UNPAID,
    "missing a wage knocks the hireling's loyalty down")
  ok(contains(line, "grumbles"), "a missed wage that survives is logged as a grumble")
end

function tests.mercenaryPayWageDesertsOnceLoyaltyBottomsOut()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  sellsword.loyalty = 20
  game.player.gold = 0
  local line = Mercenaries.payWage(game)
  ok(not sellsword:isAlive(), "a hireling whose loyalty bottoms out deserts")
  eq(#game.level.entities, 0, "a deserted hireling is swept from the level")
  ok(contains(line, "deserts"), "desertion is logged distinctly from a mere grumble")
end

function tests.mercenaryPayWageIsANoOpWithNoHirelingOnTheLevel()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  eq(Mercenaries.payWage(game), nil, "paying a wage with no hireling present does nothing and reports nothing")
end

function tests.mercenaryDismissReleasesTheHirelingWithNoPenalty()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Mercenaries.hire(game, "medic")
  local name = Mercenaries.dismiss(game)
  eq(name, "field medic", "dismissing returns the released hireling's name")
  eq(#game.level.entities, 0, "the dismissed hireling leaves the level")
end

function tests.mercenaryDismissFailsWithNoOneUnderContract()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  eq(Mercenaries.dismiss(game), nil, "dismissing with nobody hired reports nothing")
end

function tests.useItemOnAContractHiresTheNamedMercenaryAndConsumesIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Items.contract("skirmisher") }
  ok(game:useItem(1), "using a contract succeeds")
  eq(#game.player.inventory, 0, "the contract leaves the inventory once the hireling joins")
  eq(#game.level.entities, 1, "the hired mercenary is added to the level")
  eq(game.level.entities[1].species, "skirmisher", "the hired mercenary matches the contract's roster key")
end

function tests.useItemOnAContractWithAnUnknownRosterKeyFailsWithoutConsumingIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Items.contract("dragon") }
  eq(game:useItem(1), false, "using a contract for an unknown roster key fails")
  eq(#game.player.inventory, 1, "a failed hire never consumes the contract")
end

function tests.aFallenHirelingIsLoggedAndSweptWithoutAwardingXp()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  sellsword.hp = 1
  Status.apply(sellsword, Status.POISON, 1, 5)
  local xpBefore = game.player.xp
  game:takeMonsterTurn(sellsword)
  eq(#game.level.entities, 0, "a hireling that dies to its own status tick is swept from the level")
  eq(game.player.xp, xpBefore, "a fallen hireling grants the player no xp")
  ok(contains(game.log:last(), "falls"), "a fallen hireling's death is logged")
end

function tests.gameEndPlayerTurnPaysTheHirelingWageOnceTheIntervalElapses()
  local game = Game.new(5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  ok(sellsword ~= nil, "the starting room around a fresh game has a free cell to hire into")
  game.player.gold = 1000
  game.turn = Mercenaries.WAGE_INTERVAL - 1
  local goldBefore = game.player.gold
  game:endPlayerTurn()
  eq(game.player.gold, goldBefore - sellsword.wage, "the wage interval turn bills the live hireling")
end

function tests.mercenaryFieldsSurviveSerialization()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local medic = Mercenaries.hire(game, "medic")
  medic.loyalty = 55
  local restoredLevel = Level.fromData(game.level:toData())
  eq(#restoredLevel.entities, 1, "the hireling survives a level round trip")
  eq(restoredLevel.entities[1].kind, "hireling", "the hireling's kind survives a round trip")
  eq(restoredLevel.entities[1].species, "medic", "the hireling's roster key survives a round trip")
  eq(restoredLevel.entities[1].wage, Mercenaries.byKey.medic.wage, "the hireling's wage survives a round trip")
  eq(restoredLevel.entities[1].loyalty, 55, "the hireling's loyalty survives a round trip")
end

function tests.movePlayerSwapsPlacesWithAHiredHirelingToo()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  local hpBefore = sellsword.hp
  game:movePlayer(1, 0)
  eq(sellsword.x, 5, "a hireling is displaced by a swap exactly like a companion, never attacked")
  eq(sellsword.hp, hpBefore, "swapping past a hireling never damages it")
end

return tests
