local helpers = require("helpers")
local Items = require("items")
local Effects = require("effects")
local Status = require("status")
local Monsters = require("monsters")
local Spells = require("spells")
local Resistances = require("resistances")
local Stealth = require("stealth")
local Disease = require("disease")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.spellCastMissileKillsAndGrantsXp()
  local game = stagedGame(5, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  local manaBefore = game.player.mana
  local success = game:castSpell("missile", rat)
  eq(success, true, "a known spell in range with a clear shot casts successfully")
  eq(game.player.mana, manaBefore - Spells.catalog.missile.cost, "casting spends mana")
  eq(#game.level.entities, 0, "the missile kills the rat and sweeps it from the level")
  eq(game.player.xp, Monsters.xpFor(rat), "a spell kill grants xp same as a melee kill")
end

function tests.spellCastFailsWithoutSpendingState()
  local game = stagedGame(5, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.mana = 0
  local success = game:castSpell("missile", rat)
  eq(success, false, "casting without enough mana fails")
  eq(game.player.mana, 0, "a failed cast does not touch mana")
  eq(rat.hp, rat.maxHp, "a failed cast deals no damage")

  game.player.mana = 10
  local success2 = game:castSpell("heal")
  eq(success2, false, "casting a spell that exists but was never learned fails")
  eq(game.player.mana, 10, "an unlearned spell cast spends no mana")

  local success3 = game:castSpell("fireball", rat)
  eq(success3, false, "casting a key that matches no spell in the catalog fails")
end

function tests.spellLearnFromTome()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  eq(Spells.knows(game.player, "heal"), false, "the starting kit does not know heal")
  game.player.inventory[#game.player.inventory + 1] = Items.tome("heal")
  game:useItem(#game.player.inventory)
  eq(Spells.knows(game.player, "heal"), true, "reading a tome permanently learns its spell")

  local before = #game.player.inventory
  game.player.inventory[#game.player.inventory + 1] = Items.tome("heal")
  game:useItem(#game.player.inventory)
  eq(#game.player.inventory, before, "the tome is consumed whether or not the spell was new")
end

function tests.spellHealAndShield()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "heal")
  Spells.learn(game.player, "shield")
  game.player.hp = 10
  local manaBefore = game.player.mana
  game:castSpell("heal")
  eq(game.player.hp > 10, true, "the heal spell restores hp")
  eq(game.player.mana, manaBefore - Spells.catalog.heal.cost, "casting heal spends its mana cost")

  local defenseBefore = game.player:effectiveDefense()
  game:castSpell("shield")
  eq(game.player:effectiveDefense() > defenseBefore, true, "the shield spell raises effective defense")
  ok(Status.has(game.player, Status.SHIELD), "shield applies the shield status")
end

function tests.spellBlinkMovesWithinRadius()
  local game = stagedGame(3, arena(21, 11), 10, 6)
  Spells.learn(game.player, "blink")
  local startX, startY = game.player.x, game.player.y
  local success = game:castSpell("blink")
  eq(success, true, "blink casts when mana and known")
  local moved = game.player.x ~= startX or game.player.y ~= startY
  ok(moved, "blink relocates the caster")
  local dist = math.max(math.abs(game.player.x - startX), math.abs(game.player.y - startY))
  ok(dist <= 5, "blink lands within its radius")
  eq(game.level.map:isWalkable(game.player.x, game.player.y), true, "blink lands on walkable ground")
end

function tests.manaRegeneratesEachTurn()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.mana = 0
  game.level.entities = {}
  game:endPlayerTurn()
  eq(game.player.mana, 1, "mana regenerates by one per player turn")
  game.player.mana = game.player.maxMana
  game:endPlayerTurn()
  eq(game.player.mana, game.player.maxMana, "mana regeneration is capped at max mana")
end

function tests.spellMissileAndFireballRespectTargetResistance()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local wisp = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  wisp.hp, wisp.maxHp = 40, 40
  wisp.resist = { arcane = Resistances.IMMUNE }
  game.level.entities = { wisp }
  game:castSpell("missile", wisp)
  eq(wisp.hp, 40, "an arcane-immune target takes no damage from magic missile")

  local blastGame = stagedGame(2, arena(21, 11), 5, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  orc.hp, orc.maxHp = 20, 20
  orc.resist = { fire = Resistances.RESIST }
  blastGame.level.entities = { orc }
  Effects.apply("fireball", blastGame, blastGame.player, {})
  eq(orc.hp, 16, "a fire-resistant target only takes half of fireball's flat burn")
end

function tests.spellShockBoltDealsMoreDamageToASoakedTargetThanADryOne()
  local dryGame = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(dryGame.player, "shock")
  local dry = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  dry.hp, dry.maxHp = 100, 100
  dryGame.level.entities = { dry }
  local castOk = dryGame:castSpell("shock", dry)
  ok(castOk, "casting a learned, in-range shock bolt succeeds")
  local dryDealt = 100 - dry.hp
  ok(dryDealt > 0, "shock bolt deals real lightning damage to a dry target")

  local wetGame = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(wetGame.player, "shock")
  local soaked = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  soaked.hp, soaked.maxHp = 100, 100
  soaked.wet = 2
  wetGame.level.entities = { soaked }
  wetGame:castSpell("shock", soaked)
  local wetDealt = 100 - soaked.hp
  eq(wetDealt, dryDealt + dryDealt // 2,
    "shock bolt deals exactly its 50 percent conductivity bonus against a soaked target")
  ok(contains(wetGame.log:last(), "water clinging"),
    "casting shock bolt on a soaked target reports the conductivity through water")
end

function tests.spellsDiscordAppliesTheDiscordStatusAndSpendsItsListedManaCost()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "discord")
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  game.level.entities = { orc }
  local manaBefore = game.player.mana
  local success = game:castSpell("discord", orc)
  ok(success, "casting a learned, in-range discord succeeds")
  ok(Status.has(orc, Status.DISCORD), "the target now carries the discord status")
  eq(game.player.mana, manaBefore - Spells.catalog.discord.cost, "casting discord spends exactly its listed mana cost")
end

function tests.spellsDiscordFailsOutOfRangeAndSpendsNothing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "discord")
  local farOrc = Monsters.create(Monsters.byKey.orc, 1, 19, 6, 1)
  game.level.entities = { farOrc }
  local manaBefore = game.player.mana
  local success = game:castSpell("discord", farOrc)
  ok(not success, "discord cast beyond its range fails")
  ok(not Status.has(farOrc, Status.DISCORD), "a failed cast never applies the status")
  eq(game.player.mana, manaBefore, "a failed cast spends no mana")
end

function tests.spellsConfuseAppliesTheConfuseStatusAndSpendsItsListedManaCost()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "confuse")
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  game.level.entities = { orc }
  local manaBefore = game.player.mana
  local success = game:castSpell("confuse", orc)
  ok(success, "casting a learned, in-range confuse succeeds")
  ok(Status.has(orc, Status.CONFUSE), "the target now carries the confuse status")
  eq(game.player.mana, manaBefore - Spells.catalog.confuse.cost, "casting confuse spends exactly its listed mana cost")
end

function tests.spellsConfuseFailsOutOfRangeAndSpendsNothing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "confuse")
  local farOrc = Monsters.create(Monsters.byKey.orc, 1, 19, 6, 1)
  game.level.entities = { farOrc }
  local manaBefore = game.player.mana
  local success = game:castSpell("confuse", farOrc)
  ok(not success, "confuse cast beyond its range fails")
  ok(not Status.has(farOrc, Status.CONFUSE), "a failed cast never applies the status")
  eq(game.player.mana, manaBefore, "a failed cast spends no mana")
end

function tests.spellsBlindAppliesTheBlindStatusAndSpendsItsListedManaCost()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "blind")
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  game.level.entities = { orc }
  local manaBefore = game.player.mana
  local success = game:castSpell("blind", orc)
  ok(success, "casting a learned, in-range blind succeeds")
  ok(Status.has(orc, Status.BLIND), "the target now carries the blind status")
  eq(game.player.mana, manaBefore - Spells.catalog.blind.cost, "casting blind spends exactly its listed mana cost")
end

function tests.spellsBlindFailsOutOfRangeAndSpendsNothing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "blind")
  local farOrc = Monsters.create(Monsters.byKey.orc, 1, 19, 6, 1)
  game.level.entities = { farOrc }
  local manaBefore = game.player.mana
  local success = game:castSpell("blind", farOrc)
  ok(not success, "blind cast beyond its range fails")
  ok(not Status.has(farOrc, Status.BLIND), "a failed cast never applies the status")
  eq(game.player.mana, manaBefore, "a failed cast spends no mana")
end

function tests.spellsWeakenAppliesTheWeakenStatusAndReducesAttackAndSpendsItsListedManaCost()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "weaken")
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  game.level.entities = { orc }
  local effectiveAttackBefore = orc:effectiveAttack()
  local manaBefore = game.player.mana
  local success = game:castSpell("weaken", orc)
  ok(success, "casting a learned, in-range weaken succeeds")
  ok(Status.has(orc, Status.WEAKEN), "the target now carries the weaken status")
  eq(orc:effectiveAttack() + 3, effectiveAttackBefore, "weaken's -3 attack modifier is folded into the target's effective attack")
  eq(game.player.mana, manaBefore - Spells.catalog.weaken.cost, "casting weaken spends exactly its listed mana cost")
end

function tests.spellsWeakenFailsOutOfRangeAndSpendsNothing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "weaken")
  local farOrc = Monsters.create(Monsters.byKey.orc, 1, 19, 6, 1)
  game.level.entities = { farOrc }
  local manaBefore = game.player.mana
  local success = game:castSpell("weaken", farOrc)
  ok(not success, "weaken cast beyond its range fails")
  ok(not Status.has(farOrc, Status.WEAKEN), "a failed cast never applies the status")
  eq(game.player.mana, manaBefore, "a failed cast spends no mana")
end

function tests.spellsCleanseLiftsHostileStatusesAndDiseaseOnTheCasterAndSpendsItsListedManaCost()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "cleanse")
  Status.apply(game.player, Status.POISON, 5, 2)
  Status.apply(game.player, Status.CONFUSE, 6, 1)
  Disease.infect(game.player, Disease.PARASITES)
  local manaBefore = game.player.mana
  local success = game:castSpell("cleanse")
  ok(success, "casting a learned, self-targeted cleanse succeeds")
  ok(not Status.has(game.player, Status.POISON), "cleanse lifts poison from the caster")
  ok(not Status.has(game.player, Status.CONFUSE), "cleanse lifts confusion from the caster")
  ok(not Disease.isInfected(game.player), "cleanse also lifts an active infection, like the cure potion does")
  eq(game.player.mana, manaBefore - Spells.catalog.cleanse.cost, "casting cleanse spends exactly its listed mana cost")
  eq(game.log:last(), "your affliction lifts, and the poison and confusion fade",
    "the single logged line credits both the disease and the status effects it lifted, with a plural verb")
end

function tests.spellsCleanseNamesOneTwoAndThreeLiftedStatusesAsNounsInANaturalList()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "cleanse")
  game.player.mana = 100
  Status.apply(game.player, Status.CONFUSE, 6, 1)
  game:castSpell("cleanse")
  eq(game.log:last(), "the confusion fades", "a single lifted status is named as a noun with a singular verb")
  Status.apply(game.player, Status.BLIND, 6, 1)
  Status.apply(game.player, Status.WEAKEN, 6, 1)
  game:castSpell("cleanse")
  eq(game.log:last(), "the blindness and weakness fade", "two lifted statuses are joined with \"and\"")
  Status.apply(game.player, Status.POISON, 6, 1)
  Status.apply(game.player, Status.SLOW, 6, 1)
  Status.apply(game.player, Status.STUN, 6, 1)
  game:castSpell("cleanse")
  eq(game.log:last(), "the poison, slowness and stun fade", "three lifted statuses read as \"a, b and c\"")
end

function tests.spellsCleanseWithNothingHostileStillSucceedsAndSpendsMana()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "cleanse")
  local manaBefore = game.player.mana
  local success = game:castSpell("cleanse")
  ok(success, "casting cleanse with nothing to lift still succeeds, exactly like heal or shield always do")
  eq(game.player.mana, manaBefore - Spells.catalog.cleanse.cost, "mana is still spent even when there was nothing to cleanse")
  ok(contains(game.log:last(), "nothing to cleanse"), "the logged line is honest that nothing was actually lifted")
end

function tests.spellsLevitateAppliesTheLevitateStatusToTheCasterAndSpendsItsListedManaCost()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "levitate")
  local manaBefore = game.player.mana
  local success = game:castSpell("levitate")
  ok(success, "casting a learned, self-targeted levitate succeeds")
  ok(Status.has(game.player, Status.LEVITATE), "the caster now carries the levitate status")
  eq(game.player.mana, manaBefore - Spells.catalog.levitate.cost, "casting levitate spends exactly its listed mana cost")
end

function tests.spellsPolymorphTransformsTheTargetAndSpendsItsListedManaCost()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "polymorph")
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  game.level.entities = { orc }
  local manaBefore = game.player.mana
  local success = game:castSpell("polymorph", orc)
  ok(success, "casting a learned, in-range polymorph succeeds")
  ok(orc.species ~= "orc", "the target's species actually changed")
  eq(game.player.mana, manaBefore - Spells.catalog.polymorph.cost, "casting polymorph spends exactly its listed mana cost")
end

function tests.spellsPolymorphFailsOutOfRangeAndSpendsNothing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "polymorph")
  local farOrc = Monsters.create(Monsters.byKey.orc, 1, 19, 6, 1)
  game.level.entities = { farOrc }
  local manaBefore = game.player.mana
  local success = game:castSpell("polymorph", farOrc)
  ok(not success, "polymorph cast beyond its range fails")
  eq(farOrc.species, "orc", "a failed cast never transforms the target")
  eq(game.player.mana, manaBefore, "a failed cast spends no mana")
end

function tests.gameCastSpellOnlyEmitsNoiseOnASuccessfulCastNeverOnAFailedOne()
  local game = stagedGame(5, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  local bystander = Monsters.create(Monsters.byKey.orc, 2, 9, 6, 1)
  bystander.awareness = Stealth.DORMANT
  game.level.entities = { rat, bystander }
  game.player.mana = 0
  for _ = 1, 200 do
    game:castSpell("missile", rat)
  end
  eq(bystander.awareness, Stealth.DORMANT, "two hundred failed casts for lack of mana never make a sound")

  game.player.mana = 999
  local stirred = false
  for _ = 1, 200 do
    rat.hp = rat.maxHp
    game:castSpell("missile", rat)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a spell that actually goes off is loud enough to eventually stir a nearby bystander")
end

return tests
