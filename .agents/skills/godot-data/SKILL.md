---
name: godot-data
description: Use when a Godot game defines items, enemies, levels, spells, dialogue or balance numbers as data, when choosing between custom Resources and JSON or CSV tables, when designers tune values in a spreadsheet, or when game data loads wrong, changes by itself or is missing from an exported build.
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
  `GetPropertyList()` entries whose usage has `PropertyUsageFlags.Storage` (this alone catches renamed properties)
- ids unique and matching `^[a-z0-9_]+$`; references resolve; no cycles where none belong (upgrade chains)
- ranges from the `PropertyHint.Range` hint strings; enums with `Enum.IsDefined`
- the game's balance rules from the GDD: damage rises with tier, drop weights sum above 0, every enemy beatable at the
  level's expected player power

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
  not exist, unknown columns (typos in a header), and a CSV still imported as a translation.
- Field rules: `type` (string, int, number, bool), `min`, `max`, `enum`, `pattern`, `ref`, `list` (`;` between values
  in a CSV cell), `optional`; `"extra": "allow"` on a table permits unlisted columns.
- Run it alone: `pwsh ci/godot/godot-ci.ps1 test -Project game -Runners data`.

## 5. Spreadsheets

- One direction only: the sheet, then an export (a script or a downloaded CSV) committed to the repository, then the
  game. Never hand-edit the export; commit it so a review shows every balance change.
- Keep derived columns (damage per second, time to kill) in the sheet; export only the inputs.
- Print a digest of all data tables in the game's log and in bug reports, so a report says which balance it ran.
