---
name: godot-data
description: Use when a Godot game defines items, enemies, levels, spells, dialogue or balance numbers as data, when choosing between custom Resources and JSON or CSV tables, when designers tune values in a spreadsheet, when objects placed in level scenes (AI points, interactables, zip lines) must keep obeying gameplay rules, or when game data loads wrong, changes by itself or is missing from an exported build.
---

# Data-driven design in Godot 4 (C#)

Keep what designers tune (numbers, lists, ids, references between them) out of code, check it in CI like code, and load
it the same way in the editor, in tests and in the exported game. Every behaviour below was measured on Godot 4.7.2
mono; sources: `${CLAUDE_PLUGIN_ROOT}/docs/data.md`.

## 1. Resources or tables

| | `[GlobalClass]` Resources (`.tres`) | JSON or CSV tables |
|---|---|---|
| Best for | A few hand-tuned items tied to art and scenes | Many rows of numbers, tuned in a spreadsheet |
| Editing | The inspector | A spreadsheet, exported to the repository |
| Reviewing a change | Readable diffs | Readable diffs; one row per item |
| Checked by the kit | Section 3 | The `data` runner (section 4) |
| Mods and downloads | Never: a `.tres` runs scripts embedded in it | Yes, validated (`godot-modding`) |

Either way: every definition has a stable string `Id` (not a file name, not an index); references name ids; one loader,
used by the game, tests and CI, reports every problem at once instead of stopping at the first.

Content edited often (maps, waves, dialogue) deserves its own editor, a `@tool` script or a small plugin, so people
other than the programmer can make it: Toru Hidaka's graphics, map and sound utilities let others make games at Enix
(*Untold History*).

## 2. The traps of custom Resources

- **A loaded Resource is one shared object.** Two enemies with `[Export] Weapon` set to `axe.tres` hold the same
  object; `a.Weapon.Damage += 5` changes `b` and every later `GD.Load("res://axe.tres")`. Definitions are read-only at
  run time; per-instance state goes in a plain C# object built from the definition (`new WeaponState(def)`).
- `ResourceLocalToScene` copies only when a scene is instantiated; two `GD.Load` calls still share.
- `Duplicate(true)` keeps external sub-resources (another `.tres`) shared and drops fields that are not `[Export]`ed;
  `Duplicate()` shares arrays. `DuplicateDeep(Resource.DeepDuplicateMode.All)` copies external ones too. Cost: 45 µs for
  a small resource, 1.5 ms for a large one, against 5 µs for `new`; never duplicate per bullet.
- **Renaming or removing an `[Export]` property loses data silently.** The old `.tres` loads with no warning (not even
  with `--verbose`), the property gets its C# default, and the next save erases the old value. When renaming, edit
  every `.tres` in the same commit (the keys are plain text) and check with the test below.
- **Renaming a class or its file**: move the `.cs.uid` with the `.cs` (`git mv` both); a `.tres` without a `uid=` (any
  written by `ResourceSaver.Save` in a running game) then fails to load and returns null.
- **Values equal to the default are not written.** Changing a C# default silently changes every file that had it. Give
  balance numbers no meaningful default (0, then validate).
- **Inspector hints are not validation.** A hand-edited `.tres` loaded `Hp = 999` past `PropertyHint.Range "0,100"`, an
  enum value 7 that does not exist, and `Speed = "fast"` on a float as 0, all without an error.
- **Hot reload**: `GD.Load` returns the cached object after the file changes;
  `ResourceLoader.Load(path, "", ResourceLoader.CacheMode.Replace)` reloads into the same object, so every holder sees
  the new values. A debug "reload data" key can do this for changed files.

## 3. Tests for Resources (in the game's test project)

- every `.tres` under the data folders loads, non-null, of the expected class
- every key in each `.tres` is a stored property of its class: parse the keys from the text and compare with
  `GetPropertyList()` entries whose usage has `PropertyUsageFlags.Storage` (this alone catches renamed properties); the
  kit's `validate` runner now does this for every `.tres` (`keeps spead, which EnemyStats no longer has`)
- ids unique and matching `^[a-z0-9_]+$`; references resolve; no cycles where none belong (upgrade chains)
- ranges from the `PropertyHint.Range` hint strings; enums with `Enum.IsDefined`
- the game's balance rules from the GDD: damage rises with tier, drop weights sum above 0, every enemy beatable at the
  level's expected player power
- a cost curve: one formula, kept in one place, gives each item's benefits minus its costs; the test fails on any item
  outside a stated band (the method of a game balance course's GDC talk)
- chance tables: no negative weight, every probability within 0 and 1, the exclusive outcomes summing to exactly 1 (most
  probability mistakes fail one of these); where the exact chance of an outcome is known, the seeded rate of `godot-procgen`'s
  "Chances come out right" test must agree with it

## 4. Tables: JSON and CSV

- **A `.csv` is imported as a translation by default**, even a table of enemies, and then the file itself is not in the
  exported game. In the Import dock choose Import As > Keep File and commit its `.import` (`importer="keep"`); read it
  with `FileAccess.GetCsvLine()`, which handles quoted commas.
- `.json` is exported as is. `.txt` and `.yaml` are exported only if the export preset's include filter names them.
- A `.tres` is converted to binary in an export and appears as `name.tres.remap`, so a `DirAccess` scan for `*.tres`
  finds nothing there. List with `ResourceLoader.ListDirectory("res://data")` and load by path.
- Godot's `Json` returns every number as a double (`10` is `10.0`; ids above 2^53 are corrupted), accepts trailing commas
  and keeps the last of duplicate keys. Parse tables in C# with `System.Text.Json` into records; set
  `UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow` so a misspelt field fails.
- Parse numbers with `CultureInfo.InvariantCulture`: `float.Parse("0.5")` gives 5 on a German system, inside Godot too,
  and CI machines never show it; the `architecture` runner warns (`culture-parse`).

### The `data` runner

`data.json` in the project describes each table; the `data` runner (picked automatically when the file exists) checks
every row without Godot and writes one JUnit case per table:

```json
{ "tables": {
    "items":   { "file": "data/items.json", "id": "id",
                 "fields": { "price": { "type": "int", "min": 0 }, "rarity": { "enum": ["common", "rare"] } } },
    "enemies": { "file": "data/enemies.csv", "id": "id",
                 "fields": { "hp": { "type": "int", "min": 1 }, "drops": { "ref": "items", "list": true },
                             "boss": { "type": "bool", "optional": true } } } } }
```

- It catches: duplicate or missing ids, wrong types, values out of range or not in the enum, references to ids that do
  not exist, unknown columns (typos in a header), and a CSV still imported as a translation; a mistyped id, enum value,
  column or table comes with the near name ("did you mean 'mining'?").
- Field rules: `type` (string, int, number, bool), `min`, `max`, `enum`, `pattern`, `ref`, `list` (`;` between values
  in a CSV cell), `optional`, `acyclic` (on a `ref` to its own table: prerequisites that loop, as in a tech tree,
  `godot-algorithms`); `"extra": "allow"` on a table permits unlisted columns.
- Across rows: `"totals"` on a table (what a zone's quests give must reach its next level: `godot-progression`) and
  `"names"` at the top level (misspelt proper nouns in dialogue, translations and scenes: `godot-narrative`).
- Dialogue rules: a table of `"kind": "responses"` (`godot-narrative` section 4); `"type": "criteria"` checks the same
  criteria grammar (`health<25;!seen_tank`) in any table, such as quest or unlock conditions.
- Run it alone: `pwsh ci/godot/godot-ci.ps1 test -Project game -Runners data`.
- Puzzle levels: `godot-game-design` section 6 has a `levels` table that requires a one-sentence solution and a purpose
  for every level.

## 5. Spreadsheets

- One direction only: the sheet, then an export (a script or a downloaded CSV) committed to the repository, then the
  game. Never hand-edit the export; commit it so a review shows every balance change.
- Keep derived columns (damage per second, time to kill) in the sheet; export only the inputs.
- Feature switches are data too, so a feature can be turned off for a test (DayZ). Values tuned around a bug break when
  it is fixed: retune after fixes, and keep whole-system regression runs (IL-2).
- Print a digest of all data tables in the game's log and in bug reports, so a report says which balance it ran.
- Balance downloaded from a server (rebalancing without a patch; a Sony online consultant's GDC advice) is data only:
  JSON or CSV parsed into the same records and checked by the same rules, never a `.tres`, a script or an expression,
  which would be a way in for an attacker. The shipped tables stay the fallback, so the game plays offline with
  whatever version it has; apply a download between missions or runs, never mid-mission; write its version into saves.

## 6. Placed objects: every one, every run

Anyone breaks placed content, often far from where they worked: a prop's collision fix moves AI points off the navmesh
in every level that uses the prop, a navmesh change drops the slopes, a code change lowers a limit. Check every placed
node of every level in each test run instead of by hand (Assassin's Creed Origins: 228 zip lines at two minutes each is
a tester's full day; `${CLAUDE_PLUGIN_ROOT}/docs/gdc/assassins-creed-origins-world-data.md`).

Copy `${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/placement_check.gd` into the game's test folder and call it from a GUT
test (its header has the code; a C# game ports the rules). It loads each level, waits for navigation, checks nodes by
group and fails once, one line per finding: scene, node path, position, rule, measured value and limit.

| Group | Rule | Passes when |
|---|---|---|
| `ai_point` | `navmesh_below` | navmesh is at most 0.5 m straight below |
| | `path_to_link` | a path reaches each node in its `links` metadata |
| `interactable` | `ground_in_reach` | a ray down hits ground within the player's reach |
| `zipline` | `zipline_clear` | a capsule swept under the rope to its `End` child hits nothing |
| | `zipline_angle` | the rope is no steeper than the movement code allows |
| `landmark` | `landmark_still` | it is no moving body and did not move in 30 physics frames |
| | `landmark_seen` | it is in view ahead from at least two separate stretches of the `route` paths |
| `route` (a `Path3D`) | `landmark_ahead` | walked each way (metadata `one_way` skips the way back), a landmark is in view ahead on a quarter of it |

- The wayfinding rules and why they matter: `godot-game-design` section 7. They aim at a landmark's `Marker3D` children
  (the top of a tower), from `eye_height` within `view_fov`; only what has collision hides a landmark.
- **Limits come from gameplay code**: `check.reach = Player.REACH` with `const Player := preload("res://player.gd")`.
  A copied number keeps passing after the code changes; yesterday's valid zip line must fail the day the limit drops.
- **A bug found once becomes a rule for its whole type**: one torch out of reach means a check of every torch.
- **Prove each rule on a broken fixture before trusting it.** A false positive sends someone looking for nothing, and
  they stop reading the report. Two traps the kit's fixture caught: before the map syncs, `map_get_closest_point`
  returns (0, 0, 0), so a probe at the origin looks ready early (wait for `map_get_closest_point_owner` to be valid);
  `map_get_path` to another navmesh island returns a path to the nearest reachable point, so compare where it ends.
- **Exemptions are visible**: node metadata `placement_skip = {"zipline_clear": "the crate breaks"}`; the summary lists
  each with its reason, and one without a reason is a finding.
- **One summary with the change per type since the last run** (`counts_file`; keep the file between runs). The talk's
  most useful line was "ladders +500", seen before anyone complained.
- On 4.7.2 headless, navigation answered after 9 to 11 physics frames for the first level of a GUT run and 3 or 4 for
  the next; the helper polls, capped. The checks take about 10 ms per 1,000 nodes.
- A check at commit time does not replace the full run: data fine on day one breaks on day ten through another change.
- Run it: `pwsh ci/godot/godot-ci.ps1 test -Project game -Runners gut -Filter test_every_level`.
