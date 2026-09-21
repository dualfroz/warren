local Los = require("los")
local Items = require("items")
local Resistances = require("resistances")

local Skills = {}

Skills.active = {
  cleave      = { name = "cleave",       class = "fighter", reqLevel = 1, cooldown = 3 },
  secondWind  = { name = "second wind",  class = "fighter", reqLevel = 3, cooldown = 12 },
  poisonBlade = { name = "poison blade", class = "rogue",   reqLevel = 5, cooldown = 6 },
  meditate    = { name = "meditate",     class = "mage",    reqLevel = 3, cooldown = 0 },
  multishot   = { name = "multishot",    class = "ranger",  reqLevel = 1, cooldown = 5 },
}

Skills.passive = {
  berserk    = { name = "berserk",    class = "fighter", reqLevel = 5 },
  backstab   = { name = "backstab",   class = "rogue",   reqLevel = 1 },
  evasion    = { name = "evasion",    class = "rogue",   reqLevel = 3 },
  overload   = { name = "overload",   class = "mage",    reqLevel = 1 },
  manaShield = { name = "mana shield", class = "mage",   reqLevel = 5 },
  camouflage = { name = "camouflage", class = "ranger",  reqLevel = 3 },
  trueshot   = { name = "trueshot",   class = "ranger",  reqLevel = 5 },
}

local function defOf(key)
  return Skills.active[key] or Skills.passive[key]
end

function Skills.forClass(classKey)
  local list = {}
  for key, def in pairs(Skills.active) do
    if def.class == classKey then list[#list + 1] = key end
  end
  for key, def in pairs(Skills.passive) do
    if def.class == classKey then list[#list + 1] = key end
  end
  table.sort(list)
  return list
end

function Skills.has(entity, key)
  return entity.skills ~= nil and entity.skills[key] == true
end

function Skills.learn(player, key)
  local def = defOf(key)
  if not def then return false, "there is no such skill" end
  if player.class ~= def.class then return false, "that skill is not part of your training" end
  if player.level < def.reqLevel then return false, "you are not experienced enough for that yet" end
  if Skills.has(player, key) then return false, "you already know that" end
  if (player.skillPoints or 0) <= 0 then return false, "you have no skill points to spend" end
  player.skillPoints = player.skillPoints - 1
  player.skills[key] = true
  return true, "you learn " .. def.name
end

function Skills.tickCooldowns(player)
  for key, turns in pairs(player.skillCooldowns) do
    if turns > 0 then player.skillCooldowns[key] = turns - 1 end
  end
end

function Skills.meleeDamageMultiplier(attacker, defender)
  if Skills.has(attacker, "backstab") and defender.hp == defender.maxHp then
    return 2
  end
  return 1
end

function Skills.evades(game, defender)
  if not Skills.has(defender, "evasion") then return false end
  return game.rng:chance(1, 4)
end

function Skills.attackBonus(entity)
  if entity.skills and entity.skills.berserk and entity.hp <= entity.maxHp * 0.34 then
    return 4
  end
  return 0
end

function Skills.defenseBonus(entity)
  if entity.skills and entity.skills.manaShield and (entity.mana or 0) >= 5 then
    return 3
  end
  return 0
end

function Skills.spellDamageMultiplier(caster)
  if Skills.has(caster, "overload") then return 1.25 end
  return 1
end

function Skills.rangedDamageBonus(entity)
  if Skills.has(entity, "trueshot") then return 3 end
  return 0
end

function Skills.detectionPenalty(player, dark)
  if dark and Skills.has(player, "camouflage") then return 3 end
  return 0
end

local EIGHT_DIRS = {
  { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
  { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

local function statAttack(entity)
  return entity.effectiveAttack and entity:effectiveAttack() or entity.attack
end

local function statDefense(entity)
  return entity.effectiveDefense and entity:effectiveDefense() or entity.defense
end

function Skills.useCleave(game, target)
  if not target or not target:isAlive() then return false, { "there is nothing there to cleave" } end
  local player = game.player
  local dist = math.max(math.abs(target.x - player.x), math.abs(target.y - player.y))
  if dist > 1 then return false, { "cleave only reaches an adjacent foe" } end
  player.skillCooldowns.cleave = Skills.active.cleave.cooldown
  local lines = {}
  game:playerAttack(target)
  local damageType = (player.weapon and player.weapon.damageType) or Resistances.PHYSICAL
  for _, dir in ipairs(EIGHT_DIRS) do
    local other = game.level:entityAt(player.x + dir[1], player.y + dir[2])
    if other and other ~= target and other:isAlive() then
      local dealt = math.floor((statAttack(player) - statDefense(other)) * 0.5)
      if dealt < 1 then dealt = 1 end
      dealt = Resistances.apply(other, dealt, damageType)
      other.hp = other.hp - dealt
      lines[#lines + 1] = string.format("your cleave catches %s for %d", other.name, dealt)
      if not other:isAlive() then game:awardKill(other) end
    end
  end
  return true, lines
end

function Skills.useSecondWind(game)
  local player = game.player
  player.skillCooldowns.secondWind = Skills.active.secondWind.cooldown
  local amount = math.floor(player.maxHp * 0.3)
  local before = player.hp
  player.hp = math.min(player.maxHp, player.hp + amount)
  return true, { string.format("you catch your breath and recover %d", player.hp - before) }
end

function Skills.usePoisonBlade(game)
  local player = game.player
  player.skillCooldowns.poisonBlade = Skills.active.poisonBlade.cooldown
  player.pendingPoisonBlade = true
  return true, { "your blade drips with venom" }
end

function Skills.consumePoisonBlade(player)
  if player.pendingPoisonBlade then
    player.pendingPoisonBlade = nil
    return true
  end
  return false
end

function Skills.useMeditate(game)
  local player = game.player
  local before = player.mana
  player.mana = math.min(player.maxMana, player.mana + 6)
  return true, { string.format("you meditate and recover %d mana", player.mana - before) }
end

local function firstAmmoIndex(entity)
  for i, item in ipairs(entity.inventory) do
    if item.kind == Items.AMMO and item.count > 0 then return i end
  end
  return nil
end

local function canReach(game, x1, y1, x2, y2, range)
  local dist = math.max(math.abs(x1 - x2), math.abs(y1 - y2))
  return dist <= range and Los.clear(game.level.map, x1, y1, x2, y2)
end

function Skills.useMultishot(game, t1, t2)
  local shooter = game.player
  local bow = shooter.bow
  if not bow then return false, { "you have no bow readied" } end
  local ammoIdx = firstAmmoIndex(shooter)
  if not ammoIdx then return false, { "you have no arrows left" } end
  local targets = {}
  for _, t in ipairs({ t1, t2 }) do
    if t and t:isAlive() and canReach(game, shooter.x, shooter.y, t.x, t.y, bow.range) then
      targets[#targets + 1] = t
    end
  end
  if #targets == 0 then return false, { "no target in range" } end
  shooter.skillCooldowns.multishot = Skills.active.multishot.cooldown
  local ammo = shooter.inventory[ammoIdx]
  ammo.count = ammo.count - 1
  if ammo.count <= 0 then table.remove(shooter.inventory, ammoIdx) end
  local lines = {}
  for i, t in ipairs(targets) do
    local share = (i == 1) and 1 or 0.5
    local dealt = math.floor((shooter.baseAttack + bow.power - t:effectiveDefense()) * share)
    if dealt < 1 then dealt = 1 end
    dealt = Resistances.apply(t, dealt, Resistances.PHYSICAL)
    t.hp = t.hp - dealt
    lines[#lines + 1] = string.format("your arrow splits and strikes %s for %d", t.name, dealt)
    if not t:isAlive() then game:awardKill(t) end
  end
  return true, lines
end

function Skills.use(game, key, ...)
  local def = Skills.active[key]
  if not def then return false, { "you have no such skill to use" } end
  local player = game.player
  if not Skills.has(player, key) then return false, { "you haven't learned that skill" } end
  if (player.skillCooldowns[key] or 0) > 0 then return false, { "that skill is not ready yet" } end
  if key == "cleave" then return Skills.useCleave(game, ...)
  elseif key == "secondWind" then return Skills.useSecondWind(game)
  elseif key == "poisonBlade" then return Skills.usePoisonBlade(game)
  elseif key == "meditate" then return Skills.useMeditate(game)
  elseif key == "multishot" then return Skills.useMultishot(game, ...)
  end
  return false, { "that skill does nothing yet" }
end

return Skills
