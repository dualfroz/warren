# Warren

Warren is a terminal roguelike written in plain Lua 5.4 with no dependencies. You go down ten
procedurally generated floors, take the Amulet of Warren from the deepest one and carry it back up
the stairs. Everything in a run comes from one seed: the floors, the monsters, the loot and every
dice roll. The same seed, class and mutators always play out the same way. The game runs in two
modes. The autopilot plays a run headlessly, which is useful for testing, replays and benchmarks.
Interactive mode reads typed commands from stdin. Between runs, a meta file keeps renown, perks,
achievements, a bestiary, a leaderboard and the graves of earlier characters.

## Features

**Dungeon**

- Ten floors by default. Each one is built from the world seed and its depth, using its own random
  number generator, and is cached once visited, so going back to a floor finds it exactly as you
  left it.
- Generators: rooms with L-shaped corridors, binary space partitioning, cellular-automata caves,
  drunkard's walk and a braided recursive-backtracker maze. A connectivity pass makes every floor
  cell reachable.
- Hand-authored prefab vaults, lever-gated treasure vaults, pressure-plate gates with pushable
  blocks, and secret doors that hide unreachable alcoves.
- Terrain and hazards: water, lava, chasms that drop you to the next floor, ice that keeps you
  sliding, and spreading fire and caustic gas. Water soaks you, which douses fire and makes
  lightning hit harder.
- Doors, locked doors with keys, and hidden traps (dart, poison, teleport, confuse, blind, stun)
  that you can detect and disarm.
- Floor weather (foggy, consecrated, infested), timed events (blood moon, rich veins, hush),
  depth-band biomes with native factions, and dark floors where your torch matters.
- Rift crossings into harder pocket floors that you can leave and come back to, and an optional
  horde arena with endless escalating waves.
- Diggable rock with a limited-use pick, including cave-ins and ore strikes.

**Character**

- Four classes: fighter, rogue, mage and ranger. Each has a starting bonus and its own skill tree
  of actives (cleave, second wind, poison blade, meditate, multishot) and passives (berserk,
  backstab, evasion, overload, mana shield, camouflage, trueshot).
- Experience and levels, skill points, and weapon proficiency that ranks up per weapon.
- A spellbook learned from tomes: magic missile, minor heal, cleansing ward, arcane shield, shock
  bolt, discord, confusing hex, veil of shadow, withering hex, polymorph, levitation and blink.
- Mana, hunger with food and corpses, a torch that burns down, carry weight with encumbrance tiers,
  sanity that drops from dread, and diseases that incubate, erupt and get worse in stages.
- Status effects: poison, burning, regeneration, haste, slow, strength, stun, confusion,
  blindness, weakness, discord, levitation and shields.

**Combat**

- An energy-based turn scheduler, where faster actors act more often and ties resolve the same
  way every time.
- Melee, bows with arrows, thrown weapons and potions, and a melee momentum combo.
- Elemental damage types (physical, fire, cold, poison, lightning, arcane) with immune, resist and
  weak tiers from monster profiles and from worn gear.
- Stealth: monsters start asleep, wake on noise or sight, hunt, lose track of you, search for you
  and fall asleep again. Noise spreads around corners but stops at walls, and attacks on sleeping
  monsters deal sneak damage.

**Items and crafting**

- Potions and scrolls with randomized appearances that you identify by using them or by reading
  a scroll of identify.
- Rolled affixes, cursed gear that binds when worn, durability and repair, item sets with
  bonuses that grow per piece, rune chains that form runewords, and unique artifacts.
- Essence crafting: forge gems, merge them into higher tiers, socket them, temper and enchant
  gear, and disenchant it back into essence.
- Alchemy: brew pairs of herbs at cauldrons, which can curdle into gas. Herbs come from the floor,
  from resource nodes and from carved corpses. Ore veins and gem seams run out and refill over
  time.
- Shops with prices that depend on your faction standing, selling, stealing, chests opened with
  keys or lockpicks, and bounty boards.

**Monsters**

- A data-driven bestiary of 18 wild species plus the shopkeeper, with AI behaviours (chase, pack, ranged, flee, erratic,
  tunnel) and species abilities: summoning, curses, healing, rallying, shrieks, stealing,
  splitting, regeneration, breath weapons and death bursts.
- Elite affixes, three bosses with an enrage phase and a desperation nova, mimics, infighting
  between rival factions, polymorph, and a nemesis that follows you between floors and grows
  stronger each time it escapes.
- Factions with reputation: killing members angers a faction, tribute calms it, and tribal
  factions leave you alone until provoked.
- Captives: net a battered monster, then ransom it, sell it or interrogate it.

**Allies**

- Companions bonded from charms, which level up and evolve.
- Hired mercenaries who need wages and loyalty.
- Reanimated thralls raised from fresh corpses at a cost in sanity.

**Meta-progression and run tooling**

- Renown earned per run, permanent perks, achievements, renown titles, win and loss streaks, and
  run analytics.
- Ascension mutators that unlock from your history and raise the risk in exchange for more
  renown, plus daily challenge presets that fix a class, a set of mutators and a seed.
- A bestiary that lasts across runs, a top-N leaderboard, and graves of dead characters that can
  show up in later runs and hold a vengeful shade guarding part of the lost hoard.
- Versioned, checksummed save files (FNV-1a) with migration of older formats, so a truncated or
  tampered save fails with a clear error.
- Morgue files written at the end of a run, deterministic replay verification, and CSV export of
  the leaderboard and the bestiary.

## Requirements

Lua 5.4. Nothing else is needed to play. The test suite also runs the real entry point through
`io.popen`, so the CLI tests need a POSIX shell.

## Running

All flags are optional. Without `--auto` or `--play`, the game prints the starting floor and exits.

```sh
lua warren.lua --seed 42 --auto 50
lua warren.lua --seed 3 --class fighter --play
lua warren.lua --seed 7 --auto 30 --save run.sav
lua warren.lua --load run.sav --play
lua warren.lua --seed 3 --class ranger --auto 50
lua warren.lua --seed 3 --auto 200 --morgue run.morgue
lua warren.lua --seed 3 --auto 200 --verify
lua warren.lua --challenge 42 --auto 200
lua warren.lua --meta legacy.sav --seed 3 --auto 200
lua warren.lua --meta legacy.sav --seed 3 --auto 200 --mutators famine,nightblind
lua warren.lua --meta legacy.sav --buy vigor
lua warren.lua --meta legacy.sav --report
lua warren.lua --meta legacy.sav --export-csv runs.csv
lua warren.lua --meta legacy.sav --export-compendium bestiary.csv
```

### Command line flags

| Flag | Meaning |
|---|---|
| `--seed <n>` | World seed. The default comes from the current time (low 16 bits). |
| `--class <name>` | `fighter`, `rogue`, `mage` or `ranger`. An unknown name is ignored. |
| `--auto <n>` | Let the autopilot play up to `n` turns. It stops early on death. |
| `--play` | Start interactive mode after any `--auto` turns. |
| `--save <file>` | Save the run when the program exits. |
| `--load <file>` | Resume a saved run instead of starting a new one. |
| `--meta <file>` | Meta-progression file, created if missing. With `--auto`, a finished run banks renown, achievements and a leaderboard entry, and a death leaves a grave. |
| `--buy <perk>` | Spend renown on a perk (`vigor`, `purse`, `focus`, `keeneye`, `tough`). Needs `--meta`. Exits with status 1 if the purchase fails. |
| `--report` | Print renown, title, streaks, perks, challenges, achievements, mutators, bestiary and leaderboard. |
| `--mutators <a,b>` | Ascension mutators for this run: `bloodbound`, `famine`, `nightblind`, `frail`, `glasscannon`. Only mutators already unlocked in the meta file take effect. |
| `--challenge <day>` | Use the daily challenge preset for a day index. This replaces seed, class and mutators. After an `--auto` run it reports whether the run honored the challenge. |
| `--morgue <file>` | Write a morgue report if the run ended in death or victory. |
| `--verify` | Replay the seed for the same number of `--auto` turns and confirm the outcome matches. Only works for runs without `--meta` and without `--load`. |
| `--export-csv <file>` | Write the meta leaderboard as CSV. |
| `--export-compendium <file>` | Write the meta bestiary as CSV. |

Unknown flags are ignored.

## How to play

In `--play` mode the game draws the floor and a status panel. You type one command per line and
press Enter. `quit`, `exit` or `q` leaves the loop without ending the run, so `--save` still writes
the current state. The loop also stops at end of input, which means you can pipe in a script of
commands. A command that fails, such as a typo, walking into a wall or a bad argument, does not
use up a turn. Informational commands never take a turn.

### Commands

| Command | Effect |
|---|---|
| `north` `south` `east` `west` `ne` `nw` `se` `sw` (or `n` `s` `e` `w`) | Move one step. Moving into a monster attacks it, moving into a block pushes it, and moving onto a lever pulls it. |
| `attack <dir>` | Attack in a direction. |
| `wait`, `z`, `.` | Pass a turn. |
| `pickup`, `g` | Pick up what lies here. Shop wares are bought automatically if you can afford them. |
| `explore` | Walk toward unexplored ground until something interrupts you. |
| `rest` | Rest until healed. Stops when a monster comes into view or you take damage. |
| `travel down`, `travel up` | Walk to the down or up stairs. |
| `descend`, `>` / `ascend`, `<` | Take the stairs. Climbing out of depth 1 with the amulet wins the game. |
| `inventory`, `i` | List what you carry, numbered. |
| `use <n>`, `u <n>` | Use, drink, read, equip or eat inventory item `n`. |
| `drop <n>` / `sell <n>` | Drop an item, or sell it to the shop you stand in. |
| `throw <n> [target]` | Throw an item at a monster. |
| `fire [target]` | Shoot the equipped bow. |
| `cast <spell> [target]` | Cast a learned spell (`missile`, `heal`, `cleanse`, `shield`, `shock`, `discord`, `confuse`, `blind`, `weaken`, `polymorph`, `levitate`, `blink`). |
| `useskill <skill> [target]` | Use an active skill. `multishot` takes up to two targets. |
| `learn <skill>` | Spend a skill point. |
| `capture <n> [target]` | Throw net `n` at a battered monster. |
| `open`, `pray`, `quest` | Open the chest, pray at the shrine, or take the bounty here. |
| `butcher`, `raise`, `scavenge` | Eat, reanimate or carve the corpse underfoot. |
| `harvest` | Harvest the resource node underfoot. |
| `ransom`, `sellcaptive`, `interrogate` | Deal with a captive here. |
| `appease <faction>` | Pay gold to improve your standing with a faction. |
| `dig <dir>` / `disarm <dir>` | Dig with the equipped pick, or disarm a trap you have detected. |
| `enterrift`, `exitrift` | Cross a rift (needs a rift shard) or return from it. |
| `horde` | Enter the horde arena. |
| `steal`, `dismiss` | Steal the ware underfoot, or release your hired mercenary. |
| `forge <element>` | Forge a gem: `fire`, `frost`, `shock` or `venom`. |
| `merge <a> <b>`, `brew <a> <b>` | Merge two gems, or brew two herbs at a cauldron. |
| `socket <target> <gem>`, `socketrune <target> <rune>` | Socket a gem or a rune. The target is `weapon`, `armor` or an item number. |
| `temper <target>`, `enchant <target> <affix>`, `disenchant <target>` | Essence crafting. |
| `repair <slot>` | Repair `weapon`, `armor` or `bow` for gold. |
| `look`, `l` | Number the visible monsters. |
| `examine <n>`, `examine monster <n>`, `x` | Inspect an item or a visible monster. |
| `status`, `help` | Show your stats, or the command list. |

`[target]` is the number `look` gives a monster. Leave it out to target the nearest visible
monster.

### Map

| Glyph | Meaning |
|---|---|
| `@` | You |
| `#` `.` | Wall, floor |
| `<` `>` | Stairs up, stairs down |
| `+` `'` `x` | Closed, open and locked door |
| `^` | Revealed trap |
| `~` `}` `V` `-` `:` | Water, lava, chasm, ice, rubble |
| `` ` `` `,` | Fire, gas |
| `H` `I` `K` | Lever, pulled lever, vault door |
| `0` `;` `8` `9` | Block, pressure plate, closed gate, open gate |
| `_` `U` `N` `E` | Shrine, cauldron, open bounty board, claimed bounty board |
| `B` `u` `A` | Chest, emptied chest, rift |
| `O` `S` | Ore vein, gem seam |
| `X` `\|` | Corpse, grave marker |
| `!` `?` `&` | Potion, scroll, tome |
| `/` `)` `{` `[` | Weapon, bow, arrows, armor |
| `=` `"` `]` | Ring, amulet, companion charm |
| `$` `*` `%` `Y` | Gold, gem, food, herb |
| `(` `J` `\` `t` | Key, lockpick, miner's pick, trap kit |
| `F` `P` `R` `1` | Net, mercenary contract, rift shard, rune |

### Monsters and allies

As in NetHack, lowercase letters are ordinary creatures and uppercase letters are the big or rare
ones.

| Glyph | Meaning |
|---|---|
| `r` `v` `k` `g` | Rat, cave bat, kobold, goblin |
| `a` `o` `w` `m` | Skeleton archer, orc, cave wretch, dark mage |
| `z` `j` `f` `s` | Shambling zombie, gelatinous slime, footpad, goblin shaman |
| `n` `c` `b` `h` | Necromancer, dark cleric, banshee, shopkeeper |
| `i` | Vengeful shade rising from a grave |
| `T` `C` `D` `M` | Troll, orc chieftain, young dragon, revealed mimic |
| `W` `L` `Q` | Bosses: the Orc Warlord, the Lich, the Bone Queen |
| `d` `e` `G` | Companions: hunting hound, hearth sprite, clay golem |
| `l` `y` `p` | Mercenaries: sellsword, skirmisher, field medic |
| `Z` | Reanimated thrall |

Every glyph in both tables means exactly one thing. A companion keeps its glyph when it evolves,
and a polymorphed creature takes the glyph of its new form. A hidden mimic copies the glyph of the
chest, gold, tome or armor it pretends to be. Unexplored cells are blank. Explored cells that are
out of sight show only terrain.

## Tests

```sh
lua tests/run.lua                 # every suite
lua tests/run.lua combat cli      # selected suites only
```

The runner has no dependencies. It prints every test and finishes with a line in the form
`N tests, M asserts, F failed`. It exits with status 0 only when every assertion passes, and it
lists the failed assertions otherwise. Tests use fixed seeds, so a regression shows up as a
specific failed assertion and not as a flaky one.

- `tests/run.lua` holds the ordered list of suites and the runner.
- `tests/helpers.lua` holds the assertions (`ok`, `eq`, `contains`) and shared fixtures such as
  hand-built arenas and staged games.
- `tests/suites/<area>.lua` holds one suite per module or feature. Most suites match a file in
  `src/` (for example `combat`, `companions`, `savegame`). `cli` drives `warren.lua` itself,
  `autopilot` covers the headless player, and `game` covers the turn loop, travel and stairs.

To add a test, add a `function tests.<name>()` to the matching suite. To add a suite, create the
file and add its name to the list in `tests/run.lua`.

## Project layout

```
warren.lua          command line entry point: flags, interactive loop, meta bookkeeping
src/game.lua        turn orchestration, autopilot, player actions, save and load
src/commands.lua    text command parser used by interactive mode
src/builder.lua     fills a generated map with stairs, doors, monsters, loot and features
src/gen/            map generators (rooms, bsp, cellular, drunkard, maze, prefab) and connectivity
src/*.lua           one module per system (combat, spells, crafting, companions, meta, ...)
tests/              test runner, helpers and per-area suites
```

## Limitations

- Terminal ASCII output only, with no colour and no curses. Interactive mode reads whole lines,
  so every command needs Enter.
- Replay verification (`--verify`) covers only runs without meta-progression, because perks and a
  partly filled bestiary change a run in ways the seed alone does not capture.
- A run is recorded into the meta file only when it was played with `--auto` and ended in death
  or victory during that invocation.
- Unknown command line flags are ignored without a warning.

## License

MIT, see [LICENSE](LICENSE).
