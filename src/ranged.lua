-- Player ranged combat via an equipped bow and a stack of arrows carried in
-- the inventory. Unlike throwing, firing never costs the launcher itself -
-- only ammunition - so a bow stays equipped shot after shot as long as the
-- quiver holds out. A loosed arrow lands where the target stood either way,
-- recoverable exactly like a thrown weapon.

local Los = require("los")
local Items = require("items")
local Skills = require("skills")
local Artifacts = require("artifacts")
local Resistances = require("resistances")
local Proficiency = require("proficiency")
local Durability = require("durability")

local Ranged = {}

-- Inventory index of the first non-empty arrow stack, or nil if the quiver
-- is dry. Ammo of the same name merges into one stack on pickup, so in
-- practice there is at most one.
function Ranged.ammoIndex(entity)
  for i, item in ipairs(entity.inventory) do
    if item.kind == Items.AMMO and item.count > 0 then return i end
  end
  return nil
end

function Ranged.canReach(game, x1, y1, x2, y2, range)
  local dist = math.max(math.abs(x1 - x2), math.abs(y1 - y2))
  return dist <= range and Los.clear(game.level.map, x1, y1, x2, y2)
end

-- Looses one arrow from `shooter`'s equipped bow at `target`. Returns (true,
-- lines) if a shot went out - whatever it did on arrival - or (false, lines)
-- if it never left the string: no bow readied, no arrows, or no clear shot.
-- Damage comes from baseAttack rather than effectiveAttack so a melee
-- weapon's power does not also inflate every arrow; the bow's own power and
-- the target's armour are what separate a longbow from a sling. Mastery of
-- that specific bow (see proficiency.lua) still applies on top, since it is
-- read and recorded explicitly by the bow's own name rather than riding
-- effectiveAttack's blended total.
function Ranged.fire(game, shooter, target)
  local bow = shooter.bow
  if not bow then return false, { "you have no bow readied" } end
  if not target or not target:isAlive() then return false, { "no target" } end
  local ammoIdx = Ranged.ammoIndex(shooter)
  if not ammoIdx then return false, { "you have no arrows left" } end
  if not Ranged.canReach(game, shooter.x, shooter.y, target.x, target.y, bow.range) then
    return false, { "you have no clear shot" }
  end
  local ammo = shooter.inventory[ammoIdx]
  ammo.count = ammo.count - 1
  if ammo.count <= 0 then table.remove(shooter.inventory, ammoIdx) end
  local defense = math.max(0, target:effectiveDefense() - Artifacts.bowPierce(shooter))
  local dealt = shooter.baseAttack + Durability.effectivePower(bow) + Skills.rangedDamageBonus(shooter)
    + Proficiency.bonusFor(shooter, bow.name) - defense
  if dealt < 1 then dealt = 1 end
  dealt = Resistances.apply(target, dealt, Resistances.PHYSICAL)
  target.hp = target.hp - dealt
  local lines = { string.format("your %s hits %s for %d", ammo.name, target.name, dealt) }
  game.level.floorItems[#game.level.floorItems + 1] = {
    x = target.x, y = target.y, item = { kind = Items.AMMO, name = ammo.name, glyph = ammo.glyph, count = 1 },
  }
  local masteredKey, masteredBonus = Proficiency.onHitWith(shooter, bow.name)
  if masteredKey then
    lines[#lines + 1] = string.format("you grow more skilled with your %s (+%d attack)", masteredKey, masteredBonus)
  end
  local broke = Durability.wearBow(shooter)
  if broke then lines[#lines + 1] = broke end
  if not target:isAlive() then game:awardKill(target) end
  return true, lines
end

return Ranged
