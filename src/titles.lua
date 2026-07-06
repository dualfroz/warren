-- Renown-gated titles: a flavor rank meta.lua's own banked renown climbs
-- through, one tier per crossed threshold, entirely separate from a
-- character's class - a title describes how far this save file's whole
-- history has come, not what any single run's build looked like.

local Titles = {}

Titles.LADDER = {
  { threshold = 0, name = "Whelp" },
  { threshold = 50, name = "Delver" },
  { threshold = 150, name = "Warden" },
  { threshold = 350, name = "Vanquisher" },
  { threshold = 700, name = "Warren Lord" },
  { threshold = 1500, name = "Undying" },
}

-- The highest title whose threshold `renown` clears, walked from the top of
-- the ladder down so a renown total that clears several thresholds at once
-- always resolves to the hardest-earned name rather than the first match.
function Titles.forRenown(renown)
  for i = #Titles.LADDER, 1, -1 do
    if renown >= Titles.LADDER[i].threshold then return Titles.LADDER[i].name end
  end
  return Titles.LADDER[1].name
end

-- Renown still needed to clear the next threshold above `renown`, or nil
-- once renown has already cleared the top of the ladder and there is
-- nothing left to climb toward.
function Titles.toNext(renown)
  for _, tier in ipairs(Titles.LADDER) do
    if renown < tier.threshold then return tier.threshold - renown end
  end
  return nil
end

return Titles
