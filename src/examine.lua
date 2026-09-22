local Items = require("items")
local Identify = require("identify")
local Curses = require("curses")
local Durability = require("durability")
local Runewords = require("runewords")
local Sets = require("sets")
local Shop = require("shop")
local Resistances = require("resistances")
local Factions = require("factions")
local Stealth = require("stealth")
local Disease = require("disease")
local Status = require("status")

local Examine = {}

local AWARENESS_LABEL = {
  [Stealth.DORMANT] = "asleep",
  [Stealth.SEARCHING] = "searching for you",
  [Stealth.HUNTING] = "hunting you",
}

local function bonusText(bonus)
  local parts = {}
  if bonus.attack and bonus.attack ~= 0 then parts[#parts + 1] = string.format("attack +%d", bonus.attack) end
  if bonus.defense and bonus.defense ~= 0 then parts[#parts + 1] = string.format("defense +%d", bonus.defense) end
  if bonus.regen and bonus.regen ~= 0 then parts[#parts + 1] = string.format("regen +%d", bonus.regen) end
  return table.concat(parts, ", ")
end

local NO_PRICE = { [Items.GOLD] = true, [Items.KEY] = true }

local function kindDetail(item)
  if item.kind == Items.WEAPON or item.kind == Items.ARMOR or item.kind == Items.BOW then
    local parts = { string.format("power %d", item.power) }
    if item.range then parts[#parts + 1] = "range " .. item.range end
    if item.damageType then parts[#parts + 1] = "deals " .. item.damageType .. " damage" end
    Durability.ensure(item)
    if Durability.isBroken(item) then
      parts[#parts + 1] = string.format("durability %d/%d (broken)", item.durability, item.maxDurability)
    else
      parts[#parts + 1] = string.format("durability %d/%d", item.durability, item.maxDurability)
    end
    if item.temper and item.temper > 0 then parts[#parts + 1] = string.format("tempered +%d", item.temper) end
    return table.concat(parts, ", ")
  elseif item.kind == Items.RING then
    return string.format("attack +%d, defense +%d", item.attack, item.defense)
  elseif item.kind == Items.FOOD then
    return string.format("restores %d nutrition", item.nutrition)
  elseif item.kind == Items.TOME then
    return "teaches the spell: " .. item.spell
  elseif item.kind == Items.AMMO then
    return string.format("%d in the stack", item.count)
  elseif item.kind == Items.CHARM then
    return "summons a companion: " .. item.companion
  elseif item.kind == Items.KIT then
    return "trap effect: " .. item.effect
  elseif item.kind == Items.CONTRACT then
    return "hires: " .. item.hireling
  elseif item.kind == Items.PICK then
    return string.format("%d %s left", item.uses, item.uses == 1 and "use" or "uses")
  elseif item.kind == Items.GEM then
    return string.format("tier %d, power %d", item.tier, item.power)
  end
  return nil
end

local function gearTraits(item, lines)
  if item.affix then
    local desc = item.affix.name
    if item.affix.onHit then
      desc = string.format("%s (on hit: %s, %d turns, potency %d)", desc,
        item.affix.onHit.status, item.affix.onHit.duration, item.affix.onHit.potency)
    end
    lines[#lines + 1] = "affix: " .. desc
  end

  if item.artifact then
    lines[#lines + 1] = "artifact power: " .. (item.unique or "passive bonus")
  end

  if item.set then
    local spec = Sets.byKey[item.set]
    lines[#lines + 1] = "set piece: " .. (spec and spec.name or item.set)
  end

  if item.socket then
    lines[#lines + 1] = string.format("socketed: tier %d %s gem", item.socket.tier, item.socket.element)
  end

  if item.runes and #item.runes > 0 then
    local word = Runewords.activeWord(item)
    if word then
      lines[#lines + 1] = string.format("runeword %s: %s", word.name, bonusText(word))
    else
      lines[#lines + 1] = "runes: " .. table.concat(item.runes, "-")
    end
  end

  if item.resist then
    local parts = {}
    for damageType, tier in pairs(item.resist) do
      parts[#parts + 1] = damageType .. " " .. tier
    end
    table.sort(parts)
    lines[#lines + 1] = "grants: " .. table.concat(parts, ", ")
  end

  if Curses.isCursed(item) and Curses.isRevealed(item) then
    lines[#lines + 1] = "cursed (" .. item.curseKind .. ")"
  end
end

function Examine.item(identifyState, item)
  local lines = { Curses.label(item, Identify.label(identifyState, item)) }
  local detail = kindDetail(item)
  if detail then lines[#lines + 1] = detail end
  gearTraits(item, lines)
  if not NO_PRICE[item.kind] then
    lines[#lines + 1] = "worth " .. Shop.priceOf(item) .. " gold"
  end
  return table.concat(lines, "; ")
end

function Examine.monster(player, monster)
  local lines = { monster.name }
  lines[#lines + 1] = string.format("hp %d/%d, attack %d, defense %d",
    monster.hp, monster.maxHp, monster:effectiveAttack(), monster:effectiveDefense())
  lines[#lines + 1] = "awareness: " .. (AWARENESS_LABEL[monster.awareness] or "hunting you")
  if monster.provoked then lines[#lines + 1] = "provoked" end

  if monster.faction then
    local tier = Factions.tier(Factions.reputationFor(player, monster.faction))
    lines[#lines + 1] = string.format("faction: %s (%s)", monster.faction, tier)
  end

  if monster.elite then
    lines[#lines + 1] = (monster.eliteTier or "elite") .. ": " .. table.concat(monster.eliteAffixes or {}, ", ")
  end

  if monster.isBoss then
    local tags = {}
    if monster.enraged then tags[#tags + 1] = "enraged" end
    if monster.desperate then tags[#tags + 1] = "desperate" end
    lines[#lines + 1] = #tags > 0 and ("boss, " .. table.concat(tags, ", ")) or "boss"
  end

  local resistParts = {}
  for _, damageType in ipairs(Resistances.TYPES) do
    local tier = Resistances.tierOf(monster, damageType)
    if tier ~= Resistances.NORMAL then
      resistParts[#resistParts + 1] = damageType .. " " .. tier
    end
  end
  if #resistParts > 0 then lines[#lines + 1] = "resistances: " .. table.concat(resistParts, ", ") end

  if monster.statuses and #monster.statuses > 0 then
    local parts = {}
    for _, active in ipairs(monster.statuses) do
      parts[#parts + 1] = string.format("%s (%d)", Status.noun(active.kind), active.duration)
    end
    lines[#lines + 1] = "afflicted: " .. Status.joinNaturally(parts)
  end

  if Disease.isInfected(monster) then
    local def = Disease.defs[monster.disease.key]
    lines[#lines + 1] = Disease.hasErupted(monster)
      and string.format("diseased: %s (stage %d)", def.name, monster.disease.stage)
      or string.format("diseased: %s (incubating)", def.name)
  end

  return table.concat(lines, "; ")
end

return Examine
