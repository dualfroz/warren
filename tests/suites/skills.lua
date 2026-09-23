local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Affixes = require("affixes")
local Status = require("status")
local Monsters = require("monsters")
local Game = require("game")
local Skills = require("skills")
local Resistances = require("resistances")

local ok, eq, arena, stagedGame, arenaDark = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame, helpers.arenaDark

local tests = helpers.suite()

function tests.skillLearnRespectsClassLevelAndPoints()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skillPoints = 0
  eq(game:learnSkill("cleave"), false, "learning fails without a banked skill point")
  game.player.skillPoints = 1
  eq(game:learnSkill("backstab"), false, "learning a skill from another class fails")
  eq(game.player.skillPoints, 1, "a failed learn spends no point")
  eq(game:learnSkill("berserk"), false, "learning fails below the skill's level requirement")
  eq(game:learnSkill("cleave"), true, "a same-class, level-eligible skill with a point banked learns")
  eq(game.player.skillPoints, 0, "learning spends the point")
  eq(Skills.has(game.player, "cleave"), true, "the skill is now known")
  game.player.skillPoints = 1
  eq(game:learnSkill("cleave"), false, "an already-known skill cannot be learned twice")
  eq(game.player.skillPoints, 1, "re-learning a known skill spends no point")
end

function tests.skillCooldownBlocksImmediateReuseAndTicksDown()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.secondWind = true
  game.player.hp = game.player.maxHp - 10
  eq(game:useSkill("secondWind"), true, "second wind activates while off cooldown")
  eq(game:useSkill("secondWind"), false, "an immediate reuse fails while on cooldown")
  for _ = 1, Skills.active.secondWind.cooldown do
    game:endPlayerTurn()
  end
  eq(game.player.skillCooldowns.secondWind, 0, "the cooldown ticks down to zero over that many player turns")
  game.player.hp = game.player.maxHp - 10
  eq(game:useSkill("secondWind"), true, "second wind is usable again once its cooldown fully elapses")
end

function tests.fighterCleaveHitsPrimaryAndAdjacentMonsters()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.cleave = true
  local primary = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  local splash = Monsters.create(Monsters.byKey.orc, 2, 3, 5, 1)
  game.level.entities = { primary, splash }
  local success = game:useSkill("cleave", primary)
  eq(success, true, "cleave lands on an adjacent primary target")
  ok(primary.hp < primary.maxHp, "the primary target takes damage")
  ok(splash.hp < splash.maxHp, "a second monster adjacent to the player also takes splash damage")
  ok((splash.maxHp - splash.hp) < (primary.maxHp - primary.hp), "the splash hit deals less than the primary hit")
  eq(game.player.skillCooldowns.cleave, Skills.active.cleave.cooldown, "cleave starts its own cooldown")
end

function tests.fighterCleaveSplashRespectsAFireImmuneTargetLikeThePrimaryHitAlreadyDoes()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.cleave = true
  game.player.weapon = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[3])
  eq(game.player.weapon.damageType, "fire", "the flaming affix retags the dagger's swing as fire")
  local primary = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  local immune = Monsters.create(Monsters.byKey.dragon, 2, 3, 5, 6)
  game.level.entities = { primary, immune }
  game:useSkill("cleave", primary)
  ok(primary.hp < primary.maxHp, "the primary target still burns for full mitigated damage")
  eq(immune.hp, immune.maxHp, "a fire-immune splash target takes zero cleave splash from a flaming weapon")
end

function tests.fighterSecondWindRestoresPortionOfMaxHp()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.secondWind = true
  game.player.hp = 5
  game:useSkill("secondWind")
  eq(game.player.hp, 5 + math.floor(game.player.maxHp * 0.3), "second wind restores three tenths of max hp")

  game.player.skillCooldowns.secondWind = 0
  game.player.hp = game.player.maxHp - 1
  game:useSkill("secondWind")
  eq(game.player.hp, game.player.maxHp, "second wind never heals past max hp")
end

function tests.fighterBerserkBoostsAttackAtLowHp()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.berserk = true
  local full = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  game.level.entities = { full }
  game.player.hp = game.player.maxHp
  game:playerAttack(full)
  local dmgFull = full.maxHp - full.hp

  local game2 = stagedGame(1, arena(21, 11), 3, 6)
  game2.player.class = "fighter"
  game2.player.skills.berserk = true
  local low = Monsters.create(Monsters.byKey.orc, 2, 4, 6, 1)
  game2.level.entities = { low }
  game2.player.hp = math.floor(game2.player.maxHp * 0.3)
  game2:playerAttack(low)
  local dmgLow = low.maxHp - low.hp

  ok(dmgLow > dmgFull, "berserk raises attack once hp drops to a third of max")
end

function tests.rogueBackstabDoublesDamageOnFullHpTarget()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "rogue"
  game.player.skills.backstab = true
  local fresh = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  game.level.entities = { fresh }
  game:playerAttack(fresh)
  local dmgFresh = fresh.maxHp - fresh.hp

  local game2 = stagedGame(1, arena(21, 11), 3, 6)
  game2.player.class = "rogue"
  game2.player.skills.backstab = true
  local hurt = Monsters.create(Monsters.byKey.rat, 2, 4, 6, 1)
  hurt.hp = hurt.hp - 1
  game2.level.entities = { hurt }
  game2:playerAttack(hurt)
  local dmgHurt = (hurt.maxHp - 1) - hurt.hp

  eq(dmgFresh, dmgHurt * 2, "backstab doubles damage against a target still at full hp")
end

function tests.rogueEvasionCanFullyNegateMeleeHit()
  local defender = { skills = { evasion = true } }
  local sawDodge, sawHit = false, false
  local rng = Rng.new(1)
  for _ = 1, 60 do
    if Skills.evades({ rng = rng }, defender) then sawDodge = true else sawHit = true end
  end
  ok(sawDodge, "evasion dodges at least once over enough attempts")
  ok(sawHit, "evasion is a chance, not a guarantee, over enough attempts")
  eq(Skills.evades({ rng = Rng.new(1) }, {}), false, "a defender without the skill never evades")
end

function tests.poisonBladeAppliesPoisonOnNextMeleeHitOnly()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "rogue"
  game.player.skills.poisonBlade = true
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 100, 100
  game.level.entities = { orc }
  eq(game:useSkill("poisonBlade"), true, "poison blade readies without needing a target")
  game:playerAttack(orc)
  ok(Status.has(orc, Status.POISON), "the readied venom lands on the very next melee hit")
  orc.statuses = {}
  game:playerAttack(orc)
  eq(Status.has(orc, Status.POISON), false, "poison blade is spent after one hit, not reapplied on the next")
end

function tests.pendingPoisonBladeReadinessSurvivesAGameSaveLoadRoundTrip()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "rogue"
  game.player.skills.poisonBlade = true
  eq(game:useSkill("poisonBlade"), true, "poison blade readies without needing a target")
  eq(game.player.pendingPoisonBlade, true, "readying the skill sets the pending flag before any save/load happens")
  local restored = Game.fromData(game:toData())
  eq(restored.player.pendingPoisonBlade, true, "a poison blade readied before a save is still primed after loading it back")
  ok(Skills.consumePoisonBlade(restored.player), "the restored pending venom is still consumable on the very next swing")
end

function tests.mageOverloadBoostsMissileDamage()
  local game = stagedGame(5, arena(21, 11), 3, 6)
  local base = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  game.level.entities = { base }
  game:castSpell("missile", base)
  local dmgBase = base.maxHp - base.hp

  local game2 = stagedGame(5, arena(21, 11), 3, 6)
  game2.player.class = "mage"
  game2.player.skills.overload = true
  local boosted = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  game2.level.entities = { boosted }
  game2:castSpell("missile", boosted)
  local dmgBoosted = boosted.maxHp - boosted.hp

  ok(dmgBoosted > dmgBase, "overload raises missile spell damage")
end

function tests.mageMeditateRestoresManaWithinCap()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "mage"
  game.player.skills.meditate = true
  game.player.mana = 2
  game:useSkill("meditate")
  eq(game.player.mana, 8, "meditate restores a flat amount of mana")

  game.player.mana = game.player.maxMana - 1
  game:useSkill("meditate")
  eq(game.player.mana, game.player.maxMana, "meditate never overfills the mana pool")
end

function tests.mageManaShieldRaisesDefenseWhileManaHeld()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "mage"
  game.player.skills.manaShield = true
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  local before = game.player.hp
  game.player.mana = 10
  game:monsterMelee(orc)
  local dmgWithShield = before - game.player.hp

  game.player.hp = before
  game.player.mana = 0
  game:monsterMelee(orc)
  local dmgWithoutShield = before - game.player.hp

  ok(dmgWithoutShield > dmgWithShield, "mana shield reduces damage taken while mana holds")
end

function tests.rangerMultishotHitsTwoTargetsForOneArrow()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "ranger"
  game.player.skills.multishot = true
  game.player.bow = Items.bow("shortbow", 3, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 5)
  local first = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  local second = Monsters.create(Monsters.byKey.orc, 2, 3, 8, 1)
  game.level.entities = { first, second }
  local success = game:useSkill("multishot", first, second)
  eq(success, true, "multishot succeeds with two reachable targets")
  ok(first.hp < first.maxHp, "the primary target takes damage")
  ok(second.hp < second.maxHp, "the secondary target takes damage")
  local stack
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.AMMO then stack = item end
  end
  eq(stack.count, 4, "multishot consumes only a single arrow for both targets")
end

function tests.rangerMultishotRespectsPhysicalResistanceOnBothSplitArrows()
  local function primaryDamageDealt(resistant)
    local game = stagedGame(1, arena(21, 11), 3, 6)
    game.player.class = "ranger"
    game.player.skills.multishot = true
    game.player.bow = Items.bow("shortbow", 3, 6)
    game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 5)
    local first = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
    first.hp, first.maxHp = 100, 100
    if resistant then first.resist = { physical = Resistances.RESIST } end
    local second = Monsters.create(Monsters.byKey.orc, 2, 3, 8, 1)
    second.hp, second.maxHp = 100, 100
    game.level.entities = { first, second }
    game:useSkill("multishot", first, second)
    return 100 - first.hp
  end
  local plain = primaryDamageDealt(false)
  local resisted = primaryDamageDealt(true)
  ok(resisted < plain, "a physically resistant target takes measurably less multishot damage than an unresisted one")
  eq(resisted, math.floor(plain / 2), "physical resistance halves the split-arrow hit, the same mitigation Resistances.apply gives a single Ranged.fire shot")
end

function tests.rangerCamouflageShrinksDetectionOnDarkFloors()
  local game = stagedGame(1, arenaDark(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 11, 6, 1)
  eq(game:canSeePlayer(orc, 10), true, "without camouflage a dark floor does not shrink detection")

  game.player.class = "ranger"
  game.player.skills.camouflage = true
  eq(game:canSeePlayer(orc, 10), false, "camouflage shrinks a monster's detection range on a dark floor")

  game.level.dark = false
  eq(game:canSeePlayer(orc, 10), true, "camouflage does nothing once the floor is lit")
end

function tests.rangerTrueshotAddsFlatRangedDamage()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local base = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  game.level.entities = { base }
  game.player.bow = Items.bow("short bow", 2, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 2)
  game:fireAt(base)
  local dmgBase = base.maxHp - base.hp

  local game2 = stagedGame(4, arena(21, 11), 3, 6)
  game2.player.class = "ranger"
  game2.player.skills.trueshot = true
  local boosted = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  game2.level.entities = { boosted }
  game2.player.bow = Items.bow("short bow", 2, 6)
  game2.player.inventory[#game2.player.inventory + 1] = Items.ammo("arrow", 2)
  game2:fireAt(boosted)
  local dmgTrueshot = boosted.maxHp - boosted.hp

  eq(dmgTrueshot, dmgBase + 3, "trueshot adds a flat +3 to every ranged hit")
end

function tests.skillFieldsSurviveSerialization()
  local game = Game.new(5, { class = "mage" })
  game.player.skills.overload = true
  game.player.skillCooldowns.meditate = 2
  game.player.skillPoints = 3
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.class, "mage", "class survives a save/load round trip")
  eq(restored.player.skillPoints, 3, "skill points survive a save/load round trip")
  eq(Skills.has(restored.player, "overload"), true, "learned skills survive a save/load round trip")
  eq(restored.player.skillCooldowns.meditate, 2, "skill cooldowns survive a save/load round trip")
end

return tests
