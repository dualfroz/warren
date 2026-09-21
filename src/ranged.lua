local Los = require("los")
local Items = require("items")
local Skills = require("skills")
local Artifacts = require("artifacts")
local Resistances = require("resistances")
local Proficiency = require("proficiency")
local Durability = require("durability")

local Ranged = {}

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
