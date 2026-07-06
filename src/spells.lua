-- Mana-fuelled spellbook. Spells are learned permanently from tomes (see
-- Items.TOME) and cast by spending mana from a pool that regenerates each
-- player turn. Targeted spells additionally need line of sight and range,
-- checked here before any mana is spent so a bad cast is free. Damage and
-- teleport spells reach into the game the same way potion/scroll effects do.

local Los = require("los")
local Status = require("status")
local Skills = require("skills")
local Resistances = require("resistances")
local Conductivity = require("conductivity")
local Polymorph = require("polymorph")
local Disease = require("disease")

local Spells = {}

local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Every walkable, unoccupied cell within `radius` orthogonal steps of the
-- caster, excluding the caster's own cell. Used by blink so a short-range
-- teleport only ever lands somewhere the caster could in principle walk to.
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
  -- Mirrors effects.lua's "cure" potion handler (both lift disease and every
  -- Status.HOSTILE debuff) but reachable without needing the item on hand -
  -- until now the only way to shed poison/burning/stun/slow/weaken/discord/
  -- confuse/blind was to survive until they expired on their own.
  cleanse = {
    name = "cleansing ward", cost = 5, targeted = false,
    cast = function(_, caster)
      local diseaseCured = Disease.cure(caster)
      local lifted = Status.cureHostile(caster)
      if diseaseCured and #lifted > 0 then
        return { string.format("your affliction lifts, and the %s fades", table.concat(lifted, ", ")) }
      elseif diseaseCured then
        return { "your affliction lifts" }
      elseif #lifted > 0 then
        return { string.format("the %s fades", table.concat(lifted, ", ")) }
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
  -- Fractures the target's mind for a few turns: while it lasts, the
  -- target attacks whatever creature stands nearest it - ally or foe,
  -- including the caster's own companion/hireling/thrall if one strays
  -- close enough - instead of chasing the caster (see infighting.lua). No
  -- direct damage of its own; the value is entirely in redirecting a
  -- threat, or turning a cluster of monsters against itself.
  discord = {
    name = "discord", cost = 5, targeted = true, range = 6,
    cast = function(_, _, target)
      Status.apply(target, Status.DISCORD, 8, 1)
      return { string.format("%s's mind fractures with discord", target.name) }
    end,
  },
  -- Scrambles the target's own sense of direction for a few turns (see
  -- status.lua's Status.CONFUSE, and its mirror in Game:movePlayer/Ai.act) -
  -- a lucky roll can send a dangerous chaser stumbling into a wall, a lava
  -- pool, or one of its own allies instead of at the caster.
  confuse = {
    name = "confusing hex", cost = 4, targeted = true, range = 5,
    cast = function(_, _, target)
      Status.apply(target, Status.CONFUSE, 6, 1)
      return { string.format("%s's senses reel with confusion", target.name) }
    end,
  },
  -- Snuffs the target's sight down to melee range for a few turns (see
  -- status.lua's Status.BLIND, folded into Game:effectiveRadius/canSeePlayer)
  -- - unlike confuse, which garbles the target's own movement, a blinded
  -- monster keeps walking straight at its last known heading and simply
  -- stops noticing anything past arm's reach, useful against archers and
  -- casters whose whole threat depends on seeing the caster from a distance.
  blind = {
    name = "veil of shadow", cost = 4, targeted = true, range = 5,
    cast = function(_, _, target)
      Status.apply(target, Status.BLIND, 6, 1)
      return { string.format("a veil of shadow falls over %s's eyes", target.name) }
    end,
  },
  -- Saps the target's fighting strength for a few turns (see status.lua's
  -- Status.WEAKEN). Until now WEAKEN only ever flowed toward the player - a
  -- shaman's ranged curse, a cursed shrine's backfired prayer - with no way
  -- for the player to return the favor against a monster; this spell is
  -- that missing direction, shaped exactly like confuse/blind above (no
  -- direct damage, just a debuff riding on Status.apply).
  weaken = {
    name = "withering hex", cost = 4, targeted = true, range = 5,
    cast = function(_, _, target)
      Status.apply(target, Status.WEAKEN, 6, 1)
      return { string.format("%s's strength withers", target.name) }
    end,
  },
  -- Rewrites the target's body outright rather than damaging or debuffing
  -- it (see polymorph.lua). A pricier cast than any other targeted spell
  -- here, since a lucky roll can turn a real threat into something the
  -- caster can safely ignore - and an unlucky one can just as easily make
  -- it worse, the same double-edged risk a shrine's backfired prayer carries.
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
  -- A self-buff shaped exactly like shield, but see status.lua's
  -- Status.LEVITATE for the payoff: for as long as it lasts, the caster
  -- drifts clear of lava, a chasm's drop, an ice tile's slide, and any
  -- ground-pressure trap (Game:checkTerrainFor/checkTrapFor) instead of
  -- soaking a hit.
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

-- Attempts to cast `key` on behalf of `caster`. Returns (true, lines) on a
-- successful cast, or (false, lines) with an explanatory line and no state
-- changed - no mana spent, no cooldown, nothing - on failure.
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
