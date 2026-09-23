local helpers = require("helpers")
local Rng = require("rng")
local Entity = require("entity")
local Items = require("items")
local Affixes = require("affixes")
local Identify = require("identify")
local Status = require("status")
local Monsters = require("monsters")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.itemsAndEquipment()
  local hero = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, maxHp = 30, attack = 5, defense = 1 })
  eq(Items.use(Items.potion(8), hero), 8, "potion reports amount healed")
  eq(hero.hp, 28, "potion restores hp")
  hero.inventory[1] = Items.potion(50)
  Items.useFromInventory(hero, 1)
  eq(hero.hp, hero.maxHp, "healing never exceeds maxHp")
  Items.equipWeapon(Items.weapon("sword", 4), hero)
  eq(hero.attack, 9, "weapon adds to attack")
  Items.equipWeapon(Items.weapon("axe", 7), hero)
  eq(hero.attack, 12, "swapping weapon adjusts attack correctly")
  eq(#hero.inventory, 1, "displaced weapon returns to inventory")
  Items.equipArmor(Items.armor("plate", 3), hero)
  eq(hero.defense, 4, "armor adds to defense")
  Items.equipRing(Items.ring("power", 2, 1), hero)
  eq(hero.attack, 14, "ring adds to attack")
  eq(hero.defense, 5, "ring adds to defense")
end

function tests.affixes()
  local blade = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[3])
  eq(blade.power, 3, "flaming affix raises weapon power")
  eq(blade.name, "flaming dagger", "affix prefixes the item name")
  eq(blade.affix.onHit.status, "burning", "flaming carries an on-hit rider")
  local a = Affixes.rollWeapon(Rng.new(5))
  local b = Affixes.rollWeapon(Rng.new(5))
  eq(a and a.key, b and b.key, "affix rolls are deterministic per seed")
end

function tests.identification()
  local a = Identify.new(Rng.new(7))
  local b = Identify.new(Rng.new(7))
  local healing = Items.potionOf("heal")
  eq(Identify.label(a, healing), Identify.label(b, healing), "appearances are deterministic per seed")
  ok(not contains(Identify.label(a, healing), "healing"), "an unidentified potion hides its true name")
  ok(contains(Identify.label(a, healing), "potion"), "an unidentified potion still reads as a potion")
  local c = Identify.new(Rng.new(8))
  local differs = Identify.label(a, healing) ~= Identify.label(c, healing)
    or Identify.label(a, Items.potionOf("poison")) ~= Identify.label(c, Items.potionOf("poison"))
  ok(differs, "a different world scrambles appearances differently")
  Identify.reveal(a, healing)
  eq(Identify.label(a, healing), "potion of healing", "identifying reveals the true name")
end

function tests.identifyGivesEveryPotionTypeItsOwnDistinctUnidentifiedLook()
  local state = Identify.new(Rng.new(3))
  local seen = {}
  for _, entry in ipairs(Items.potionTypes) do
    local label = Identify.label(state, Items.potionOf(entry.effect))
    ok(seen[label] == nil, "no two potion types share an unidentified look (collided on " .. label .. ")")
    seen[label] = true
  end
  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  eq(count, #Items.potionTypes, "every potion type, including confuse, got its own look")
end

function tests.weaponAffixOnHit()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.weapon = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[3])
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 30, 30
  game.level.entities = { orc }
  game:playerAttack(orc)
  eq(Status.has(orc, Status.BURNING), true, "a flaming weapon ignites what it hits")
end

function tests.itemsEquipPickSwapsAnyPriorPickBackIntoInventory()
  local entity = { inventory = {}, pick = Items.pick("worn pick", 3) }
  local fresh = Items.pick("fresh pick", 20)
  Items.equipPick(fresh, entity)
  eq(entity.pick, fresh, "the freshly equipped pick becomes the active one")
  eq(#entity.inventory, 1, "the previously equipped pick drops back into the inventory")
  eq(entity.inventory[1].name, "worn pick", "the displaced pick is the one that was equipped before")
end

return tests
