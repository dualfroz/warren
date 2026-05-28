-- Item identification. At world creation each potion and scroll type is dealt a
-- random appearance (a colour or a nonsense label) by shuffling fixed pools with
-- the world rng. Until a type is known the player only sees its appearance; using
-- an item, or reading a scroll of identify, reveals the type for good.

local Items = require("items")

local Identify = {}

local potionLooks = {
  "ruby", "azure", "cloudy", "fizzy", "smoky", "golden", "murky", "viscous",
}
local scrollLooks = {
  "XYZZY", "ELBERETH", "ZELGO KAI", "JUYED AWK", "VE FORBRYDERNE",
  "FOOBIE BLETCH", "GHOTI", "NR 9",
}

local function shuffled(pool, rng)
  local copy = {}
  for i = 1, #pool do copy[i] = pool[i] end
  for i = #copy, 2, -1 do
    local j = rng:range(1, i)
    copy[i], copy[j] = copy[j], copy[i]
  end
  return copy
end

function Identify.new(rng)
  local appearance = {}
  local potionOrder = shuffled(potionLooks, rng)
  for i, entry in ipairs(Items.potionTypes) do
    appearance[Items.POTION .. "/" .. entry.effect] = potionOrder[i] .. " potion"
  end
  local scrollOrder = shuffled(scrollLooks, rng)
  for i, entry in ipairs(Items.scrollTypes) do
    appearance[Items.SCROLL .. "/" .. entry.effect] = "scroll labeled " .. scrollOrder[i]
  end
  return { appearance = appearance, known = {} }
end

function Identify.isConcealable(item)
  return item.kind == Items.POTION or item.kind == Items.SCROLL
end

function Identify.reveal(state, item)
  state.known[Items.typeId(item)] = true
end

function Identify.isKnown(state, item)
  return state.known[Items.typeId(item)] == true
end

function Identify.label(state, item)
  if not Identify.isConcealable(item) then return item.name end
  local id = Items.typeId(item)
  if state.known[id] then return item.name end
  return state.appearance[id] or item.name
end

-- Reveals the first still-unknown concealable item in an inventory. Returns the
-- item whose type became known, or nil when everything is already identified.
function Identify.revealFirstUnknown(state, inventory)
  for _, item in ipairs(inventory) do
    if Identify.isConcealable(item) and not Identify.isKnown(state, item) then
      Identify.reveal(state, item)
      return item
    end
  end
  return nil
end

return Identify
