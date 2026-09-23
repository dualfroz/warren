local scriptDir = arg[0]:match("^(.*)[/\\]") or "."
package.path = scriptDir .. "/../src/?.lua;" .. scriptDir .. "/?.lua;" .. package.path

local helpers = require("helpers")

local suites = {
  "core", "map", "combat", "items", "status", "generation", "builder", "ai", "traps", "effects",
  "hazards", "shrines", "autopilot", "progression", "spells", "throwing", "ranged", "abilities",
  "savegame", "game", "shop", "classes", "skills", "crafting", "alchemy", "nodes", "corpses",
  "hunger", "reanimation", "scavenging", "companions", "disease", "artifacts", "bosses", "quests",
  "meta", "resistances", "factions", "encumbrance", "render", "terrain", "elites", "vaults",
  "runewords", "atmosphere", "biomes", "stealth", "compendium", "sets", "mimics", "curses",
  "momentum", "conductivity", "digging", "sanity", "events", "graves", "proficiency", "ascension",
  "durability", "secrets", "chests", "mercenaries", "morgue", "leaderboard", "replay",
  "challenges", "analytics", "titles", "export", "streaks", "nemesis", "infighting", "polymorph",
  "blocks", "noise", "captives", "horde", "branches", "phases", "commands", "examine", "text", "cli",
}

local known = {}
for _, name in ipairs(suites) do known[name] = true end

local selected = {}
for i = 1, #arg do
  if not known[arg[i]] then
    io.stderr:write("unknown suite: " .. arg[i] .. "\n")
    os.exit(2)
  end
  selected[arg[i]] = true
end

local testCount = 0
for _, suiteName in ipairs(suites) do
  if next(selected) == nil or selected[suiteName] then
    local tests = dofile(scriptDir .. "/suites/" .. suiteName .. ".lua")
    io.write(suiteName, "\n")
    for _, name in ipairs(helpers.testNames(tests)) do
      tests[name]()
      testCount = testCount + 1
      io.write(string.format("  %-26s ok\n", name))
    end
  end
end

io.write(string.format("\n%d tests, %d asserts, %d failed\n", testCount, helpers.passed + helpers.failed, helpers.failed))
if helpers.failed > 0 then
  io.write("FAILURES:\n")
  for _, name in ipairs(helpers.failures) do
    io.write("  - " .. name .. "\n")
  end
  os.exit(1)
end
os.exit(0)
