local helpers = require("helpers")
local Rng = require("rng")
local Entity = require("entity")
local Scheduler = require("scheduler")
local MessageLog = require("messagelog")

local ok, eq = helpers.ok, helpers.eq

local tests = helpers.suite()

function tests.rngDeterminism()
  local a, b = Rng.new(12345), Rng.new(12345)
  for i = 1, 100 do
    eq(a:nextUint(), b:nextUint(), "rng stream matches at step " .. i)
  end
  local c = Rng.new(99)
  ok(a:nextUint() ~= c:nextUint(), "different seed diverges")
  local low, high, within = math.huge, -math.huge, true
  local ranged = Rng.new(7)
  for _ = 1, 500 do
    local v = ranged:range(3, 9)
    if v < 3 or v > 9 then within = false end
    low, high = math.min(low, v), math.max(high, v)
  end
  ok(within, "range stays inside bounds")
  eq(low, 3, "range reaches its low bound")
  eq(high, 9, "range reaches its high bound")
end

function tests.scheduler()
  local player = Entity.new({ id = 0, x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 10, attack = 1, defense = 0, speed = 100 })
  local slow = Entity.new({ id = 1, x = 2, y = 1, glyph = "o", name = "orc", kind = "monster", hp = 10, attack = 1, defense = 0, speed = 100 })
  local fast = Entity.new({ id = 2, x = 3, y = 1, glyph = "v", name = "bat", kind = "monster", hp = 10, attack = 1, defense = 0, speed = 200 })
  local stub = { player = player }
  function stub:currentEntities() return { slow, fast } end
  local function run()
    player.energy, slow.energy, fast.energy = 0, 0, 0
    local tally = { [0] = 0, [1] = 0, [2] = 0 }
    local firstId
    for step = 1, 60 do
      local actor = Scheduler.next(stub)
      if step == 1 then firstId = actor.id end
      tally[actor.id] = tally[actor.id] + 1
      Scheduler.spend(actor)
    end
    return tally, firstId
  end
  local tally, firstId = run()
  eq(firstId, 2, "the fastest actor acts first")
  ok(tally[2] > tally[0], "a double-speed actor acts more often than the player")
  eq(tally[0], tally[1], "equal-speed actors act equally often")
  local tally2 = run()
  ok(tally[0] == tally2[0] and tally[2] == tally2[2], "scheduling is deterministic")
end

function tests.messageLog()
  local log = MessageLog.new(3)
  for i = 1, 5 do log:add("line " .. i) end
  eq(#log.lines, 3, "the log keeps only its capacity")
  eq(log:last(), "line 5", "the newest line is retained")
  local recent = log:recent(2)
  eq(recent[1], "line 4", "recent returns the tail in order")
  eq(recent[2], "line 5", "recent ends on the newest line")
end

return tests
