-- Text command parser and dispatcher for a human player, layered entirely on
-- top of the granular Game:<action> methods choosePlayerAction (ai.lua's own
-- autopilot) already drives - nothing here duplicates combat, targeting or
-- turn bookkeeping, it only translates a typed word into the same call the
-- autopilot would have made. Every other player-facing system in this engine
-- is a mechanic; this is the one module whose whole job is the interface
-- between a line of text and those mechanics, which is why it takes `game`
-- as a plain argument rather than requiring game.lua itself (that require
-- runs the other way, from game.lua's Game:manualStep).
--
-- Commands.apply(game, text) always returns (consumesTurn, message): a
-- movement/action word that actually did something returns true and leaves
-- Game:manualStep to spend the turn, exactly like choosePlayerAction would
-- have; an unrecognized word, a bad argument, or an action with nothing to
-- act on returns false and spends nothing, so a typo never costs a turn the
-- way a wasted keystroke would in any other roguelike. Purely informational
-- commands (inventory, look, status, help) always return false for the same
-- reason - reading your own inventory is free.

local Spells = require("spells")
local Identify = require("identify")
local Factions = require("factions")
local Examine = require("examine")
local Skills = require("skills")

local Commands = {}

local DIRS = {
  north = { 0, -1 }, n = { 0, -1 },
  south = { 0, 1 }, s = { 0, 1 },
  east = { 1, 0 }, e = { 1, 0 },
  west = { -1, 0 }, w = { -1, 0 },
  northeast = { 1, -1 }, ne = { 1, -1 },
  northwest = { -1, -1 }, nw = { -1, -1 },
  southeast = { 1, 1 }, se = { 1, 1 },
  southwest = { -1, 1 }, sw = { -1, 1 },
}

-- Splits `text` on whitespace into a lowercase verb plus its remaining
-- tokens as args. Returns nil for anything with no verb at all (an empty or
-- all-whitespace line), which Commands.apply treats the same as an unknown
-- command - no turn spent either way.
function Commands.parse(text)
  if type(text) ~= "string" then return nil end
  local tokens = {}
  for token in text:gmatch("%S+") do
    tokens[#tokens + 1] = token:lower()
  end
  if #tokens == 0 then return nil end
  local args = {}
  for i = 2, #tokens do args[#args + 1] = tokens[i] end
  return { verb = tokens[1], args = args }
end

-- A monster the player can actually see right now: alive, kind "monster"
-- (excludes the player's own companions/hirelings/thralls, which never
-- carry that kind - see game.lua's isPlayerAlly), and standing on a tile
-- game.visible already marks lit for the player this turn.
local function isVisibleHostile(game, entity)
  return entity.kind == "monster" and entity:isAlive()
    and game.visible[game.level.map:index(entity.x, entity.y)] == true
end

-- Up to `count` nearest visible hostiles, Chebyshev distance, ties broken by
-- ascending id - the same tie rule Game:nearestAlly and companions.lua's own
-- nearestHostile already use, so auto-targeting a ranged command picks
-- exactly the monster the autopilot would have picked in the same spot.
local function nearestHostiles(game, count)
  local player = game.player
  local results, excluded = {}, {}
  for _ = 1, count do
    local best, bestDist
    for _, entity in ipairs(game.level.entities) do
      if not excluded[entity] and isVisibleHostile(game, entity) then
        local dist = math.max(math.abs(entity.x - player.x), math.abs(entity.y - player.y))
        if not best or dist < bestDist or (dist == bestDist and entity.id < best.id) then
          best, bestDist = entity, dist
        end
      end
    end
    if not best then break end
    results[#results + 1] = best
    excluded[best] = true
  end
  return results
end

local function nearestHostile(game)
  return nearestHostiles(game, 1)[1]
end

-- Every visible hostile in game.level.entities's own order, unlike
-- nearestHostiles above which sorts by distance - this is the order
-- Handlers.look numbers its list in, so "examine monster <n>" always means
-- the same monster the player just saw look print at that number.
local function visibleHostilesInOrder(game)
  local list = {}
  for _, entity in ipairs(game.level.entities) do
    if isVisibleHostile(game, entity) then list[#list + 1] = entity end
  end
  return list
end

-- Resolves an optional trailing target number - the exact 1-based index
-- Handlers.look/examine already print next to each visible hostile - to an
-- entity, falling back to the nearest visible hostile (the old, only
-- behaviour) when the caller omitted it. Every targeted handler below stays
-- correct for a player who never bothers naming a target, while letting a
-- player who cares (a dangerous archer standing behind an expendable rat)
-- reach past the default without any change to game.lua's own range/line-of-
-- sight checks, which still reject an out-of-reach explicit target exactly
-- like they already reject a too-far auto-picked one.
-- Returns (target, explicit): explicit is true only when the caller actually
-- passed a token for the slot, so callers can tell "you named a target that
-- is not there" apart from "there is no target in sight at all" and keep
-- their own existing wording for the latter.
local function resolveTarget(game, indexText)
  if indexText == nil then return nearestHostile(game), false end
  local index = tonumber(indexText)
  return index and visibleHostilesInOrder(game)[index], true
end

-- Commands.parse lowercases every token before a handler ever sees it, which
-- is harmless for directions/spells/factions/slots (already all-lowercase
-- keys) but not for Skills.active/Skills.passive, whose keys are camelCase
-- (secondWind, poisonBlade, manaShield) - a player typing the skill's own
-- name would otherwise never match it. Maps a lowercased word back to its
-- real key by case-insensitive scan; returns the word unchanged when nothing
-- matches, so an actually unknown skill still reaches Skills.use/Skills.learn
-- and gets their own "no such skill" wording instead of being swallowed here.
local function resolveSkillKey(word)
  if not word then return word end
  for key in pairs(Skills.active) do
    if key:lower() == word then return key end
  end
  for key in pairs(Skills.passive) do
    if key:lower() == word then return key end
  end
  return word
end

local Handlers = {}

local function moveHandler(dx, dy)
  return function(game)
    if game:movePlayer(dx, dy) then return true, nil end
    return false, "you cannot go that way"
  end
end

for name, dir in pairs(DIRS) do
  Handlers[name] = moveHandler(dir[1], dir[2])
end

Handlers.attack = function(game, args)
  local dir = DIRS[args[1]]
  if not dir then return false, "attack which direction?" end
  if game:movePlayer(dir[1], dir[2]) then return true, nil end
  return false, "there is nothing to attack there"
end

Handlers.wait = function() return true, "you wait" end
Handlers.z = Handlers.wait
Handlers["."] = Handlers.wait

Handlers.pickup = function(game)
  game:pickupHere()
  return true, nil
end
Handlers.g = Handlers.pickup

-- Game:autoExplore already returns the exact (consumesTurn, message) shape
-- every handler here does - it just may have spent several turns getting
-- there instead of one, stopping itself the moment a hostile comes into
-- sight or the player takes damage rather than walking on regardless.
Handlers.explore = function(game)
  return game:autoExplore()
end

-- Game:restUntilHealed shares the same shape and the same "may spend several
-- turns before returning" behaviour as Game:autoExplore just above.
Handlers.rest = function(game)
  return game:restUntilHealed()
end

-- Game:travelTo shares that same "may spend several turns" shape too. "down"/
-- "up" are the level's own stairs (self.level.downX/Y, upX/Y) - always a
-- valid, already-walkable destination regardless of what the player has
-- explored yet, exactly like choosePlayerAction's own goal-seeking already
-- assumes; a raw x/y command is deliberately not offered since nothing in
-- this interface ever shows the player a raw coordinate to aim one at.
Handlers.travel = function(game, args)
  if args[1] == "down" then return game:travelTo(game.level.downX, game.level.downY) end
  if args[1] == "up" then return game:travelTo(game.level.upX, game.level.upY) end
  return false, "travel where? down or up"
end

-- Every handler below that takes an inventory index shares the same shape:
-- a missing or non-numeric first arg fails without spending a turn, exactly
-- like an unknown verb, rather than crashing into the underlying Game
-- method with a nil index.
local function indexArg(args)
  return tonumber(args[1])
end

Handlers.use = function(game, args)
  local index = indexArg(args)
  if not index then return false, "use what? give an inventory number" end
  if game:useItem(index) then return true, nil end
  return false, "you cannot use that"
end
Handlers.u = Handlers.use

Handlers.drop = function(game, args)
  local index = indexArg(args)
  if not index then return false, "drop what? give an inventory number" end
  if game:dropItem(index) then return true, nil end
  return false, "you have nothing there to drop"
end

Handlers.sell = function(game, args)
  local index = indexArg(args)
  if not index then return false, "sell what? give an inventory number" end
  if game:sellItem(index) then return true, nil end
  return false, "that cannot be sold here"
end

-- Trailing target number is always the argument slot right after whatever
-- an individual handler needed for itself (an inventory index, a spell/skill
-- key) - see resolveTarget above for exactly what "explicit" changes.
Handlers.throw = function(game, args)
  local index = indexArg(args)
  if not index then return false, "throw what? give an inventory number" end
  local target, explicit = resolveTarget(game, args[2])
  if not target then
    if explicit then return false, "no monster in sight at that number" end
    return false, "there is nothing in sight to throw at"
  end
  if game:throwAt(index, target) then return true, nil end
  return false, "you cannot throw that"
end

Handlers.capture = function(game, args)
  local index = indexArg(args)
  if not index then return false, "capture with what? give an inventory number" end
  local target, explicit = resolveTarget(game, args[2])
  if not target then
    if explicit then return false, "no monster in sight at that number" end
    return false, "there is nothing in sight to capture"
  end
  if game:captureAt(index, target) then return true, nil end
  return false, "the capture attempt fails"
end

Handlers.fire = function(game, args)
  local target, explicit = resolveTarget(game, args[1])
  if not target then
    if explicit then return false, "no monster in sight at that number" end
    return false, "there is nothing in sight to fire at"
  end
  if game:fireAt(target) then return true, nil end
  return false, "you cannot fire right now"
end

Handlers.cast = function(game, args)
  local key = args[1]
  if not key then return false, "cast what spell?" end
  local def = Spells.catalog[key]
  if not def then return false, "you know no spell by that name" end
  local target = nil
  if def.targeted then
    local explicit
    target, explicit = resolveTarget(game, args[2])
    if not target then
      if explicit then return false, "no monster in sight at that number" end
      return false, "there is nothing in sight to cast that at"
    end
  end
  if game:castSpell(key, target) then return true, nil end
  return false, "the spell fails"
end

-- multishot's two targets are named together or not at all: giving only one
-- explicit number is ambiguous about which of the (up to) two shots it picks
-- out, so that case falls back to the same auto-pick-both-nearest behaviour
-- as giving none, rather than guessing which slot the player meant.
Handlers.useskill = function(game, args)
  local key = resolveSkillKey(args[1])
  if not key then return false, "use which skill?" end
  local success
  if key == "cleave" then
    local target, explicit = resolveTarget(game, args[2])
    if not target and explicit then return false, "no monster in sight at that number" end
    success = game:useSkill(key, target)
  elseif key == "multishot" then
    if args[2] and args[3] then
      local list = visibleHostilesInOrder(game)
      local t1, t2 = list[tonumber(args[2]) or -1], list[tonumber(args[3]) or -1]
      if not t1 or not t2 then return false, "no monster in sight at that number" end
      success = game:useSkill(key, t1, t2)
    else
      local targets = nearestHostiles(game, 2)
      success = game:useSkill(key, targets[1], targets[2])
    end
  else
    success = game:useSkill(key)
  end
  if success then return true, nil end
  return false, "that skill fails"
end

-- Zero-argument actions that always resolve against whatever stands on the
-- player's own tile (a chest, a corpse, a captive, a node, a stairwell...),
-- the same way every one of these Game methods already looks itself up by
-- self.player.x/y rather than taking a target. `nothingMessage` only ever
-- surfaces when the underlying method itself failed silently (no log line
-- of its own) - most branches already explain themselves through game.log.
local function hereHandler(methodName, nothingMessage)
  return function(game)
    if game[methodName](game) then return true, nil end
    return false, nothingMessage
  end
end

Handlers.open = hereHandler("openChest", "there is nothing here to open")
Handlers.butcher = hereHandler("butcherCorpse", "there is nothing here to butcher")
Handlers.raise = hereHandler("raiseCorpse", "there is nothing here to raise")
Handlers.scavenge = hereHandler("scavengeCorpse", "there is nothing here to scavenge")
Handlers.harvest = hereHandler("harvestNode", "there is nothing here to harvest")
Handlers.ransom = hereHandler("ransomCaptive", "there is nothing here to ransom")
Handlers.sellcaptive = hereHandler("sellCaptive", "there is nothing here to sell")
Handlers.interrogate = hereHandler("interrogateCaptive", "there is nothing here to interrogate")
Handlers.descend = hereHandler("descend", "there are no stairs down here")
Handlers[">"] = Handlers.descend
Handlers.ascend = hereHandler("ascend", "there are no stairs up here")
Handlers["<"] = Handlers.ascend
Handlers.enterrift = hereHandler("enterRift", "there is no rift here to cross")
Handlers.exitrift = hereHandler("exitRift", "you are not standing across a rift")

-- Game:startHorde is a deliberate, one-way trial (see its own header: the
-- dungeon floor left behind is simply abandoned, there is no exit back) that
-- always succeeds and, unlike every hereHandler above, carries no location
-- requirement of its own - so this guards against the one real footgun a
-- typed command adds that the method itself does not: retyping "horde"
-- mid-run would otherwise silently discard the current wave and its
-- progress by building a brand new arena on top of it.
Handlers.horde = function(game)
  if game.horde then return false, "you are already fighting in the arena" end
  game:startHorde()
  return true, nil
end

Handlers.pray = function(game)
  local shrine = game.level:shrineAt(game.player.x, game.player.y)
  if not shrine then return false, "there is no shrine here" end
  if game:prayAt(shrine) then return true, nil end
  return false, "your prayer goes unanswered"
end

Handlers.quest = function(game)
  local board = game.level:questBoardAt(game.player.x, game.player.y)
  if not board then return false, "there is no quest board here" end
  if game:tryAcceptQuest(board) then return true, nil end
  return false, "you cannot take up that bounty"
end

-- Every faction key factions.lua defines, spelled out here (rather than
-- discovered from the module at runtime) purely so a bad argument's error
-- message can list them by name; the set itself is built from the same
-- constants Game:appeaseFaction already trusts, so a typo can never buy
-- standing with a faction that does not exist.
local FACTION_NAMES = {
  Factions.MERCHANT, Factions.GOBLINOID, Factions.VERMIN, Factions.ORCISH,
  Factions.UNDEAD, Factions.BEAST, Factions.CULT, Factions.DRAKE, Factions.BANDIT,
}
local FACTION_SET = {}
for _, name in ipairs(FACTION_NAMES) do FACTION_SET[name] = true end

Handlers.appease = function(game, args)
  local faction = args[1]
  if not faction or not FACTION_SET[faction] then
    return false, "appease which faction? " .. table.concat(FACTION_NAMES, ", ")
  end
  if game:appeaseFaction(faction) then return true, nil end
  return false, nil
end

Handlers.dig = function(game, args)
  local dir = DIRS[args[1]]
  if not dir then return false, "dig which direction?" end
  if game:dig(dir[1], dir[2]) then return true, nil end
  return false, "you cannot dig there"
end

-- Disarms a detected-but-unsprung trap one step away in `dir` - the same
-- Chebyshev-1 reach Disarm.sweep already uses to notice it in the first
-- place (see Game:endPlayerTurn's "you notice a hidden trap nearby"). The
-- validity check below duplicates Game:disarmTrap's own guard on purpose:
-- unlike every other handler here, a disarm attempt against a real trap
-- must still spend the turn even when Disarm.attempt fails and springs it,
-- but Game:disarmTrap's own boolean return conflates that spring with "no
-- trap here" into the same false - so this handler tells the two apart
-- itself instead of trusting the method's return value for turn cost.
Handlers.disarm = function(game, args)
  local dir = DIRS[args[1]]
  if not dir then return false, "disarm which direction?" end
  local trap = game.level:trapAt(game.player.x + dir[1], game.player.y + dir[2])
  if not trap or not trap.detected or trap.revealed then
    return false, "there is nothing here you have noticed to disarm"
  end
  game:disarmTrap(trap)
  return true, nil
end

-- Crafting/economy verbs (game.lua's forgeGem/mergeGemsAt/socketItem/
-- socketRune/temperItem/enchantItem/disenchantItem/repairEquipped/
-- stealFromShop/dismissHireling/learnSkill/brewAt), the other half of the
-- API choosePlayerAction can already reach that a typed session could not
-- until now. Every one of these Game methods already logs its own success
-- or failure reason, so a handler only needs its own message for an
-- argument so malformed the underlying method can never even be called.

-- Shared by socket/socketrune/temper/enchant/disenchant: their `target`
-- resolves through Game:resolveGear exactly like this, either the literal
-- word for currently equipped gear or an inventory slot number for
-- anything else (a spare ring, an unequipped bow).
local function targetArg(token)
  if token == "weapon" or token == "armor" then return token end
  return tonumber(token)
end

Handlers.forge = function(game, args)
  local element = args[1]
  if not element then return false, "forge which element? fire, frost, shock or venom" end
  if game:forgeGem(element) then return true, nil end
  return false, nil
end

Handlers.merge = function(game, args)
  local a, b = tonumber(args[1]), tonumber(args[2])
  if not a or not b then return false, "merge which two gems? give two inventory numbers" end
  if game:mergeGemsAt(a, b) then return true, nil end
  return false, "those cannot be merged"
end

Handlers.socket = function(game, args)
  local target, gemIndex = targetArg(args[1]), tonumber(args[2])
  if not target or not gemIndex then
    return false, "socket what into what? give a target (weapon/armor/item number) and a gem number"
  end
  if game:socketItem(target, gemIndex) then return true, nil end
  return false, "that cannot be socketed"
end

Handlers.socketrune = function(game, args)
  local target, runeIndex = targetArg(args[1]), tonumber(args[2])
  if not target or not runeIndex then
    return false, "socket which rune into what? give a target (weapon/armor/item number) and a rune number"
  end
  if game:socketRune(target, runeIndex) then return true, nil end
  return false, "that cannot be socketed"
end

Handlers.temper = function(game, args)
  local target = targetArg(args[1])
  if not target then return false, "temper what? weapon, armor or an item number" end
  if game:temperItem(target) then return true, nil end
  return false, "that cannot be tempered"
end

Handlers.enchant = function(game, args)
  local target, affixKey = targetArg(args[1]), args[2]
  if not target or not affixKey then
    return false, "enchant what with what? give a target (weapon/armor/item number) and an affix name"
  end
  if game:enchantItem(target, affixKey) then return true, nil end
  return false, "that cannot be enchanted"
end

Handlers.disenchant = function(game, args)
  local target = targetArg(args[1])
  if not target then return false, "disenchant what? weapon, armor or an item number" end
  if game:disenchantItem(target) then return true, nil end
  return false, "that cannot be disenchanted"
end

Handlers.repair = function(game, args)
  local slot = args[1]
  if slot ~= "weapon" and slot ~= "armor" and slot ~= "bow" then
    return false, "repair what? weapon, armor or bow"
  end
  if game:repairEquipped(slot) then return true, nil end
  return false, nil
end

-- Steals whichever warded ware sits underfoot, the same tile Game:pickupHere
-- already resolves against - unlike Game:stealFromShop's own raw floorItems
-- index, a typed command can only ever mean "the ware I am standing on".
local function groundIndexHere(game)
  for i, ground in ipairs(game.level.floorItems) do
    if ground.x == game.player.x and ground.y == game.player.y then return i, ground end
  end
  return nil
end

Handlers.steal = function(game)
  local index = groundIndexHere(game)
  if index and game:stealFromShop(index) then return true, nil end
  return false, "there is nothing here worth stealing"
end

Handlers.dismiss = function(game)
  if game:dismissHireling() then return true, nil end
  return false, nil
end

Handlers.learn = function(game, args)
  local key = resolveSkillKey(args[1])
  if not key then return false, "learn which skill?" end
  game:learnSkill(key)
  return false, nil
end

-- Duplicates Game:brewAt's own precondition checks (cauldron underfoot, two
-- distinct herb items) before ever calling it, the same shape as disarm
-- above and for the same reason: past those preconditions, brewing always
-- spends both herbs, whether the pairing brews a potion or curdles into gas
-- (see Alchemy.brew), so this handler must not read a curdle's own `false`
-- as "nothing happened" and hand the player a free turn back.
Handlers.brew = function(game, args)
  local a, b = tonumber(args[1]), tonumber(args[2])
  if not a or not b then return false, "brew which two herbs? give two inventory numbers" end
  if not game.level:cauldronAt(game.player.x, game.player.y) then
    return false, "there is no cauldron here"
  end
  if a == b then return false, "brew two different herbs, not the same one twice" end
  local herbA, herbB = game.player.inventory[a], game.player.inventory[b]
  if not herbA or not herbB or herbA.kind ~= "herb" or herbB.kind ~= "herb" then
    return false, "you need two herbs to brew"
  end
  game:brewAt(a, b)
  return true, nil
end

-- Purely informational commands. Every one of these returns false (spends no
-- turn) and carries its whole answer in the message, which is the one place
-- a caller should print something the game log itself would never contain.
Handlers.inventory = function(game)
  if #game.player.inventory == 0 then return false, "you are carrying nothing" end
  local lines = {}
  for i, item in ipairs(game.player.inventory) do
    lines[#lines + 1] = string.format("  %d) %s", i, Identify.label(game.identify, item))
  end
  return false, table.concat(lines, "\n")
end
Handlers.i = Handlers.inventory

Handlers.status = function(game)
  local p = game.player
  return false, string.format(
    "hp %d/%d  mana %d/%d  gold %d  essence %d  level %d  xp %d/%d  depth %d  turn %d",
    p.hp, p.maxHp, p.mana or 0, p.maxMana or 0, p.gold, p.essence,
    p.level, p.xp, p.xpNext, game.depth, game.turn)
end

Handlers.look = function(game)
  local targets = visibleHostilesInOrder(game)
  if #targets == 0 then return false, "you see no threats nearby" end
  local names = {}
  for i, entity in ipairs(targets) do
    names[#names + 1] = string.format("%d) %s", i, entity.name)
  end
  return false, "in sight: " .. table.concat(names, ", ")
end
Handlers.l = Handlers.look

-- Detail views (examine.lua): `examine <n>` inspects inventory item n, the
-- same index use/drop/sell already key off; `examine monster <n>` inspects
-- the nth entry of the very list Handlers.look just numbered. Both branches
-- are free, like every other informational command here.
Handlers.examine = function(game, args)
  if args[1] == "monster" then
    local index = tonumber(args[2])
    if not index then return false, "examine which monster? give the number look showed you" end
    local target = visibleHostilesInOrder(game)[index]
    if not target then return false, "no monster in sight at that number" end
    return false, Examine.monster(game.player, target)
  end
  local index = indexArg(args)
  if not index then return false, "examine what? give an inventory number, or 'monster <n>'" end
  local item = game.player.inventory[index]
  if not item then return false, "you are not carrying anything at that number" end
  return false, Examine.item(game.identify, item)
end
Handlers.x = Handlers.examine

Handlers.help = function()
  return false, "commands: north/south/east/west/ne/nw/se/sw (or n/s/e/w/...), attack <dir>, " ..
    "wait, pickup, explore, rest, travel down/up, inventory, use <n>, drop <n>, sell <n>, throw <n> [target], " ..
    "fire [target], capture <n> [target], cast <spell> [target], useskill <skill> [target], " ..
    "open, pray, quest, appease <faction>, butcher, raise, " ..
    "scavenge, harvest, ransom, sellcaptive, interrogate, dig <dir>, disarm <dir>, " ..
    "descend, ascend, enterrift, exitrift, horde, " ..
    "steal, dismiss, learn <skill>, forge <element>, merge <a> <b>, brew <a> <b>, " ..
    "socket <target> <gem>, socketrune <target> <rune>, temper <target>, " ..
    "enchant <target> <affix>, disenchant <target>, repair <slot>, " ..
    "examine <n>, examine monster <n>, look, status, help " ..
    "([target] is the number look/examine gives a monster; omit it to auto-target the nearest one)"
end

-- Parses `text` and dispatches it against `game`. Returns (consumesTurn,
-- message): Game:manualStep spends the player's turn iff the first value is
-- true, and either surfaces `message` itself (a failure reason, or an
-- informational answer) or leaves the game log to speak for a successful
-- action, exactly the way every Game:<action> method already logs its own
-- outcome.
function Commands.apply(game, text)
  local parsed = Commands.parse(text)
  if not parsed then return false, "say something" end
  local handler = Handlers[parsed.verb]
  if not handler then return false, "unknown command: " .. parsed.verb end
  return handler(game, parsed.args)
end

return Commands
