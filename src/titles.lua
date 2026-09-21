local Titles = {}

Titles.LADDER = {
  { threshold = 0, name = "Whelp" },
  { threshold = 50, name = "Delver" },
  { threshold = 150, name = "Warden" },
  { threshold = 350, name = "Vanquisher" },
  { threshold = 700, name = "Warren Lord" },
  { threshold = 1500, name = "Undying" },
}

function Titles.forRenown(renown)
  for i = #Titles.LADDER, 1, -1 do
    if renown >= Titles.LADDER[i].threshold then return Titles.LADDER[i].name end
  end
  return Titles.LADDER[1].name
end

function Titles.toNext(renown)
  for _, tier in ipairs(Titles.LADDER) do
    if renown < tier.threshold then return tier.threshold - renown end
  end
  return nil
end

return Titles
