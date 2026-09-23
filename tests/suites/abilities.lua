local helpers = require("helpers")
local Entity = require("entity")
local Items = require("items")
local Status = require("status")
local Monsters = require("monsters")
local Ai = require("ai")
local Abilities = require("abilities")
local Companions = require("companions")
local Momentum = require("momentum")
local Durability = require("durability")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.trollRegenerateUnlessBurning()
  local troll = Monsters.create(Monsters.byKey.troll, 1, 5, 5, 1)
  troll.hp = troll.maxHp - 5
  local line = Abilities.regenTick(troll)
  ok(line ~= nil, "a damaged troll regenerates and logs it")
  eq(troll.hp, troll.maxHp - 5 + Monsters.byKey.troll.regen, "regen heals by the species regen amount")

  troll.hp = troll.maxHp
  eq(Abilities.regenTick(troll), nil, "a troll already at full hp produces no regen line")

  troll.hp = troll.maxHp - 5
  Status.apply(troll, Status.BURNING, 3, 2)
  eq(Abilities.regenTick(troll), nil, "burning suppresses troll regeneration")
end

function tests.ratHasNoRegen()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  rat.hp = 1
  eq(Abilities.regenTick(rat), nil, "a species without a regen tag never heals passively")
end

function tests.wretchDeathBurstsPoisonSpores()
  local game = stagedGame(1, arena(21, 11), 4, 6)
  local wretch = Monsters.create(Monsters.byKey.wretch, 1, 5, 6, 1)
  wretch.hp = 1
  game.level.entities = { wretch }
  eq(Status.has(game.player, Status.POISON), false, "the player starts unpoisoned")
  game:playerAttack(wretch)
  eq(Status.has(game.player, Status.POISON), true, "a wretch's death burst poisons an adjacent player")
  ok(contains(game.log:recent(3)[1] or "", "spores") or contains(game.log:recent(3)[2] or "", "spores")
    or contains(game.log:recent(3)[3] or "", "spores"), "the spore burst is logged")
end

function tests.sporeBurstNamesItsVictimsAsANaturalList()
  local game = stagedGame(1, arena(21, 11), 4, 6)
  local wretch = Monsters.create(Monsters.byKey.wretch, 1, 5, 6, 3)
  game.level.entities = { wretch }
  eq(Abilities.onDeath(game, wretch), "a burst of spores poisons you", "a lone victim is named without any joiner")
  local goblin = Monsters.create(Monsters.byKey.goblin, 2, 6, 6, 3)
  local rat = Monsters.create(Monsters.byKey.rat, 3, 5, 7, 3)
  game.level.entities = { wretch, goblin, rat }
  eq(Abilities.onDeath(game, wretch), "a burst of spores poisons you, goblin and rat",
    "three victims read as a, b and c")
end

function tests.dragonBreathIgnitesPlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local dragon = Monsters.create(Monsters.byKey.dragon, 1, 6, 6, 1)
  game.level.entities = { dragon }
  local hpBefore = game.player.hp
  Ai.act(game, dragon)
  ok(game.player.hp < hpBefore, "a dragon in range breathes fire for damage")
  eq(Status.has(game.player, Status.BURNING), true, "dragon breath ignites the player")
end

function tests.necromancerSummonsZombie()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local necro = Monsters.create(Monsters.byKey.necromancer, 1, 6, 6, 4)
  game.level.entities = { necro }
  local acted = Abilities.tryAct(game, necro)
  eq(acted, true, "a necromancer in range summons instead of moving")
  eq(#game.level.entities, 2, "summoning adds a minion to the level")
  local minion = game.level.entities[2]
  eq(minion.species, "zombie", "the necromancer summons its configured species")
  eq(minion.summonedBy, necro.id, "the minion is tagged with its summoner's id")
  eq(necro.cooldown, 6, "summoning starts the ability's cooldown")
  ok(contains(game.log:last(), "calls forth"), "the summon is logged")
end

function tests.summonRespectsPopulationCap()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local necro = Monsters.create(Monsters.byKey.necromancer, 1, 6, 6, 4)
  local minionA = Monsters.create(Monsters.byKey.zombie, 2, 7, 6, 4)
  local minionB = Monsters.create(Monsters.byKey.zombie, 3, 6, 7, 4)
  minionA.summonedBy = necro.id
  minionB.summonedBy = necro.id
  game.level.entities = { necro, minionA, minionB }
  local acted = Abilities.tryAct(game, necro)
  eq(acted, false, "a necromancer already at its summon cap does not summon a third")
  eq(#game.level.entities, 3, "the level still has exactly the two existing minions")
end

function tests.curseAtRangeHurtsAndWeakens()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  local hpBefore = game.player.hp
  local acted = Abilities.tryAct(game, shaman)
  eq(acted, true, "a shaman with a clear shot curses instead of moving")
  eq(game.player.hp, hpBefore - 1, "the curse bolt runs through Combat.damage (shaman attack 2 minus the player's base defense 1)")
  eq(Status.has(game.player, Status.WEAKEN), true, "the curse also weakens the player")
  eq(shaman.cooldown, 4, "casting the curse starts its cooldown")
  ok(contains(game.log:last(), "curses you for 1"), "the logged amount matches the mitigated damage, not a flat number")
end

function tests.curseDamageIsMitigatedByThePlayersDefenseLikeAnyOtherAttack()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  game.player.defense = game.player.defense + 10
  local hpBefore = game.player.hp
  Abilities.tryAct(game, shaman)
  eq(game.player.hp, hpBefore - 1, "a shaman's attack (2) minus a heavily-defended player floors at Combat.damage's minimum of 1, not a flat 3")
end

function tests.curseBreaksThePlayersMeleeMomentumStack()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  game.player.combo = 4
  Abilities.tryAct(game, shaman)
  eq(Momentum.stacks(game.player), 0, "a landed curse bolt snaps momentum to zero exactly like a melee hit or a breath attack")
end

function tests.curseWearsThePlayersEquippedArmor()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  game.player.armor = { name = "chainmail", kind = Items.ARMOR, power = 2, defense = 2 }
  Durability.ensure(game.player.armor)
  local durabilityBefore = game.player.armor.durability
  Abilities.tryAct(game, shaman)
  eq(game.player.armor.durability, durabilityBefore - 1, "the curse wears equipped armor exactly like a landed melee or breath hit does")
end

function tests.curseWithheldWhenAdjacent()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 4, 6, 4)
  game.level.entities = { shaman }
  local acted = Abilities.tryAct(game, shaman)
  eq(acted, false, "a shaman standing next to the player withholds its curse")
end

function tests.abilityCooldownBlocksImmediateReuse()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  Abilities.tryAct(game, shaman)
  local hpAfterFirst = game.player.hp
  local acted = Abilities.tryAct(game, shaman)
  eq(acted, false, "an ability on cooldown does not fire again")
  eq(game.player.hp, hpAfterFirst, "no further damage is dealt while on cooldown")
  for _ = 1, 4 do Abilities.tickCooldown(shaman) end
  eq(shaman.cooldown, 0, "four ticks fully drains a four-turn cooldown")
  local actedAgain = Abilities.tryAct(game, shaman)
  eq(actedAgain, true, "the ability is usable again once its cooldown has ticked down")
end

function tests.shriekAtRangeBlindsThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local banshee = Monsters.create(Monsters.byKey.banshee, 1, 7, 6, 5)
  game.level.entities = { banshee }
  eq(Status.has(game.player, Status.BLIND), false, "the player starts able to see")
  local acted = Abilities.tryAct(game, banshee)
  eq(acted, true, "a banshee with a clear shot shrieks instead of moving")
  eq(Status.has(game.player, Status.BLIND), true, "the shriek blinds the player")
  eq(banshee.cooldown, 6, "shrieking starts its cooldown")
  ok(contains(game.log:last(), "blinds you"), "the shriek is logged")
end

function tests.shriekWithheldWhenAdjacent()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local banshee = Monsters.create(Monsters.byKey.banshee, 1, 4, 6, 5)
  game.level.entities = { banshee }
  local acted = Abilities.tryAct(game, banshee)
  eq(acted, false, "a banshee standing next to the player withholds its shriek")
  eq(Status.has(game.player, Status.BLIND), false, "no shriek means no blindness")
end

function tests.shriekIsUnavailableOutOfRange()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local banshee = Monsters.create(Monsters.byKey.banshee, 1, 20, 6, 5)
  game.level.entities = { banshee }
  local acted = Abilities.tryAct(game, banshee)
  eq(acted, false, "a banshee out of shriek range falls through to its base ai")
  eq(Status.has(game.player, Status.BLIND), false, "no shriek means no blindness")
end

function tests.shriekBlindnessReducesTheVictimsEffectiveSightRadius()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local banshee = Monsters.create(Monsters.byKey.banshee, 1, 7, 6, 5)
  game.level.entities = { banshee }
  Abilities.tryAct(game, banshee)
  eq(game:effectiveRadius(), 1, "blind (also inflicted by a banshee) still narrows sight to game.lua's own radius")
end

function tests.healerMendsNeediestAlly()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local cleric = Monsters.create(Monsters.byKey.cleric, 1, 6, 6, 5)
  local hurt = Monsters.create(Monsters.byKey.rat, 2, 8, 6, 5)
  hurt.hp = 1
  game.level.entities = { cleric, hurt }
  local acted = Abilities.tryAct(game, cleric)
  eq(acted, true, "a cleric with a hurt ally in sight heals instead of moving")
  eq(hurt.hp, 7, "healing restores the fixed amount, capped at max hp")
  eq(cleric.cooldown, 5, "healing starts its cooldown")
end

function tests.healerSkipsWhenAlliesAreHealthy()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local cleric = Monsters.create(Monsters.byKey.cleric, 1, 6, 6, 5)
  local ally = Monsters.create(Monsters.byKey.rat, 2, 8, 6, 5)
  game.level.entities = { cleric, ally }
  local acted = Abilities.tryAct(game, cleric)
  eq(acted, false, "a cleric with no hurt allies falls through to its base ai")
end

function tests.healerNeverMendsThePlayersOwnCompanionHirelingOrThrall()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local cleric = Monsters.create(Monsters.byKey.cleric, 1, 6, 6, 5)
  local companion = Companions.summon(game, "hound")
  companion.x, companion.y = 8, 6
  companion.hp = 1
  game.level.entities = { cleric, companion }
  local acted = Abilities.tryAct(game, cleric)
  eq(acted, false, "a hurt companion is not a valid heal target, so the cleric falls through instead")
  eq(companion.hp, 1, "the player's own companion is left exactly as hurt as it was")
end

function tests.rallyBuffsAdjacentAllies()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 10, 6, 6)
  local grunt = Monsters.create(Monsters.byKey.goblin, 2, 11, 6, 6)
  game.level.entities = { chieftain, grunt }
  eq(Status.has(grunt, Status.STRENGTH), false, "the grunt starts unbuffed")
  local acted = Abilities.tryAct(game, chieftain)
  eq(acted, true, "a chieftain next to an unbuffed ally rallies instead of moving")
  eq(Status.has(grunt, Status.STRENGTH), true, "rallying buffs the adjacent ally")
  eq(Status.has(chieftain, Status.STRENGTH), true, "rallying also buffs the chieftain itself")
  eq(chieftain.cooldown, 8, "rallying starts its cooldown")
end

function tests.rallyNamesTheBuffedAlliesAsANaturalList()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 10, 6, 6)
  local goblin = Monsters.create(Monsters.byKey.goblin, 2, 11, 6, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 3, 10, 7, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 4, 9, 6, 6)
  game.level.entities = { chieftain, goblin, rat, orc }
  Abilities.tryAct(game, chieftain)
  eq(game.log:last(), "orc chieftain rallies goblin, rat and orc", "the rally line reads as a, b and c")
end

function tests.rallySkipsWhenNoUnbuffedAlliesAdjacent()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 10, 6, 6)
  game.level.entities = { chieftain }
  local acted = Abilities.tryAct(game, chieftain)
  eq(acted, false, "a chieftain with no adjacent allies falls through to its base ai")
end

function tests.rallyNeverBuffsThePlayersOwnCompanionHirelingOrThrall()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 10, 6, 6)
  local companion = Companions.summon(game, "hound")
  companion.x, companion.y = 11, 6
  game.level.entities = { chieftain, companion }
  local acted = Abilities.tryAct(game, chieftain)
  eq(acted, false, "an adjacent companion is not a valid rally target, so the chieftain falls through instead")
  eq(Status.has(companion, Status.STRENGTH), false, "the player's own companion is never buffed by a hostile chieftain")
  eq(Status.has(chieftain, Status.STRENGTH), false, "the chieftain does not even buff itself when it has no monster ally to rally")
end

function tests.footpadStealsThenFlees()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local footpad = Monsters.create(Monsters.byKey.footpad, 1, 4, 6, 4)
  game.level.entities = { footpad }
  local before = #game.player.inventory
  local acted = Abilities.tryAct(game, footpad)
  eq(acted, true, "an adjacent footpad steals instead of attacking")
  eq(#game.player.inventory, before - 1, "the stolen item leaves the player's inventory")
  eq(footpad.fleeing, true, "the footpad starts fleeing after the theft")
  ok(contains(game.log:last(), "steals"), "the theft is logged")

  local xBefore = footpad.x
  local actedAgain = Abilities.tryAct(game, footpad)
  eq(actedAgain, true, "a fleeing footpad keeps acting through its ability")
  eq(#game.player.inventory, before - 1, "a fleeing footpad does not steal again")
  ok(footpad.x ~= xBefore, "a fleeing footpad moves away from the player")
end

function tests.footpadWithNothingToStealStillFlees()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.inventory = {}
  local footpad = Monsters.create(Monsters.byKey.footpad, 1, 4, 6, 4)
  game.level.entities = { footpad }
  local acted = Abilities.tryAct(game, footpad)
  eq(acted, true, "a footpad with nothing to steal still consumes its turn")
  eq(footpad.fleeing, true, "it flees even without a prize")
  ok(contains(game.log:last(), "nothing worth stealing"), "the empty-handed theft attempt is logged")
end

function tests.slimeSplitsOnSurvivedHit()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local slime = Monsters.create(Monsters.byKey.slime, 1, 4, 6, 4)
  game.level.entities = { slime }
  eq(slime.hp, 13, "a depth-4 slime spawns with its bonus hp")
  game:playerAttack(slime)
  eq(slime:isAlive(), true, "the slime survives a single hit")
  eq(slime.maxHp, 6, "a surviving split halves the slime's max hp")
  eq(slime.hp, 6, "the split slime is left at its new max hp")
  eq(#game.level.entities, 2, "the split spawns a clone next to the original")
  local clone = game.level.entities[2]
  eq(clone.species, "slime", "the clone is the same species as the original")
  eq(clone.maxHp, 6, "the clone shares the halved max hp")
  eq(clone.splitGen, 1, "the clone is tagged as a first-generation split")
  ok(contains(game.log:last(), "splits in two"), "the split is logged")
end

function tests.splitCapsAtTwoGenerations()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local slime = Monsters.create(Monsters.byKey.slime, 1, 4, 6, 4)
  slime.splitGen = 2
  game.level.entities = { slime }
  local before = #game.level.entities
  local line = Abilities.onHit(game, slime)
  eq(line, nil, "a slime that already split twice does not split again")
  eq(#game.level.entities, before, "no clone is added once the split cap is reached")
end

function tests.abilityFieldsSurviveSerialization()
  local necro = Monsters.create(Monsters.byKey.necromancer, 5, 6, 6, 4)
  necro.cooldown = 3
  necro.fleeing = true
  necro.splitGen = 1
  necro.summonedBy = 2
  necro.stolen = Items.potion(10)
  local restored = Entity.fromData(necro:toData())
  eq(restored.ability, "summon", "the ability tag survives a round trip")
  eq(restored.summonSpecies, "zombie", "the summon species survives a round trip")
  eq(restored.cooldown, 3, "cooldown survives a round trip")
  eq(restored.fleeing, true, "the fleeing flag survives a round trip")
  eq(restored.splitGen, 1, "the split generation survives a round trip")
  eq(restored.summonedBy, 2, "the summoner id survives a round trip")
  eq(restored.stolen.name, "potion of healing", "a stolen item's data survives a round trip")
end

return tests
