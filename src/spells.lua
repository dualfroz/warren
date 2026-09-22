local Los = require("los")
local Status = require("status")
local Skills = require("skills")
local Resistances = require("resistances")
local Conductivity = require("conductivity")
local Polymorph = require("polymorph")
local Disease = require("disease")

local Spells = {}

local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function reachableWithin(game, caster, radius)
  local map = game.level.map
  local start = map:index(caster.x, caster.y)
  local dist = { [start] = 0 }
  local queue = { { caster.x, caster.y, start } }
  local head = 1
  local cells = {}
  while head <= #queue do
    local cur = queue[head]
    head = head + 1
    local cx, cy, idx = cur[1], cur[2], cur[3]
    local d = dist[idx]
    if idx ~= start then cells[#cells + 1] = { x = cx, y = cy } end
    if d < radius then
      for _, dir in ipairs(DIRS4) do
        local nx, ny = cx + dir[1], cy + dir[2]
        if map:inBounds(nx, ny) and map:isWalkable(nx, ny) then
          local nIdx = map:index(nx, ny)
          if not dist[nIdx] then
            dist[nIdx] = d + 1
            queue[#queue + 1] = { nx, ny, nIdx }
          end
        end
      end
    end
  end
  return cells
end

Spells.catalog = {
  missile = {
    name = "magic missile", cost = 3, targeted = true, range = 6,
    cast = function(game, caster, target)
      local raw = math.floor((6 + (caster.level or 1)) * Skills.spellDamageMultiplier(caster))
      local dmg = Resistances.apply(target, raw, Resistances.ARCANE)
      target.hp = target.hp - dmg
      if dmg <= 0 then
        game.log:add(string.format("a bolt of force washes over %s harmlessly", target.name))
      else
        game.log:add(string.format("a bolt of force hits %s for %d", target.name, dmg))
      end
      if not target:isAlive() then game:awardKill(target) end
      return {}
    end,
  },
  heal = {
    name = "minor heal", cost = 5, targeted = false,
    cast = function(_, caster)
      local amount = 10 + (caster.level or 1) * 2
      local before = caster.hp
      caster.hp = math.min(caster.maxHp, caster.hp + amount)
      return { string.format("you mend for %d", caster.hp - before) }
    end,
  },
  cleanse = {
    name = "cleansing ward", cost = 5, targeted = false,
    cast = function(_, caster)
      local diseaseCured = Disease.cure(caster)
      local lifted = Status.cureHostile(caster)
      local liftedList = #lifted > 0 and Status.describe(lifted)
      local fades = #lifted == 1 and "fades" or "fade"
      if diseaseCured and liftedList then
        return { string.format("your affliction lifts, and the %s %s", liftedList, fades) }
      elseif diseaseCured then
        return { "your affliction lifts" }
      elseif liftedList then
        return { string.format("the %s %s", liftedList, fades) }
      end
      return { "you feel a faint tingle, but had nothing to cleanse" }
    end,
  },
  shield = {
    name = "arcane shield", cost = 4, targeted = false,
    cast = function(_, caster)
      Status.apply(caster, Status.SHIELD, 15, 1)
      return { "a shimmering ward surrounds you" }
    end,
  },
  shock = {
    name = "shock bolt", cost = 4, targeted = true, range = 5,
    cast = function(game, caster, target)
      local raw = math.floor((5 + (caster.level or 1)) * Skills.spellDamageMultiplier(caster))
      local dmg = Conductivity.applyLightning(target, raw)
      target.hp = target.hp - dmg
      if dmg <= 0 then
        game.log:add(string.format("a crackle of lightning washes over %s harmlessly", target.name))
      elseif Conductivity.isWet(target) then
        game.log:add(string.format("lightning arcs through the water clinging to %s for %d", target.name, dmg))
      else
        game.log:add(string.format("a bolt of lightning strikes %s for %d", target.name, dmg))
      end
      if not target:isAlive() then game:awardKill(target) end
      return {}
    end,
  },
  discord = {
    name = "discord", cost = 5, targeted = true, range = 6,
    cast = function(_, _, target)
      Status.apply(target, Status.DISCORD, 8, 1)
      return { string.format("%s's mind fractures with discord", target.name) }
    end,
  },
  confuse = {
    name = "confusing hex", cost = 4, targeted = true, range = 5,
    cast = function(_, _, target)
      Status.apply(target, Status.CONFUSE, 6, 1)
      return { string.format("%s's senses reel with confusion", target.name) }
    end,
  },
  blind = {
    name = "veil of shadow", cost = 4, targeted = true, range = 5,
    cast = function(_, _, target)
      Status.apply(target, Status.BLIND, 6, 1)
      return { string.format("a veil of shadow falls over %s's eyes", target.name) }
    end,
  },
  weaken = {
    name = "withering hex", cost = 4, targeted = true, range = 5,
    cast = function(_, _, target)
      Status.apply(target, Status.WEAKEN, 6, 1)
      return { string.format("%s's strength withers", target.name) }
    end,
  },
  polymorph = {
    name = "polymorph", cost = 9, targeted = true, range = 5,
    cast = function(game, _, target)
      local oldName = target.name
      local pool = Polymorph.pool(game.depth)
      local spec = Polymorph.transform(target, game.rng, pool)
      if not spec then
        return { string.format("the magic washes over %s, changing nothing", oldName) }
      end
      return { string.format("%s convulses and reforms into a %s", oldName, spec.name) }
    end,
  },
  levitate = {
    name = "levitation", cost = 5, targeted = false,
    cast = function(_, caster)
      Status.apply(caster, Status.LEVITATE, 20, 1)
      return { "you rise off the ground" }
    end,
  },
  blink = {
    name = "blink", cost = 6, targeted = false,
    cast = function(game, caster)
      local free = {}
      for _, cell in ipairs(reachableWithin(game, caster, 5)) do
        if not game.level:entityAt(cell.x, cell.y) then
          free[#free + 1] = cell
        end
      end
      if #free == 0 then return { "there is nowhere to blink" } end
      local pick = free[game.rng:range(1, #free)]
      caster.x, caster.y = pick.x, pick.y
      return { "you blink through space" }
    end,
  },
}

function Spells.knows(caster, key)
  for _, known in ipairs(caster.spellsKnown) do
    if known == key then return true end
  end
  return false
end

function Spells.learn(caster, key)
  if not Spells.catalog[key] then return false end
  if Spells.knows(caster, key) then return false end
  caster.spellsKnown[#caster.spellsKnown + 1] = key
  return true
end

function Spells.cast(game, caster, key, target)
  local spell = Spells.catalog[key]
  if not spell then return false, { "you don't know that spell" } end
  if not Spells.knows(caster, key) then return false, { "you haven't learned that spell" } end
  if caster.mana < spell.cost then return false, { "not enough mana" } end
  if spell.targeted then
    if not target or not target:isAlive() then return false, { "no target" } end
    local dist = math.max(math.abs(target.x - caster.x), math.abs(target.y - caster.y))
    if dist > spell.range then return false, { "out of range" } end
    if not Los.clear(game.level.map, caster.x, caster.y, target.x, target.y) then
      return false, { "no clear shot" }
    end
  end
  caster.mana = caster.mana - spell.cost
  return true, spell.cast(game, caster, target) or {}
end

return Spells
