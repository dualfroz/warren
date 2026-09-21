local Tiles = require("tiles")

local Prefab = {}

Prefab.vaults = {
  {
    name = "treasureCell",
    rows = {
      "#########",
      "#.......#",
      "#.#####.#",
      "#.#*M*#.#",
      "#.#*L*#+#",
      "#.#####.#",
      "#.......#",
      "#########",
    },
  },
  {
    name = "guardPost",
    rows = {
      "#######",
      "#M...M#",
      "#..*..#",
      "#M...M#",
      "#######",
    },
  },
  {
    name = "flooded",
    rows = {
      "#########",
      "#~~...~~#",
      "#~..*..~#",
      "#..MLM..#",
      "#~..*..~#",
      "#~~...~~#",
      "#########",
    },
  },
}

local glyphFor = {
  ["#"] = Tiles.WALL,
  ["."] = Tiles.FLOOR,
  ["+"] = Tiles.DOOR_CLOSED,
  ["~"] = Tiles.WATER,
  ["*"] = Tiles.FLOOR,
  ["M"] = Tiles.FLOOR,
  ["L"] = Tiles.FLOOR,
}

function Prefab.size(vault)
  return #vault.rows[1], #vault.rows
end

function Prefab.fits(map, vault, ox, oy)
  local w, h = Prefab.size(vault)
  return ox >= 2 and oy >= 2 and ox + w - 1 <= map.width - 1 and oy + h - 1 <= map.height - 1
end

function Prefab.stamp(map, vault, ox, oy)
  local treasure, monsters, loot = {}, {}, {}
  for row = 1, #vault.rows do
    local line = vault.rows[row]
    for col = 1, #line do
      local mark = line:sub(col, col)
      local x, y = ox + col - 1, oy + row - 1
      map:set(x, y, glyphFor[mark] or Tiles.FLOOR)
      if mark == "*" then treasure[#treasure + 1] = { x = x, y = y } end
      if mark == "M" then monsters[#monsters + 1] = { x = x, y = y } end
      if mark == "L" then loot[#loot + 1] = { x = x, y = y } end
    end
  end
  return { name = vault.name, treasure = treasure, monsters = monsters, loot = loot }
end

return Prefab
