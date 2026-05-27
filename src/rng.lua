-- Deterministic 64-bit PRNG (splitmix64). Same seed always yields the same
-- stream, independent of platform and of the global math.random state.

local Rng = {}
Rng.__index = Rng

local GOLDEN = 0x9E3779B97F4A7C15
local MIX1 = 0xBF58476D1CE4E5B9
local MIX2 = 0x94D049BB133111EB

function Rng.new(seed)
  return setmetatable({ state = math.tointeger(seed) or 0 }, Rng)
end

function Rng:nextUint()
  self.state = self.state + GOLDEN
  local z = self.state
  z = (z ~ (z >> 30)) * MIX1
  z = (z ~ (z >> 27)) * MIX2
  z = z ~ (z >> 31)
  return z
end

-- Inclusive integer in [lo, hi]. Modulo of a signed value by a positive span
-- lands in [0, span) under Lua's floor-division remainder.
function Rng:range(lo, hi)
  local span = hi - lo + 1
  return lo + self:nextUint() % span
end

function Rng:chance(numerator, denominator)
  return self:range(1, denominator) <= numerator
end

function Rng:pick(list)
  return list[self:range(1, #list)]
end

function Rng:serialize()
  return { state = self.state }
end

function Rng.deserialize(snapshot)
  return setmetatable({ state = snapshot.state }, Rng)
end

return Rng
