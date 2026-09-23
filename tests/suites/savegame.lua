local helpers = require("helpers")
local Items = require("items")
local Serialize = require("serialize")
local Game = require("game")
local Sanity = require("sanity")
local SaveGame = require("savegame")
local Tiles = require("tiles")
local Render = require("render")
local Graves = require("graves")
local Entity = require("entity")
local Mercenaries = require("mercenaries")
local Companions = require("companions")

local ok, eq, contains = helpers.ok, helpers.eq, helpers.contains

local tests = helpers.suite()

function tests.saveLoadRoundTrip()
  local game = Game.new(2024)
  for _ = 1, 80 do
    if not game.player:isAlive() then break end
    game:autoStep()
  end
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(Serialize.encode(restored:toData()), Serialize.encode(game:toData()), "state is byte-identical after round trip")
  eq(restored.player.hp, game.player.hp, "player hp survives round trip")
  eq(restored.depth, game.depth, "depth survives round trip")
  eq(restored.turn, game.turn, "turn survives round trip")
  eq(table.concat(restored.level.map.tiles), table.concat(game.level.map.tiles), "current map survives round trip")
  eq(#restored.level.entities, #game.level.entities, "monster count survives round trip")
  eq(restored:render(), game:render(), "render is identical after round trip")
end

function tests.saveGameFnv1a32MatchesThePublishedTestVectors()
  eq(SaveGame.fnv1a32(""), 2166136261, "the empty string hashes to the FNV-1a32 offset basis")
  eq(SaveGame.fnv1a32("a"), 3826002220, "a single byte matches the published FNV-1a32 test vector")
  eq(SaveGame.fnv1a32("warren"), SaveGame.fnv1a32("warren"), "hashing the same string twice is deterministic")
  ok(SaveGame.fnv1a32("warren") ~= SaveGame.fnv1a32("warreo"), "a one-character change changes the hash")
end

function tests.saveGameEncodeDecodeRoundTripsAValueUnchanged()
  local codec = SaveGame.new({})
  local data = { hp = 12, name = "vault-keeper", tags = { "brave", "unlucky" } }
  local decoded = codec.decode(codec.encode(data))
  eq(Serialize.encode(decoded), Serialize.encode(data), "a value survives an encode/decode round trip byte for byte")
end

function tests.saveGameSaveThenLoadRoundTripsThroughARealFile()
  local codec = SaveGame.new({})
  local path = os.tmpname()
  codec.save(path, { hp = 12, tags = { "brave", "unlucky" } })
  local data = codec.load(path)
  os.remove(path)
  eq(data.hp, 12, "a saved number survives a real file round trip")
  eq(data.tags[1], "brave", "a saved array survives a real file round trip")
  eq(data.tags[2], "unlucky", "array order survives a real file round trip")
end

function tests.saveGameLoadReportsMissingRatherThanErroringOnANonexistentFile()
  local codec = SaveGame.new({})
  local data, err = codec.load("/tmp/warren_savegame_does_not_exist_998877.sav")
  eq(data, nil, "a missing file yields no data")
  eq(err, "missing", "the reason is reported as missing, distinct from corruption")
end

function tests.saveGameDecodeRejectsTextThatIsNotValidLuaAtAll()
  local codec = SaveGame.new({})
  local data, err = codec.decode("{ this is not } valid ( lua at all")
  eq(data, nil, "unparseable text yields no data")
  ok(contains(err or "", "corrupt"), "the failure is reported as corruption")
end

function tests.saveGameDecodeDetectsATamperedPayloadViaChecksumMismatch()
  local codec = SaveGame.new({})
  local text = codec.encode({ marker = "TAMPERMARKER", count = 3 })
  local tampered = text:gsub("TAMPERMARKER", "TAMPERMARKED", 1)
  ok(tampered ~= text, "the substitution actually changed the encoded text")
  local data, err = codec.decode(tampered)
  eq(data, nil, "a payload that no longer matches its checksum is rejected")
  ok(contains(err or "", "checksum mismatch"), "the rejection names the checksum as the reason")
end

function tests.saveGameDecodeRefusesASaveFromAVersionNewerThanTheCodecSupports()
  local codec = SaveGame.new({ function(d) return d end })
  local payload = Serialize.encode({ x = 1 })
  local envelope = {
    magic = "WARRENSAVE", version = codec.CURRENT_VERSION + 1,
    checksum = SaveGame.fnv1a32(payload), payload = payload,
  }
  local data, err = codec.decode(Serialize.encode(envelope))
  eq(data, nil, "a save newer than this codec understands is refused rather than guessed at")
  ok(contains(err or "", "future version"), "the refusal names the version mismatch as the reason")
end

function tests.saveGameWithNoMigrationHistoryPassesLegacyDataThroughUnchanged()
  local codec = SaveGame.new({})
  local path = os.tmpname()
  Serialize.saveFile(path, { greeting = "hi", count = 7 })
  local data, err = codec.load(path)
  os.remove(path)
  eq(err, nil, "a magic-less legacy file loads without an error")
  eq(data.greeting, "hi", "legacy string fields survive untouched")
  eq(data.count, 7, "legacy numeric fields survive untouched")
end

function tests.saveGameMigrationChainAppliesEachStepInOrderStartingFromVersionOne()
  local codec = SaveGame.new({
    [1] = function(d) d.trail = d.trail or {}; table.insert(d.trail, "one"); return d end,
    [2] = function(d) d.trail = d.trail or {}; table.insert(d.trail, "two"); return d end,
  })
  eq(codec.CURRENT_VERSION, 3, "two migrations put the current version one past the last step")
  local path = os.tmpname()
  Serialize.saveFile(path, { trail = {} })
  local data = codec.load(path)
  os.remove(path)
  eq(#data.trail, 2, "both migration steps ran")
  eq(data.trail[1], "one", "step one ran before step two")
  eq(data.trail[2], "two", "step two ran after step one")
end

function tests.saveGameMigrationChainSkipsStepsAlreadyPastTheStoredVersion()
  local codec = SaveGame.new({
    [1] = function(d) d.trail = d.trail or {}; table.insert(d.trail, "one"); return d end,
    [2] = function(d) d.trail = d.trail or {}; table.insert(d.trail, "two"); return d end,
  })
  local payload = Serialize.encode({ trail = {} })
  local envelope = {
    magic = "WARRENSAVE", version = 2,
    checksum = SaveGame.fnv1a32(payload), payload = payload,
  }
  local data = codec.decode(Serialize.encode(envelope))
  eq(#data.trail, 1, "a save already at version 2 only runs the one remaining step")
  eq(data.trail[1], "two", "the remaining step is the one from version 2 onward, not version 1's")
end

function tests.gameLoadUpgradesALegacyPreEnvelopeSaveMissingNewerPlayerFields()
  local game = Game.new(1, { class = "fighter" })
  local data = game:toData()
  data.playerExtra.essence = nil
  data.playerExtra.skills = nil
  data.playerExtra.skillPoints = nil
  data.playerExtra.skillCooldowns = nil
  data.playerExtra.reputation = nil
  data.playerExtra.sanity = nil
  data.stats.vaultsOpened = nil
  data.stats.setPiecesFound = nil
  local path = os.tmpname()
  Serialize.saveFile(path, data)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.essence, 0, "essence defaults in for a save predating it")
  eq(restored.stats.vaultsOpened, 0, "vaultsOpened defaults in for a save predating it")
  eq(restored.stats.setPiecesFound, 0, "setPiecesFound defaults in for a save predating it")
  eq(type(restored.player.skills), "table", "skills defaults to an empty table for a save predating the skill tree")
  eq(restored.player.skillPoints, 0, "skillPoints defaults in for a save predating the skill tree")
  eq(type(restored.player.skillCooldowns), "table",
    "skillCooldowns defaults to an empty table for a save predating the skill tree")
  eq(type(restored.player.reputation), "table", "reputation defaults to an empty table for a save predating it")
  eq(restored.player.sanity, Sanity.MAX, "sanity defaults to full for a save predating the sanity system")
end

function tests.gameLoadRaisesAClearErrorOnATruncatedSaveFileInsteadOfCrashingObscurely()
  local game = Game.new(1)
  local path = os.tmpname()
  game:save(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("a")
  file:close()
  local out = assert(io.open(path, "w"))
  out:write(text:sub(1, 20))
  out:close()
  local success, err = pcall(Game.load, path)
  os.remove(path)
  eq(success, false, "loading a truncated save fails rather than silently misloading")
  ok(contains(err or "", "corrupt"), "the failure names corruption instead of an obscure nil-call error")
end

function tests.gameLoadRaisesAClearErrorForASaveFromAFutureVersion()
  local payload = Serialize.encode({ marker = 1 })
  local envelope = {
    magic = "WARRENSAVE", version = 999,
    checksum = SaveGame.fnv1a32(payload), payload = payload,
  }
  local path = os.tmpname()
  local file = assert(io.open(path, "w"))
  file:write(Serialize.encode(envelope))
  file:close()
  local success, err = pcall(Game.load, path)
  os.remove(path)
  eq(success, false, "loading a save from a newer format fails rather than misinterpreting it")
  ok(contains(err or "", "future version"), "the failure names the version mismatch")
end

function tests.gameSaveLoadRoundTripsAnActiveRiftCrossing()
  local game = Game.new(9)
  game.level.rifts = { { x = game.player.x, y = game.player.y } }
  game.player.inventory[#game.player.inventory + 1] = Items.riftstone()
  ok(game:enterRift(), "the staged rift crossing succeeds")
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.rift, true, "the rift flag survives a save/load round trip")
  eq(restored.depth, game.depth, "depth survives the round trip")
  eq(table.concat(restored.level.map.tiles), table.concat(game.level.map.tiles),
    "the active pocket floor's map survives the round trip")
  eq(restored.riftReturn.x, game.riftReturn.x, "the remembered return position survives the round trip")
  eq(restored.riftReturn.y, game.riftReturn.y, "the remembered return position survives the round trip")
  eq(restored.riftReturn.depth, game.riftReturn.depth, "the remembered return depth survives the round trip")
  restored.player.x, restored.player.y = restored.level.downX, restored.level.downY
  ok(restored:exitRift(), "exiting still works correctly after a save/load round trip")
  eq(restored.rift, false, "the rift flag clears after exiting post-load")
end

function tests.gameSaveLoadRoundTripsAnActiveHordeArena()
  local game = Game.new(11)
  game:startHorde()
  for _, entity in ipairs(game.level.entities) do entity.hp = 0 end
  game:cleanupDead()
  game:endPlayerTurn()
  eq(game.horde.wave, 2, "the staged run has advanced to wave two before saving")
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  ok(restored.horde, "an active horde run survives a save/load round trip at all")
  eq(restored.horde.wave, 2, "the exact wave in progress survives the round trip")
  eq(restored.level.generator, "horde", "the restored level is still tagged as the arena")
  eq(table.concat(restored.level.map.tiles), table.concat(game.level.map.tiles),
    "the arena's own map survives the round trip rather than falling back to the abandoned floor")
  eq(#restored.level.entities, #game.level.entities, "wave two's monster count survives the round trip")
  eq(restored.player.x, game.player.x, "the player's arena position survives the round trip")
  eq(restored.player.y, game.player.y, "the player's arena position survives the round trip")
  for _, entity in ipairs(restored.level.entities) do entity.hp = 0 end
  restored:cleanupDead()
  restored:endPlayerTurn()
  eq(restored.horde.wave, 3, "the restored run's Horde.tick still advances waves normally after loading")
end

function tests.gameSaveLoadOfAnOrdinaryRunNeverGainsAHordeField()
  local game = Game.new(3)
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.horde, nil, "a run that never entered the arena has no horde field after a round trip")
  eq(restored.level.generator, game.level.generator,
    "an ordinary floor's own generator survives the round trip unaffected by the horde snapshot fields")
end

function tests.gameLoadRestylesTheGlyphsOfAVersionFourSaveWithoutTouchingItsKeys()
  local game = Game.new(3)
  local lavaX, lavaY = game.player.x, game.player.y
  game.level.map:set(lavaX, lavaY, "%")
  game.player.inventory = {
    { kind = Items.CHARM, companion = "hound", name = "charm of the hound", glyph = "0" },
    { kind = Items.AMMO, name = "arrow", glyph = "^", count = 5 },
    { kind = Items.LOCKPICK, name = "lockpick", glyph = ";" },
    { kind = Items.KEY, name = "iron key", glyph = "*" },
    { kind = Items.BOW, name = "short bow", glyph = "}", power = 2, range = 5, durability = 30, maxDurability = 30 },
  }
  game.level.floorItems = {
    { x = lavaX, y = lavaY, item = { kind = "mimic", mimic = true, name = "a weathered chest", glyph = "=" } },
    { x = lavaX, y = lavaY, item = { kind = "grave", grave = true, name = "a weathered grave marker", glyph = "b" } },
  }
  local monsterGlyphs = {}
  for i, entity in ipairs(game.level.entities) do monsterGlyphs[i] = entity.glyph end
  local payload = Serialize.encode(game:toData())
  local envelope = { magic = "WARRENSAVE", version = 4, checksum = SaveGame.fnv1a32(payload), payload = payload }
  local path = os.tmpname()
  local file = assert(io.open(path, "w"))
  file:write(Serialize.encode(envelope))
  file:close()
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.level.map:get(lavaX, lavaY), Tiles.LAVA, "a legacy lava tile is rewritten to the current lava glyph")
  ok(Tiles.isLava(restored.level.map:get(lavaX, lavaY)), "the rewritten tile still behaves as lava")
  for i, item in ipairs(restored.player.inventory) do
    eq(item.glyph, Items.glyphs[item.kind], "a carried " .. item.kind .. " takes its kind's current glyph")
    eq(item.name, game.player.inventory[i].name, "the carried item keeps every other field")
  end
  eq(restored.player.inventory[2].count, 5, "the arrow stack keeps its count")
  eq(restored.level.floorItems[1].item.glyph, Render.glyphs.chest, "a chest mimic keeps looking like a real chest")
  eq(restored.level.floorItems[2].item.glyph, Graves.markerGlyph, "a grave marker takes the grave glyph")
  for i, entity in ipairs(restored.level.entities) do
    eq(entity.glyph, monsterGlyphs[i], "a monster's own glyph is never rewritten")
  end
end

local function writeVersionedSave(game, version)
  local payload = Serialize.encode(game:toData())
  local envelope = { magic = "WARRENSAVE", version = version, checksum = SaveGame.fnv1a32(payload), payload = payload }
  local path = os.tmpname()
  local file = assert(io.open(path, "w"))
  file:write(Serialize.encode(envelope))
  file:close()
  return path
end

function tests.gameLoadGivesAlliesAndShadesFromAVersionFiveSaveTheirOwnLetters()
  local game = Game.new(3)
  local px, py = game.player.x, game.player.y
  local function staged(fields)
    local entity = Entity.new(fields)
    entity.x, entity.y = px, py
    return entity
  end
  local legacy = {
    staged({ glyph = "w", name = "sellsword", kind = "hireling", species = "sellsword", hp = 24, attack = 6, defense = 2 }),
    staged({ glyph = "k", name = "skirmisher", kind = "hireling", species = "skirmisher", hp = 15, attack = 5, defense = 1 }),
    staged({ glyph = "m", name = "field medic", kind = "hireling", species = "medic", hp = 13, attack = 2, defense = 1 }),
    staged({ glyph = "G", name = "vengeful shade", kind = "monster", species = "shade", hp = 10, attack = 4, defense = 1 }),
    staged({ glyph = "G", name = "clay golem", kind = "companion", species = "golem", hp = 26, attack = 5, defense = 3 }),
    staged({ glyph = "o", name = "orc", kind = "hireling", species = "orc", hp = 10, attack = 4, defense = 1 }),
  }
  legacy[1].wage, legacy[1].loyalty = 14, 80
  local monsterGlyphs = {}
  for i, entity in ipairs(game.level.entities) do monsterGlyphs[i] = entity.glyph end
  local before = #game.level.entities
  for _, entity in ipairs(legacy) do game.level.entities[#game.level.entities + 1] = entity end
  local path = writeVersionedSave(game, 5)
  local restored = Game.load(path)
  os.remove(path)
  local entities = restored.level.entities
  for i = 1, before do
    eq(entities[i].glyph, monsterGlyphs[i], "an ordinary monster's glyph is left as it was")
  end
  eq(entities[before + 1].glyph, Mercenaries.byKey.sellsword.glyph, "a saved sellsword takes its new letter")
  eq(entities[before + 2].glyph, Mercenaries.byKey.skirmisher.glyph, "a saved skirmisher takes its new letter")
  eq(entities[before + 3].glyph, Mercenaries.byKey.medic.glyph, "a saved field medic takes its new letter")
  eq(entities[before + 4].glyph, Graves.shadeGlyph, "a saved vengeful shade takes its new letter")
  eq(entities[before + 5].glyph, Companions.byKey.golem.glyph, "a saved clay golem keeps its letter")
  eq(entities[before + 6].glyph, "o", "a polymorphed hireling keeps the glyph of the form it took")
  eq(entities[before + 1].wage, 14, "the sellsword keeps its wage")
  eq(entities[before + 1].loyalty, 80, "the sellsword keeps its loyalty")
  eq(entities[before + 4].name, "vengeful shade", "the shade keeps every other field")
end

function tests.gameSaveLoadRoundTripKeepsTheCurrentAllyLetters()
  local game = Game.new(3)
  game.level.entities = {}
  local hireling = Mercenaries.hire(game, "skirmisher")
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.level.entities[1].glyph, hireling.glyph, "a current save loads its hireling with the same letter")
end

return tests
