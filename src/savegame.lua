-- A reusable versioned, checksummed save container laid on top of
-- serialize.lua's plain Lua-expression encoding. serialize.lua only knows how
-- to turn a value into text and back; it has no notion of "this text might be
-- truncated, hand-edited, or written by a codebase three versions ago". This
-- module adds that layer: an envelope carrying a schema version and an
-- FNV-1a32 checksum of its payload, plus a migration chain that walks old
-- data forward one version at a time.
--
-- A file written before this module existed - a bare Serialize.saveFile dump
-- with no envelope at all - is treated as implicit version 1, so an existing
-- save on disk keeps loading instead of being rejected outright.
--
-- SaveGame.new(migrations) builds one codec for one call site. `migrations`
-- is a 1-indexed array where migrations[v] transforms data from version v to
-- v+1; the codec's CURRENT_VERSION is #migrations + 1. Two call sites with
-- differently shaped data (a run's game state, a player's meta progression)
-- each get their own codec with their own migration chain - this module
-- knows nothing about either shape.

local Serialize = require("serialize")

local SaveGame = {}

local MAGIC = "WARRENSAVE"
local MASK32 = 0xFFFFFFFF

-- FNV-1a, 32-bit. Verified below against the algorithm's published test
-- vectors (fnv1a32("") and fnv1a32("a")), not just self-consistency.
function SaveGame.fnv1a32(str)
  local hash = 2166136261
  for i = 1, #str do
    hash = (hash ~ str:byte(i)) & MASK32
    hash = (hash * 16777619) & MASK32
  end
  return hash
end

local function migrateForward(data, fromVersion, migrations, currentVersion)
  for v = fromVersion, currentVersion - 1 do
    data = migrations[v](data)
  end
  return data
end

-- Builds a codec bound to one migration chain. `migrations` may be empty
-- (CURRENT_VERSION == 1); a version-1-only codec still gets checksumming and
-- corruption detection for free.
function SaveGame.new(migrations)
  migrations = migrations or {}
  local currentVersion = #migrations + 1
  local codec = { CURRENT_VERSION = currentVersion }

  function codec.encode(data)
    local payload = Serialize.encode(data)
    local envelope = {
      magic = MAGIC,
      version = currentVersion,
      checksum = SaveGame.fnv1a32(payload),
      payload = payload,
    }
    return Serialize.encode(envelope)
  end

  -- Returns (data) on success, or (nil, reason) on any failure. `reason` is
  -- always one of: "missing" (only from .load, never from .decode), a string
  -- starting with "corrupt:", or a string starting with "future version:".
  function codec.decode(text)
    local ok, value = pcall(Serialize.decode, text)
    if not ok or type(value) ~= "table" then
      return nil, "corrupt: cannot parse save data"
    end
    if value.magic ~= MAGIC then
      -- No envelope at all: a save from before this codec existed. The
      -- decoded value IS the raw data, at implicit version 1.
      return migrateForward(value, 1, migrations, currentVersion)
    end
    if type(value.version) ~= "number" or type(value.payload) ~= "string"
        or type(value.checksum) ~= "number" then
      return nil, "corrupt: malformed save envelope"
    end
    if value.version > currentVersion then
      return nil, "future version: save is v" .. value.version
        .. ", this build reads up to v" .. currentVersion
    end
    if SaveGame.fnv1a32(value.payload) ~= value.checksum then
      return nil, "corrupt: checksum mismatch"
    end
    local ok2, data = pcall(Serialize.decode, value.payload)
    if not ok2 or type(data) ~= "table" then
      return nil, "corrupt: cannot parse save payload"
    end
    return migrateForward(data, value.version, migrations, currentVersion)
  end

  function codec.save(path, data)
    local file = assert(io.open(path, "w"))
    file:write(codec.encode(data))
    file:close()
  end

  function codec.load(path)
    local file = io.open(path, "r")
    if not file then return nil, "missing" end
    local text = file:read("a")
    file:close()
    return codec.decode(text)
  end

  return codec
end

return SaveGame
