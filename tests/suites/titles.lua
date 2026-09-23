local helpers = require("helpers")
local Titles = require("titles")

local ok, eq = helpers.ok, helpers.eq

local tests = helpers.suite()

function tests.titlesForRenownNeverReturnsNilForAnyNonNegativeRenown()
  for _, renown in ipairs({ 0, 1, 49, 50, 350, 1499, 1500, 100000 }) do
    ok(Titles.forRenown(renown) ~= nil, "renown " .. renown .. " always resolves to some title")
  end
end

function tests.titlesForRenownWalksTheLadderFromTheBottomUp()
  eq(Titles.forRenown(0), "Whelp", "zero renown starts at the very bottom of the ladder")
  eq(Titles.forRenown(49), "Whelp", "one short of a threshold stays on the lower title")
  eq(Titles.forRenown(50), "Delver", "landing exactly on a threshold claims that title")
  eq(Titles.forRenown(349), "Warden", "just under the next threshold keeps the current title")
  eq(Titles.forRenown(1500), "Undying", "the exact top threshold claims the top title")
  eq(Titles.forRenown(999999), "Undying", "renown far past the ladder still caps at the top title")
end

function tests.titlesToNextCountsDownToTheNextThresholdAndNilsOutAtTheTop()
  eq(Titles.toNext(0), 50, "starting from zero needs exactly the first threshold's renown")
  eq(Titles.toNext(45), 5, "five renown short of the first threshold reports exactly five")
  eq(Titles.toNext(50), 100, "landing on a threshold reports the gap to the next one, not zero")
  eq(Titles.toNext(1500), nil, "sitting at the top threshold has no further tier to climb toward")
  eq(Titles.toNext(50000), nil, "renown past the top of the ladder also has nothing left to climb toward")
end

return tests
