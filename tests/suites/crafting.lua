local helpers = require("helpers")
local Items = require("items")
local Affixes = require("affixes")
local Status = require("status")
local Monsters = require("monsters")
local Game = require("game")
local Crafting = require("crafting")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.craftingForgeSpendsEssenceForATierOneGem()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.essence = Crafting.FORGE_COST - 1
  local shortSuccess, shortReason = Crafting.forge(game.player, Crafting.FIRE)
  eq(shortSuccess, false, "forging refuses when essence is short of the cost")
  eq(shortReason, "not enough essence", "the refusal names the reason")

  game.player.essence = Crafting.FORGE_COST
  local success, gem = Crafting.forge(game.player, Crafting.FIRE)
  ok(success, "forging succeeds with exactly the cost in essence")
  eq(gem.tier, 1, "a forged gem starts at tier one")
  eq(gem.element, Crafting.FIRE, "the gem carries the requested element")
  eq(game.player.essence, 0, "the forge cost is spent")

  local badSuccess, badReason = Crafting.forge(game.player, "shadow")
  eq(badSuccess, false, "an unknown element is refused")
  eq(badReason, "no such element", "the refusal names the reason")
end

function tests.craftingMergeGemsCombinesMatchingPairsIntoTheNextTier()
  local success, _, merged = Crafting.mergeGems(Crafting.gem(Crafting.FIRE, 1), Crafting.gem(Crafting.FIRE, 1))
  ok(success, "two matching chip gems merge")
  eq(merged.tier, 2, "the merged gem is one tier higher")
  eq(merged.element, Crafting.FIRE, "the merged gem keeps the shared element")
  eq(merged.power, 2, "a gem's power always matches its tier")

  local mismatchElement, elementReason = Crafting.mergeGems(Crafting.gem(Crafting.FIRE, 1), Crafting.gem(Crafting.FROST, 1))
  eq(mismatchElement, false, "gems of different elements refuse to merge")
  eq(elementReason, "elements do not match", "the refusal names the reason")

  local mismatchTier, tierReason = Crafting.mergeGems(Crafting.gem(Crafting.FIRE, 1), Crafting.gem(Crafting.FIRE, 2))
  eq(mismatchTier, false, "gems of different tiers refuse to merge")
  eq(tierReason, "tiers do not match", "the refusal names the reason")

  local atCap, capReason = Crafting.mergeGems(
    Crafting.gem(Crafting.FIRE, Crafting.MAX_TIER), Crafting.gem(Crafting.FIRE, Crafting.MAX_TIER))
  eq(atCap, false, "a gem already at the maximum tier cannot merge further")
  eq(capReason, "already at maximum tier", "the refusal names the reason")
end

function tests.craftingSocketAddsPowerAndSwapsRiderOnResocket()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  local attackBaseline = game.player.attack

  ok(Crafting.socket(game.player, weapon, Crafting.gem(Crafting.FIRE, 1)),
    "a gem sockets into an equipped weapon")
  eq(weapon.power, 3, "the gem's power lands on the item")
  eq(game.player.attack, attackBaseline + 1, "socketing an equipped weapon updates attack immediately")
  eq(weapon.socket.element, Crafting.FIRE, "the socket records its element")

  ok(Crafting.socket(game.player, weapon, Crafting.gem(Crafting.FROST, 2)),
    "resocketing replaces the previous gem")
  eq(weapon.power, 4, "power reflects only the new gem, not a stack of both")
  eq(game.player.attack, attackBaseline + 2, "attack reflects the swap, not an accumulation")
  eq(weapon.socket.element, Crafting.FROST, "the new gem's element replaces the old one")

  local success, reason = Crafting.socket(game.player, weapon, { kind = Items.WEAPON })
  eq(success, false, "a non-gem refuses to socket")
  eq(reason, "not a gem", "the refusal names the reason")
end

function tests.craftingTemperRaisesPowerAtRisingCostUpToACap()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  local attackBaseline = game.player.attack
  local totalCost = 0
  for level = 0, Crafting.TEMPER_MAX - 1 do
    totalCost = totalCost + (level + 1) * 4
  end
  game.player.essence = totalCost

  for level = 1, Crafting.TEMPER_MAX do
    ok(Crafting.temper(game.player, weapon), "temper step " .. level .. " succeeds with enough essence")
  end
  eq(weapon.power, 2 + Crafting.TEMPER_MAX, "each temper step adds exactly one flat power")
  eq(game.player.attack, attackBaseline + Crafting.TEMPER_MAX,
    "tempering an equipped weapon updates attack immediately")
  eq(game.player.essence, 0, "the full ladder of rising costs is spent exactly")

  local success, reason = Crafting.temper(game.player, weapon)
  eq(success, false, "a fully tempered item refuses a further step")
  eq(reason, "fully tempered", "the refusal names the reason")
end

function tests.craftingTemperRefusesWithoutEnoughEssence()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("mace", 3)
  Items.equipWeapon(weapon, game.player)
  game.player.essence = 3
  local success, reason = Crafting.temper(game.player, weapon)
  eq(success, false, "tempering fails when essence is short of the cost")
  eq(reason, "not enough essence", "the refusal names the reason")
  eq(weapon.power, 3, "a failed temper leaves power untouched")
  eq(game.player.essence, 3, "a failed temper spends nothing")
end

function tests.craftingEnchantGrantsAChosenAffixOnce()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  local attackBaseline = game.player.attack
  game.player.essence = Crafting.ENCHANT_COST

  ok(Crafting.enchant(game.player, weapon, "flaming"), "enchanting an unaffixed weapon succeeds")
  eq(weapon.affix.key, "flaming", "the chosen affix is attached, not a random roll")
  eq(weapon.power, 3, "the affix's power lands on the item")
  eq(weapon.name, "flaming dagger", "the affix prefix is applied to the name")
  eq(game.player.attack, attackBaseline + 1, "enchanting an equipped weapon updates attack immediately")
  eq(game.player.essence, 0, "the enchant cost is spent")

  local repeatSuccess, repeatReason = Crafting.enchant(game.player, weapon, "vicious")
  eq(repeatSuccess, false, "an already-affixed weapon refuses a second enchant")
  eq(repeatReason, "already bears an affix", "the refusal names the reason")

  local badSuccess, badReason = Crafting.enchant(game.player, Items.armor("leather armor", 1), "not-a-real-affix")
  eq(badSuccess, false, "an unknown affix key is refused")
  eq(badReason, "unknown affix", "the refusal names the reason")

  local ringSuccess, ringReason = Crafting.enchant(game.player, Items.ring("ring of power", 1, 1), "sharp")
  eq(ringSuccess, false, "gear without an affix pool cannot be enchanted")
  eq(ringReason, "cannot be enchanted", "the refusal names the reason")
end

function tests.craftingDisenchantStripsAffixAndRefundsEssence()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local armor = Affixes.decorate(Items.armor("chain mail", 2), Affixes.armor[2])
  Items.equipArmor(armor, game.player)
  local defenseBaseline = game.player.defense
  eq(armor.name, "reinforced chain mail", "sanity check: the drop rolled the expected affix")

  local success, refund = Crafting.disenchant(game.player, armor)
  ok(success, "disenchanting an affixed armor succeeds")
  eq(refund, Crafting.FORGE_COST + 2 * 3, "the refund scales with the stripped affix's power")
  eq(armor.power, 2, "power drops back to its base value")
  eq(armor.name, "chain mail", "the affix prefix is removed from the name")
  eq(armor.affix, nil, "the affix is gone")
  eq(game.player.defense, defenseBaseline - 2, "disenchanting an equipped armor updates defense immediately")
  eq(game.player.essence, refund, "the refund lands in the player's essence")

  local again, reason = Crafting.disenchant(game.player, armor)
  eq(again, false, "an already-plain item has nothing left to disenchant")
  eq(reason, "nothing to disenchant", "the refusal names the reason")
end

function tests.craftingSocketedGemRidersStackWithARolledAffixOnHit()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[4])
  Items.equipWeapon(weapon, game.player)
  ok(Crafting.socket(game.player, weapon, Crafting.gem(Crafting.SHOCK, 1)),
    "a shock gem sockets alongside the rolled affix")
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 30, 30
  game.level.entities = { orc }
  game:playerAttack(orc)
  eq(Status.has(orc, Status.POISON), true, "the rolled venomed affix still lands its rider")
  eq(Status.has(orc, Status.STUN), true, "the socketed shock gem lands its own rider on the same hit")
end

function tests.craftingShockRiderActuallyStunsTheVictimOnItsNextTurnNotJustOnPaper()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  ok(Crafting.socket(game.player, weapon, Crafting.gem(Crafting.SHOCK, 1)),
    "a bare shock gem sockets onto an unaffixed weapon")
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 30, 30
  game.level.entities = { orc }

  game:playerAttack(orc)
  eq(Status.has(orc, Status.STUN), true, "the shock rider lands immediately on the hit")

  local hpBefore, xBefore, yBefore = game.player.hp, orc.x, orc.y
  game:takeMonsterTurn(orc)
  eq(game.player.hp, hpBefore, "a stunned orc's very next turn deals no melee damage")
  eq(orc.x, xBefore, "a stunned orc's very next turn does not move")
  eq(orc.y, yBefore, "a stunned orc's very next turn does not move")

  game:takeMonsterTurn(orc)
  eq(Status.has(orc, Status.STUN), false, "the stun has fully expired by the turn after that")
  ok(game.player.hp < hpBefore, "once unstunned the orc resumes attacking normally")
end

function tests.gameCraftingWrappersDriveTheFullPipeline()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  local attackBaseline = game.player.attack

  game.player.essence = Crafting.FORGE_COST * 2
  ok(game:forgeGem(Crafting.FIRE), "forging a gem through the game wrapper succeeds")
  ok(game:forgeGem(Crafting.FIRE), "forging a second matching gem succeeds")
  local invBefore = #game.player.inventory

  local firstGemIndex, secondGemIndex
  for i, item in ipairs(game.player.inventory) do
    if item.kind == Items.GEM then
      if not firstGemIndex then firstGemIndex = i else secondGemIndex = i end
    end
  end
  ok(game:mergeGemsAt(firstGemIndex, secondGemIndex), "merging through the game wrapper succeeds")
  eq(#game.player.inventory, invBefore - 1, "merging removes both source gems and adds one merged gem")

  local mergedIndex
  for i, item in ipairs(game.player.inventory) do
    if item.kind == Items.GEM then mergedIndex = i end
  end
  ok(game:socketItem("weapon", mergedIndex), "socketing the equipped weapon through the game wrapper succeeds")
  eq(weapon.socket.element, Crafting.FIRE, "the socketed gem's element lands on the weapon")
  eq(game.player.attack, attackBaseline + 2, "socketing a tier-2 gem adds its power to attack")
  ok(not game:socketItem("weapon", mergedIndex), "the gem slot is consumed and cannot be socketed twice")

  game.player.essence = Crafting.temperCost(weapon)
  ok(game:temperItem("weapon"), "tempering the equipped weapon through the game wrapper succeeds")
  eq(weapon.power, 2 + 2 + 1, "temper stacks on top of the socket's power")
  eq(game.player.attack, attackBaseline + 3, "tempering the equipped weapon updates attack immediately")

  game.player.essence = Crafting.ENCHANT_COST
  ok(game:enchantItem("weapon", "vicious"), "enchanting the equipped weapon through the game wrapper succeeds")
  eq(weapon.affix.key, "vicious", "the chosen affix lands on the weapon")

  local beforeDisenchant = game.player.attack
  local expectedRefund = Crafting.FORGE_COST + 2 * 3
  ok(game:disenchantItem("weapon"), "disenchanting the equipped weapon through the game wrapper succeeds")
  eq(game.player.attack, beforeDisenchant - 2, "disenchanting removes the affix's power from attack")
  eq(game.player.essence, expectedRefund, "the disenchant refund lands in essence")
  ok(contains(game.log:recent(1)[1] or "", "disenchant"), "the disenchant is logged")
end

function tests.monsterKillsGrantEssenceScaledToTheirXpReward()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  local essenceBefore = game.player.essence
  game:playerAttack(rat)
  eq(game.player.essence, essenceBefore + Crafting.essenceFor(Monsters.xpFor(rat)),
    "a kill grants essence scaled to the monster's xp reward")
end

function tests.craftingFieldsSurviveSerialization()
  local game = Game.new(5)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  Crafting.socket(game.player, weapon, Crafting.gem(Crafting.VENOM, 2))
  game.player.essence = 37
  game.player.inventory[#game.player.inventory + 1] = Crafting.gem(Crafting.SHOCK, 1)

  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)

  eq(restored.player.essence, 37, "essence survives a save/load round trip")
  eq(restored.player.weapon.socket.element, Crafting.VENOM, "a socketed gem's element survives a save/load round trip")
  eq(restored.player.weapon.socket.tier, 2, "a socketed gem's tier survives a save/load round trip")
  local restoredGem
  for _, item in ipairs(restored.player.inventory) do
    if item.kind == Items.GEM then restoredGem = item end
  end
  ok(restoredGem ~= nil, "a loose gem in the inventory survives a save/load round trip")
  eq(restoredGem.element, Crafting.SHOCK, "the loose gem's element survives a save/load round trip")
end

function tests.disenchantingAnElementalAffixClearsItsDamageType()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[4])
  Items.equipWeapon(weapon, game.player)
  eq(weapon.damageType, "poison", "venomed tags the weapon as poison-typed")
  Crafting.disenchant(game.player, weapon)
  eq(weapon.damageType, nil, "disenchanting clears the elemental typing along with the affix")
end

return tests
