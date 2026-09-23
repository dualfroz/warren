local helpers = require("helpers")
local Items = require("items")
local Monsters = require("monsters")
local Game = require("game")
local Render = require("render")
local Atmosphere = require("atmosphere")
local Stealth = require("stealth")
local Sets = require("sets")
local Curses = require("curses")
local Events = require("events")
local Proficiency = require("proficiency")
local Disease = require("disease")
local Tiles = require("tiles")
local Nodes = require("nodes")
local Graves = require("graves")
local Bosses = require("bosses")
local Companions = require("companions")
local Mercenaries = require("mercenaries")
local Mimics = require("mimics")
local Reanimation = require("reanimation")
local Status = require("status")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame
local glyphAt = helpers.glyphAt

local tests = helpers.suite()

function tests.renderPanelShowsCarriedLoad()
  local game = Game.new(1)
  local panel = Render.panel(game)
  ok(contains(panel, "load light ("), "the status panel reports the carrier's current load tier and weight")
end

function tests.renderPanelReportsTheFloorSWeatherWhenPresent()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.weather = Atmosphere.INFESTED
  ok(contains(Render.panel(game), "infested"), "the status panel names an active weather condition")
end

function tests.renderPanelFlagsSleepingFoesSeparatelyFromAwakeOnes()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local sleeper = Monsters.create(Monsters.byKey.orc, 1, 10, 6, 1)
  sleeper.awareness = Stealth.DORMANT
  game.level.entities = { sleeper }
  ok(contains(Render.panel(game), "1 asleep"), "the status panel tallies how many visible foes are still asleep")

  local awake = Monsters.create(Monsters.byKey.orc, 2, 11, 6, 1)
  game.level.entities = { awake }
  ok(not contains(Render.panel(game), "asleep"), "the panel omits the asleep tally once every foe is awake")
end

function tests.renderPanelShowsTheActiveSetBonusWhenOneApplies()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  ok(not contains(Render.panel(game), "set "), "the panel omits the set line without an active bonus")
  Items.equipWeapon(Sets.create("ironclad", "weapon"), game.player)
  Items.equipArmor(Sets.create("ironclad", "armor"), game.player)
  ok(contains(Render.panel(game), "Ironclad 2pc"), "the panel names the active set and its piece count")
end

function tests.renderPanelPrefixesCursedGearOnceRevealedButNotBefore()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.weapon = Curses.afflict(Items.weapon("dagger", 5), Curses.pool.weapon[1])
  ok(not contains(Render.panel(game), "cursed"), "an unrevealed curse never shows in the status panel")
  Curses.reveal(game.player.weapon)
  ok(contains(Render.panel(game), "cursed dagger"), "a revealed curse is flagged in the status panel")
end

function tests.renderPanelShowsComboOnlyOnceItIsBuilt()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  ok(not contains(Render.panel(game), "combo"), "a fresh player with no momentum shows no combo line")
  game.player.combo = 3
  ok(contains(Render.panel(game), "combo x3"), "a built-up combo is reported in the status panel")
end

function tests.renderPanelShowsWetOnlyWhileSoaked()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  ok(not contains(Render.panel(game), "wet"), "a fresh dry player shows no wet line")
  game.player.wet = 2
  ok(contains(Render.panel(game), "wet (2)"), "a soaked player's status panel reports the remaining soak turns")
end

function tests.renderPanelShowsSanityOnlyOnceItDropsBelowComposed()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  ok(not contains(Render.panel(game), "sanity"), "a fully composed player shows no sanity line at all")
  game.player.sanity = 30
  ok(contains(Render.panel(game), "sanity 30/100 (terrified)"), "a shaken mind is reported in the status panel")
end

function tests.renderPanelShowsTheDiseaseStageOnceThePlayerIsInfectedAndNothingBeforeInfection()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  ok(not contains(Render.panel(game), "parasites"), "an uninfected player's status line mentions no disease")
  Disease.infect(game.player, Disease.PARASITES)
  ok(contains(Render.panel(game), "gut parasites(incubating)"),
    "an incubating infection shows up in the status panel even before it erupts")
  game.player.disease.stage = 2
  ok(contains(Render.panel(game), "gut parasites(stage 2)"),
    "an erupted infection reports its current stage in the status panel")
end

function tests.renderPanelNamesActiveStatusesByTheirNounsSeparatedByCommas()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  ok(contains(Render.panel(game), "status: none"), "a player with no statuses reads status: none")
  Status.apply(game.player, Status.POISON, 5, 1)
  ok(contains(Render.panel(game), "status: poison\n"), "a single status is shown by its noun alone")
  Status.apply(game.player, Status.CONFUSE, 5, 1)
  ok(contains(Render.panel(game), "status: poison, confusion\n"),
    "several statuses are listed by noun with commas, not as raw keys")
  ok(not contains(Render.panel(game), "confuse"), "the raw confuse key never reaches the panel")
  Disease.infect(game.player, Disease.PARASITES)
  ok(contains(Render.panel(game), "status: poison, confusion, gut parasites(incubating)\n"),
    "an infection joins the same comma separated status list")
end

function tests.renderPanelShowsTheActiveEventAndItsRemainingTurns()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  ok(not contains(Render.panel(game), "turns left"), "no active event shows no event line at all")
  game.level.event = { key = Events.BLOODMOON, turnsLeft = 7 }
  ok(contains(Render.panel(game), "event bloodmoon (7 turns left)"),
    "an active event reports its name and remaining turns")
end

function tests.renderPanelShowsMasteryOnlyOnceARankIsCrossed()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  ok(not contains(Render.panel(game), "mastery"), "a fresh player with no mastery shows no mastery line")
  for _ = 1, Proficiency.RANKS[1].hits do Proficiency.onMeleeHit(game.player) end
  ok(contains(Render.panel(game), string.format("mastery +%d with %s", Proficiency.RANKS[1].bonus, Proficiency.UNARMED)),
    "a crossed mastery rank is reported in the status panel")
end

function tests.renderPanelShowsActiveAscensionMutatorsByKey()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  ok(not contains(Render.panel(game), "ascension"), "no active mutators shows no ascension line at all")
  game.ascension = { "famine", "nightblind" }
  ok(contains(Render.panel(game), "ascension famine,nightblind"), "active mutators are listed by key in the panel")
end

function tests.renderPanelShowsWornGearOnlyOnceItHasTakenDamage()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Items.equipWeapon(Items.weapon("sword", 4), game.player)
  ok(not contains(Render.panel(game), "sword ("), "a pristine weapon's label carries no wear indicator")
  game.player.weapon.durability = 10
  ok(contains(Render.panel(game), "sword (10/30)"), "a dinged weapon's label reports its remaining durability")
  game.player.weapon.durability = 0
  ok(contains(Render.panel(game), "sword (broken)"), "a broken weapon's label says so plainly")
end

function tests.renderPanelKeepsEveryLineWithinEightyColumnsUnderACrowdedState()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local player = game.player
  for kind in pairs(Status.defs) do Status.apply(player, kind, 5, 1) end
  Disease.infect(player, Disease.PARASITES)
  player.disease.stage = 3
  local weapon = Curses.afflict(Items.weapon("sword", 4), Curses.pool.weapon[1])
  weapon.name = "vicious flaming Greatsword of the Drowned Ossuary Kings and Their Hollow Court"
  Curses.reveal(weapon)
  Items.equipWeapon(weapon, player)
  player.weapon.durability = 7
  for _ = 1, Proficiency.RANKS[1].hits do Proficiency.onMeleeHit(player) end
  player.sanity = 12
  game.level.event = { key = Events.BLOODMOON, turnsLeft = 117 }
  game.ascension = { "famine", "nightblind", "glasscannon", "hordes", "brittle", "cursedfloors", "nohealing" }
  game.log:add("The greatsword bites deep into the ancient bone golem and its ribcage cracks apart like thunder")
  local panel = Render.panel(game)
  for line in (panel .. "\n"):gmatch("(.-)\n") do
    ok(#line <= 80, string.format("panel line fits 80 columns (%d): %s", #line, line))
  end
  local flattened = panel:gsub("%s+", " ")
  for kind in pairs(Status.defs) do
    ok(contains(flattened, Status.noun(kind)), "a wrapped status list still names " .. Status.noun(kind))
  end
  ok(contains(flattened, "gut parasites(stage 3)"), "a wrapped status list still reports the disease stage")
  ok(contains(flattened, "weapon cursed " .. weapon.name .. " (7/30)"), "a wrapped weapon line keeps the full label")
  ok(contains(flattened, "with " .. weapon.name), "a wrapped mastery line keeps the full weapon name")
  ok(contains(flattened, "cursedfloors,nohealing"), "a wrapped ascension list keeps every mutator")
end

function tests.renderShowsAClosedChestGlyphAndAnOpenedOneOnceEmptied()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chest = { x = 4, y = 6, locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
  game.level.chests = { chest }
  game:computeVisible()
  eq(glyphAt(game, 4, 6), Render.glyphs.chest, "a closed chest renders as its own glyph")
  chest.opened = true
  chest.loot = {}
  eq(glyphAt(game, 4, 6), Render.glyphs.emptiedChest, "an emptied chest renders as its own distinct glyph")
end

function tests.renderDrawsARiftGlyphWhenVisible()
  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  rendered.level.rifts = { { x = 5, y = 6 } }
  rendered:computeVisible()
  eq(glyphAt(rendered, 5, 6), Render.glyphs.rift, "a rift on a visible cell renders as its glyph")
end

function tests.renderDrawsEachFeatureAndFloorItemWithItsOwnGlyph()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.blocks = { { x = 5, y = 4 } }
  game.level.plates = { { x = 6, y = 4 } }
  game.level.nodes = { { x = 7, y = 4, kind = Nodes.GEM, charges = 1 }, { x = 8, y = 4, kind = Nodes.ORE, charges = 1 } }
  game.level.floorItems = {
    { x = 5, y = 8, item = Items.charm("hound") },
    { x = 6, y = 8, item = Items.lockpick() },
    { x = 7, y = 8, item = Items.ammo(nil, 3) },
    { x = 8, y = 8, item = Items.net() },
    { x = 9, y = 8, item = Items.key() },
    { x = 10, y = 8, item = Graves.floorItem({ className = "fighter", gold = 0, essence = 0 }) },
  }
  game.level.map:set(9, 4, Tiles.LAVA)
  game:computeVisible()
  eq(glyphAt(game, 5, 4), "0", "a pushable block keeps the boulder glyph")
  eq(glyphAt(game, 6, 4), ";", "a pressure plate keeps its glyph")
  eq(glyphAt(game, 7, 4), "S", "a gem seam no longer shares the mimic's letter")
  eq(glyphAt(game, 8, 4), "O", "an ore vein keeps its glyph")
  eq(glyphAt(game, 9, 4), "}", "lava is drawn as in NetHack, apart from food")
  eq(glyphAt(game, 5, 8), "]", "a companion charm no longer looks like a block")
  eq(glyphAt(game, 6, 8), "J", "a lockpick no longer looks like a pressure plate")
  eq(glyphAt(game, 7, 8), "{", "arrows no longer look like a trap")
  eq(glyphAt(game, 8, 8), "F", "a net no longer looks like an orc")
  eq(glyphAt(game, 9, 8), "(", "a key no longer looks like a gem")
  eq(glyphAt(game, 10, 8), "|", "a grave marker no longer looks like a banshee")
end

local function addOwner(owners, glyph, owner)
  owners[glyph] = owners[glyph] or {}
  owners[glyph][#owners[glyph] + 1] = owner
end

function tests.everyMapFeatureItemMonsterAndAllyHasAGlyphNoOtherThingUses()
  local owners = {}
  for name, glyph in pairs(Tiles) do
    if type(glyph) == "string" then addOwner(owners, glyph, "tile " .. name) end
  end
  for name, glyph in pairs(Render.glyphs) do addOwner(owners, glyph, "feature " .. name) end
  for kind, glyph in pairs(Nodes.glyphs) do addOwner(owners, glyph, "node " .. kind) end
  for kind, glyph in pairs(Items.glyphs) do addOwner(owners, glyph, "item " .. kind) end
  addOwner(owners, Graves.markerGlyph, "grave marker")
  for _, spec in ipairs(Monsters.species) do addOwner(owners, spec.glyph, "monster " .. spec.key) end
  for _, spec in ipairs(Bosses.catalog) do addOwner(owners, spec.glyph, "boss " .. spec.key) end
  for _, spec in ipairs(Companions.species) do addOwner(owners, spec.glyph, "companion " .. spec.key) end
  for _, spec in ipairs(Mercenaries.roster) do addOwner(owners, spec.glyph, "mercenary " .. spec.key) end
  for _, entity in ipairs({ Graves.reveal(1, 1, 1, {}), Mimics.reveal(1, 1, 1, 1) }) do
    addOwner(owners, entity.glyph, "monster " .. entity.species)
  end
  addOwner(owners, Reanimation.thrallGlyph, "thrall")
  for glyph, list in pairs(owners) do
    table.sort(list)
    eq(#list, 1, string.format("glyph %q belongs to one thing only: %s", glyph, table.concat(list, ", ")))
    eq(#glyph, 1, string.format("glyph %q of %s is a single character", glyph, table.concat(list, ", ")))
  end
end

function tests.aHiredMedicAndADarkMageRenderWithDifferentLetters()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local medic = Mercenaries.hire(game, "medic")
  local mage = Monsters.create(Monsters.byKey.mage, 50, 10, 6, 1)
  game.level.entities[#game.level.entities + 1] = mage
  game:computeVisible()
  local medicGlyph, mageGlyph = glyphAt(game, medic.x, medic.y), glyphAt(game, mage.x, mage.y)
  eq(medicGlyph, Mercenaries.byKey.medic.glyph, "the hired medic is drawn with its own glyph")
  eq(mageGlyph, Monsters.byKey.mage.glyph, "the dark mage is drawn with its own glyph")
  ok(medicGlyph ~= mageGlyph, "an ally and a hostile caster can be told apart on the map")
end

function tests.mimicDisguisesCopyTheGlyphOfTheThingTheyImitate()
  local byName = {}
  for _, disguise in ipairs(Mimics.DISGUISES) do byName[disguise.name] = disguise.glyph end
  eq(byName["a weathered chest"], Render.glyphs.chest, "a chest mimic looks exactly like a chest")
  eq(byName["an ornate tome"], Items.glyphs[Items.TOME], "a tome mimic looks exactly like a tome")
  eq(byName["a glinting pile of gold"], Items.glyphs[Items.GOLD], "a gold mimic looks exactly like gold")
  eq(byName["a discarded shield"], Items.glyphs[Items.ARMOR], "a shield mimic looks exactly like armor")
end

return tests
