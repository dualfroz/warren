-- Serializes plain data (no functions, no cycles) to a Lua expression that
-- rebuilds it. Keys are emitted in sorted order so the text is deterministic,
-- which makes save/load round trips byte-for-byte comparable.

local Serialize = {}

local encodeValue
local encodeTable

local function encodeString(str)
  local out = { '"' }
  for i = 1, #str do
    local char = str:sub(i, i)
    local byte = string.byte(char)
    if char == '"' then out[#out + 1] = '\\"'
    elseif char == '\\' then out[#out + 1] = '\\\\'
    elseif char == '\n' then out[#out + 1] = '\\n'
    elseif char == '\t' then out[#out + 1] = '\\t'
    elseif byte < 32 or byte > 126 then out[#out + 1] = string.format('\\%d', byte)
    else out[#out + 1] = char end
  end
  out[#out + 1] = '"'
  return table.concat(out)
end

local function isArray(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count == #tbl
end

local function keyLess(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  return a < b
end

encodeTable = function(tbl, out)
  out[#out + 1] = "{"
  if isArray(tbl) then
    for i = 1, #tbl do
      if i > 1 then out[#out + 1] = "," end
      encodeValue(tbl[i], out)
    end
  else
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys, keyLess)
    for i, k in ipairs(keys) do
      if i > 1 then out[#out + 1] = "," end
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        out[#out + 1] = k .. "="
      else
        out[#out + 1] = "["
        encodeValue(k, out)
        out[#out + 1] = "]="
      end
      encodeValue(tbl[k], out)
    end
  end
  out[#out + 1] = "}"
end

encodeValue = function(value, out)
  local kind = type(value)
  if kind == "nil" then out[#out + 1] = "nil"
  elseif kind == "boolean" then out[#out + 1] = value and "true" or "false"
  elseif kind == "number" then
    if math.type(value) == "integer" then out[#out + 1] = string.format("%d", value)
    else out[#out + 1] = string.format("%.17g", value) end
  elseif kind == "string" then out[#out + 1] = encodeString(value)
  elseif kind == "table" then encodeTable(value, out)
  else error("cannot serialize type " .. kind) end
end

function Serialize.encode(value)
  local out = {}
  encodeValue(value, out)
  return "return " .. table.concat(out)
end

function Serialize.decode(text)
  local chunk = load(text, "savegame", "t", {})
  return chunk()
end

function Serialize.saveFile(path, value)
  local file = assert(io.open(path, "w"))
  file:write(Serialize.encode(value))
  file:close()
end

function Serialize.loadFile(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("a")
  file:close()
  return Serialize.decode(text)
end

return Serialize
