local Map = require("map")
local Carve = require("gen.carve")

local Bsp = {}

local function split(node, rng, minLeaf, depth)
  if depth <= 0 or (node.w < minLeaf * 2 and node.h < minLeaf * 2) then
    return
  end
  local horizontal
  if node.w > node.h and node.w >= minLeaf * 2 then
    horizontal = false
  elseif node.h >= minLeaf * 2 then
    horizontal = true
  else
    return
  end

  if horizontal then
    local cut = rng:range(minLeaf, node.h - minLeaf)
    node.left = { x = node.x, y = node.y, w = node.w, h = cut }
    node.right = { x = node.x, y = node.y + cut, w = node.w, h = node.h - cut }
  else
    local cut = rng:range(minLeaf, node.w - minLeaf)
    node.left = { x = node.x, y = node.y, w = cut, h = node.h }
    node.right = { x = node.x + cut, y = node.y, w = node.w - cut, h = node.h }
  end
  split(node.left, rng, minLeaf, depth - 1)
  split(node.right, rng, minLeaf, depth - 1)
end

local function carveLeaves(node, map, rng)
  if node.left or node.right then
    carveLeaves(node.left, map, rng)
    carveLeaves(node.right, map, rng)
    local a = node.left.room
    local b = node.right.room
    local ax, ay = Carve.center(a)
    local bx, by = Carve.center(b)
    Carve.corridor(map, ax, ay, bx, by, rng)
    node.room = a
    return
  end
  local w = rng:range(3, math.max(3, node.w - 2))
  local h = rng:range(3, math.max(3, node.h - 2))
  local x = node.x + rng:range(1, math.max(1, node.w - w - 1))
  local y = node.y + rng:range(1, math.max(1, node.h - h - 1))
  local room = { x = x, y = y, w = w, h = h }
  Carve.rect(map, room.x, room.y, room.w, room.h)
  map.rooms[#map.rooms + 1] = room
  node.room = room
end

function Bsp.generate(width, height, rng, options)
  options = options or {}
  local minLeaf = options.minLeaf or 7
  local maxDepth = options.maxDepth or 5
  local map = Map.new(width, height)
  local root = { x = 2, y = 2, w = width - 3, h = height - 3 }
  split(root, rng, minLeaf, maxDepth)
  carveLeaves(root, map, rng)
  return map
end

return Bsp
