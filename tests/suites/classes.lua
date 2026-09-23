local helpers = require("helpers")
local Items = require("items")
local Game = require("game")

local ok, eq = helpers.ok, helpers.eq

local tests = helpers.suite()

function tests.classApplyGrantsFighterStatBonuses()
  local base = Game.new(9)
  local fighter = Game.new(9, { class = "fighter" })
  eq(fighter.player.class, "fighter", "the requested class is stamped onto the player")
  eq(fighter.player.maxHp, base.player.maxHp + 8, "fighter grants a flat max hp bonus")
  eq(fighter.player.hp, base.player.hp + 8, "the hp bonus also tops up current hp")
  eq(fighter.player.attack, base.player.attack + 2, "fighter grants a flat attack bonus")
end

function tests.classApplyGrantsRogueGoldAndAttack()
  local base = Game.new(9)
  local rogue = Game.new(9, { class = "rogue" })
  eq(rogue.player.gold, base.player.gold + 15, "rogue starts with extra gold")
  eq(rogue.player.attack, base.player.attack + 1, "rogue grants a small attack bonus")
end

function tests.classApplyGrantsMageManaAndAttack()
  local base = Game.new(9)
  local mage = Game.new(9, { class = "mage" })
  eq(mage.player.maxMana, base.player.maxMana + 8, "mage grants a flat mana bonus")
  eq(mage.player.mana, base.player.mana + 8, "the mana bonus also tops up current mana")
  eq(mage.player.attack, base.player.attack - 1, "mage trades some attack for its mana pool")
end

function tests.classApplyGrantsRangerBowAndAmmo()
  local ranger = Game.new(9, { class = "ranger" })
  ok(ranger.player.bow ~= nil, "ranger starts with a bow equipped")
  local hasAmmo = false
  for _, item in ipairs(ranger.player.inventory) do
    if item.kind == Items.AMMO then hasAmmo = true end
  end
  ok(hasAmmo, "ranger starts with a stack of arrows")
end

function tests.invalidClassIsIgnored()
  local base = Game.new(9)
  local weird = Game.new(9, { class = "wizard" })
  eq(weird.player.class, nil, "an unrecognised class name is not applied")
  eq(weird.player.maxHp, base.player.maxHp, "stats are unaffected by an invalid class")
end

return tests
