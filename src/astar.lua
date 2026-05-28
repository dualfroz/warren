-- A* on the 4-connected grid with a binary min-heap open set and Manhattan
-- heuristic. Returns the path start..goal, or nil when unreachable.

local Astar = {}

local function heapPush(heap, node, priority)
  heap[#heap + 1] = { node = node, priority = priority }
  local i = #heap
  while i > 1 do
    local parent = i // 2
    if heap[parent].priority <= heap[i].priority then break end
    heap[parent], heap[i] = heap[i], heap[parent]
    i = parent
  end
end

local function heapPop(heap)
  local top = heap[1]
  local last = heap[#heap]
  heap[#heap] = nil
  local size = #heap
  if size > 0 then
    heap[1] = last
    local i = 1
    while true do
      local left, right = i * 2, i * 2 + 1
      local smallest = i
      if left <= size and heap[left].priority < heap[smallest].priority then smallest = left end
      if right <= size and heap[right].priority < heap[smallest].priority then smallest = right end
      if smallest == i then break end
      heap[i], heap[smallest] = heap[smallest], heap[i]
      i = smallest
    end
  end
  return top.node
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function key(x, y)
  return y * 100000 + x
end

function Astar.find(map, startX, startY, goalX, goalY, isBlocked)
  isBlocked = isBlocked or function(x, y) return not map:isWalkable(x, y) end
  if isBlocked(goalX, goalY) then return nil end

  local heap = {}
  local cameFrom = { [key(startX, startY)] = false }
  local costSoFar = { [key(startX, startY)] = 0 }
  heapPush(heap, { x = startX, y = startY }, 0)

  while #heap > 0 do
    local current = heapPop(heap)
    if current.x == goalX and current.y == goalY then
      local reversed = {}
      local cx, cy = goalX, goalY
      while true do
        reversed[#reversed + 1] = { x = cx, y = cy }
        local prev = cameFrom[key(cx, cy)]
        if not prev then break end
        cx, cy = prev.x, prev.y
      end
      local path = {}
      for i = #reversed, 1, -1 do
        path[#path + 1] = reversed[i]
      end
      return path
    end
    local currentCost = costSoFar[key(current.x, current.y)]
    for _, dir in ipairs(DIRS) do
      local nx, ny = current.x + dir[1], current.y + dir[2]
      if map:inBounds(nx, ny) and not isBlocked(nx, ny) then
        local nKey = key(nx, ny)
        local newCost = currentCost + 1
        if costSoFar[nKey] == nil or newCost < costSoFar[nKey] then
          costSoFar[nKey] = newCost
          local heuristic = math.abs(nx - goalX) + math.abs(ny - goalY)
          heapPush(heap, { x = nx, y = ny }, newCost + heuristic)
          cameFrom[nKey] = { x = current.x, y = current.y }
        end
      end
    end
  end
  return nil
end

return Astar
