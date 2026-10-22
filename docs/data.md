# Game data: sources and measurements

The research behind the `godot-data` skill, the `data` runner (`ci/godot/lib/Data.ps1`) and the `culture-parse`
architecture rule, gathered on 2026-10-21. It draws on Godot's documentation and the 4.7.2 class reference, studio
devlogs and talks. Tests ran on Linux x86_64 (4 cores), .NET SDK 8.0.131 (runtime 8.0.31) and Godot 4.7.2 mono and
standard, with C# `[GlobalClass]` Resources saved, edited by hand and reloaded, and a project exported with
`--export-release Linux`. Marks: **tested** means run here, **doc** means stated in documentation or a published talk,
and **unconfirmed** means not verified.

## Sources

| Source | What it gave |
|---|---|
| [Godot: resources](https://docs.godotengine.org/en/latest/tutorials/scripting/resources.html) | "Upon exporting a game, Godot serializes resource files as binary files (*.res)" |
| [Godot: exporting projects](https://docs.godotengine.org/en/latest/tutorials/export/exporting_projects.html) | The include filter "allows non-resource files such as .txt, .json and .csv to be exported" |
| [Godot: troubleshooting physics](https://docs.godotengine.org/en/latest/tutorials/physics/troubleshooting_physics_issues.html) | "Since resources are shared by default..." |
| GodotSharp.xml (4.7.2), `Resource.Duplicate` | A sub-resource "will only be duplicated if it's local" |
| [Orbitect: spreadsheets and JSON](https://www.gamedeveloper.com/programming/orbitect-spreadsheets-and-json), [Balancing with spreadsheets](https://bugnet.io/blog/balancing-your-game-with-spreadsheets) (search summaries) | Sheet exported to JSON by script; derived columns stay in the sheet |
| [CastleDB](http://castledb.org) (search summary) | A "structured static database": a model per sheet, references between sheets, one line-based JSON file that merges |
| Scott Bilas, [A Data-Driven Game Object System](https://www.sebaslab.com/wp-content/uploads/2022/07/data-driven-game-object-system1.pdf) (GDC 2002, Dungeon Siege) | Objects assembled from data, ">7300 unique object types" |
| Hades data tables ([Nexus](https://www.nexusmods.com/hades/mods/52/), [sgg-mod-format](https://github.com/MagicGonads/sgg-mod-format/wiki/Import-Type:-LUA)) | Data as Lua tables that mods patch by merging |
| Factorio [FFF #55](https://factorio.com/blog/post/fff-55), [FFF #47](https://factorio.com/blog/post/fff-47) | A checksum of the state every tick; desyncs are "typically just a value of one variable" |
| Asset Library: [Edit Resources as Table 2](https://godotengine.org/asset-library/asset/edit/16000), [CSV Data Importer](https://godotengine.org/asset-library/asset/1120) | Editor tools for tables (not tested) |

## Custom Resources (tested)

| What | Result |
|---|---|
| Rename an `[Export]` property (`Damage` to `BaseDamage`) and load an old `.tres` | No error or warning, also with `--verbose`; the C# default (1, was 12). Re-saving drops `Damage` for good. A removed property behaves the same |
| Rename the class and file, moving the `.cs.uid` too, `.tres` with a `uid=` | Loads as the new class; stale `path` and `script_class` are tolerated |
| The same with a `.tres` without a `uid=` | `Parse Error: [ext_resource] referenced non-existent resource`; `GD.Load` returns null |
| `ResourceSaver.Save` from a running game | Writes the `ext_resource` without a `uid` |
| Values equal to the default, an empty array | Not written to the file |
| `[Export(PropertyHint.Range, "0,100")] int Hp` set to 999 by hand | Loaded as 999 |
| An enum property set to 7 (no such member); `Speed = "fast"` on a float | Loaded as 7, and as 0, with no error |
| A missing `ExtResource` id | The whole load fails |
| Two scene instances whose `[Export] Weapon` is `axe.tres`; `a.Weapon.BaseDamage += 5` | One object: `b` and a later `GD.Load` see the change |
| `ResourceLocalToScene = true` | A copy per `PackedScene.Instantiate()`; two `GD.Load` calls still share |
| `Duplicate(true)` | An external `.tres` sub-resource stays shared; fields that are not exported are dropped (7 became 0, a `List<int>` came back empty) |
| `Duplicate(false)` | Shares the `Array<string>`: adding to the copy changed the original |
| `DuplicateDeep(Resource.DeepDuplicateMode.All)` (4.5+) | Copies the external sub-resource too |
| Cost, 1000 runs each | `Duplicate(true)` of a 1000-string array and a 20-deep chain: 1.47 ms; `Duplicate()` of 4 fields: about 45 µs; `new`: about 5 µs |
| Edit `axe.tres` on disk, then `GD.Load` | The cached, stale object |
| `ResourceLoader.Load(path, null, CacheMode.Replace)` | Reloads into the same object; every holder sees the new value. `CacheMode.Ignore` returns a new object |

So: definitions are read-only at run time and per-instance state lives in a plain C# object built from them; hints
guard only the inspector; renames need every `.tres` edited in the same commit and a test that compares each file's keys
with the class's stored properties (`GetPropertyList()` entries with `PropertyUsageFlags.Storage`).

## Data files in an export (tested, default import settings)

| File | In the project | In the exported game |
|---|---|---|
| Any `.csv` | Imported as a translation, even a data table (`items.csv` produced `items.name.translation`) | The file is absent: `FileAccess.FileExists` false |
| `.csv` with `importer="keep"` (Import As > Keep File) | Read with `FileAccess.GetCsvLine()`, quoted commas handled | Exported and readable |
| `.json` | A `JSON` resource, also readable with `FileAccess` | Exported and readable, no include filter needed |
| `.txt`, `.yaml` | Readable | Absent unless the preset's include filter names them |
| `.tres` | Text | Binary behind `w.tres.remap`; `DirAccess` lists only the `.remap`; `ResourceLoader.ListDirectory("res://data")` lists `w.tres` and loading by path works |

A loader that scans `res://data` with `DirAccess` for `*.tres` works in the editor and finds nothing in the export.

## JSON numbers and culture (tested)

- Godot's `Json.ParseString("{\"hp\": 10}")["hp"]` is a float (`10.0`); `9007199254740993` came back as
  `9007199254740992`; `{"a": 1,}` parsed; `{"a":1,"a":2}` kept 2.
- With `LANG=de_DE.UTF-8`, C# `float.Parse("0.5")` returned 5 with no exception and `1.5f.ToString()` gave `1,5`; with
  `fr_FR` it threw `FormatException`. The same inside Godot 4.7.2 C#; Godot's own `"0.5".ToFloat()` gave 0.5. A CI
  runner in `C.UTF-8` never sees it. The `culture-parse` architecture rule flags `float.Parse` and its kin without a
  culture.
- `System.Text.Json` on .NET 8 with `UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow` rejected
  `{"Id":"a","Prise":3}` for a `record Item(string Id, int Price)`:
  "The JSON property 'Prise' could not be mapped to any .NET
  member contained in type 'Item'."

## Spreadsheets and published practice (doc)

- Orbitect, before exporting balance JSON by script: "maybe spending around five minutes copying, pasting, zipping up
  and sending to one another each tweak". Derived columns (damage per second, time to kill) stay in the sheet; only
  inputs are exported.
- One direction only: sheet, then exported CSV or JSON committed to the repository, then the game.
- Dungeon Siege assembled objects from data; "data-driven" meant no engineer required. Hades keeps its data in Lua
  tables that mods merge into.

## The `data` runner

`data.json` in a game names each table's file (JSON or CSV), its id column and its fields; the runner is selected
whenever the file exists and needs no Godot. Field rules: `type` (string, int, number, bool), `min`, `max`, `enum`,
`pattern`, `ref` (another table whose ids the value must name), `list` (a JSON array, or `;` between values in a CSV
cell) and `optional`; columns not listed fail unless the table says `"extra": "allow"`. A JSON table is an array of
objects or an object keyed by id. A CSV table without `importer="keep"` in its committed `.import` fails, since it would
not ship. Numbers in CSV cells are parsed with the invariant culture. One JUnit case per table;
`tests/Test-Data.ps1` checks it against `tests/data-fixture`.

## Placed objects in levels

`ci/godot/templates/placement_check.gd`, copied into a game's tests, checks every node of the groups `ai_point`,
`interactable`, `zipline`, `landmark` and `route` in each level against limits read from gameplay code (`godot-data` section 6).
`tests/Test-Placement.ps1` proves each rule on `tests/placement-fixture`. Navigation answered under `--headless` after 9
to 11 physics frames for the first level of a GUT run; the checks took about 10 ms per 1,000 nodes. Source and the
talk's numbers: [Assassin's Creed Origins: world design data](gdc/assassins-creed-origins-world-data.md). The
`landmark` and `route` groups check wayfinding (a landmark that moves or is seen from one stretch only, a route with no
landmark ahead on the way back): [Stop Getting Lost: Make Cognitive Maps](gdc/cognitive-maps.md).

## Not confirmed

- A `_Set(StringName, Variant)` override mapping a renamed property; whether `CacheMode.Replace` emits `changed`.
- CastleDB's use in Dead Cells and Northgard; the 4.7 compatibility of CSV Data Importer; neither editor tool was tried.
- The Orbitect, Dungeon Siege, Hades and CastleDB details come from search summaries.
