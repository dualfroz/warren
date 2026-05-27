-- Headless entry point. Examples:
--   lua warren.lua --seed 42 --auto 50
--   lua warren.lua --seed 7 --auto 30 --save run.sav
--   lua warren.lua --load run.sav

local scriptDir = arg[0]:match("^(.*)[/\\]") or "."
package.path = scriptDir .. "/src/?.lua;" .. scriptDir .. "/../src/?.lua;" .. package.path

local Game = require("game")

local function parseArgs(argv)
  local opts = { seed = os.time() & 0xFFFF, auto = 0 }
  local i = 1
  while i <= #argv do
    local flag = argv[i]
    if flag == "--seed" then opts.seed = math.tointeger(tonumber(argv[i + 1])); i = i + 2
    elseif flag == "--auto" then opts.auto = math.tointeger(tonumber(argv[i + 1])); i = i + 2
    elseif flag == "--save" then opts.save = argv[i + 1]; i = i + 2
    elseif flag == "--load" then opts.load = argv[i + 1]; i = i + 2
    else i = i + 1 end
  end
  return opts
end

local opts = parseArgs(arg)
local game = opts.load and Game.load(opts.load) or Game.new(opts.seed)

for _ = 1, opts.auto do
  if not game.player:isAlive() then break end
  game:autoStep()
end

io.write(game:render(), "\n")

if opts.save then
  game:save(opts.save)
  io.write("saved to " .. opts.save .. "\n")
end
