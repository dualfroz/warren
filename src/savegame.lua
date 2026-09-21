local Serialize = require("serialize")

local SaveGame = {}

local MAGIC = "WARRENSAVE"
local MASK32 = 0xFFFFFFFF

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

  function codec.decode(text)
    local ok, value = pcall(Serialize.decode, text)
    if not ok or type(value) ~= "table" then
      return nil, "corrupt: cannot parse save data"
    end
    if value.magic ~= MAGIC then
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
