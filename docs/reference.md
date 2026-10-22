# Reference

**Script** (`ci/godot/godot-ci.ps1`): commands `test` (default), `build`, `export`, `setup`, `detect`,
`doctor`, `init`, `plan`, `bench`, `shot`, `status`, `audio`, `soak` and `credits`.

| Parameter | Default | |
|---|---|---|
| `-Project` | detected | Folder with `project.godot` |
| `-Solution` | nearest `.sln` | What `dotnet build` / `dotnet test` run on |
| `-GodotVersion` | from csproj, else `4.7.2` | e.g. `4.7.2`, `4.8-rc1` |
| `-Runners` | detected | `validate`, `architecture`, `dotnet`, `gdunit4`, `godottest`, `gut`, `flows`, `smoke`, `juice`, `l10n`, `data`, `textsize`, `layout`; `none` to only build |
| `-Filter` | | Passed to each runner's filter |
| `-Coverage` | off | One merged coverage report |
| `-MinCoverage` | `0` (off) | Fail below this line coverage percentage |
| `-Preset` | every preset | `export`: which presets |
| `-Run` | off | `export`: launch builds this machine can run; Web builds open in a browser (a debug export of the preset, served on 127.0.0.1, with cross-origin isolation headers only for a threads build) |
| `-Browser` | `chromium` | `export -Run` of a Web preset: `chromium`, `firefox`, `webkit` (Playwright's browsers: `npx playwright install --with-deps <name>`), `chrome`, `msedge` (the installed browsers); comma-separated. Needs Node.js; the playwright package comes from `GODOT_CI_PLAYWRIGHT`, the global npm folder, or is installed into the kit's tools folder. `GODOT_CI_WEB_HEADED=1` opens a browser window instead of running headless |
| `-GameVersion` | | `export`: the game's version, e.g. the tag `v1.2.3-rc.1`: its numbers go into `config/version` for this export only (Windows file version, macOS and Android versions), all of it into the C# assembly's InformationalVersion |
| `-Results`, `-Output` | `test-results`, `build` | Where results and exports go (`bench` defaults to `bench-results`, `shot` to `screenshots`, `credits` to the project folder) |
| `-Frames` | `120` | How long smoke runs and launched exports play; how long `shot` waits before each picture |
| `-GameArgs` | | Your game's flags, passed after `--` to smoke runs, `export -Run`, `bench` and `shot`; comma-separated |
| `-Scene` | main scene | `bench` and `audio -Mix` (first scene), `shot` (every scene): `res://` paths |
| `-Seconds`, `-Warmup` | `10`, `3` | `bench`: how long to measure, after a warm-up that is not counted; `audio -Mix`: how long to record (default 60); `soak`: how long to run after the warm-up |
| `-BudgetMs` | `0` (off) | `bench`: fail when the p99 frame time is above this |
| `-Label` | | `bench`: the run's name in `bench.csv` |
| `-HotspotCell` | `0` (10 m in 3D, 512 px in 2D) | `bench`: the grid cell that frame times are grouped into by camera position, for `hotspots` (where it is slow) |
| `-Resolution` | project setting | `bench`, `shot`: window size, e.g. `1920x1080` |
| `-Baseline` | | `shot`: a folder of earlier screenshots; each new one is compared with the one of the same name (not the `-Output` folder) |
| `-Locale`, `-Pseudo` | | `shot`: also take each scene in these locales (`fr,ar,ja`) and pseudolocalized, and fail (`shot-text`) on text that is cut off, off screen or missing glyphs |
| `-ColorVision` | | `shot`: also save each picture as people with colour blindness see it, `protan,deutan,tritan` (`<name>.<kind>.png`, `shots[].colorVision`) |
| `-Uncapped`, `-MaxFps` | off, `0` | `bench`: V-Sync off; or a frame-rate cap |
| `-Headless` | off | `bench`: no window (CPU timings only; works without a display) |
| `-Mix` | off | `audio`: also record the game's own mix with Movie Maker (needs a display) and judge its loudness |
| `-TargetLufs` | `-24` | `audio -Mix`: the integrated loudness the mix must reach, within 2 LU; `-18` for phones and handhelds |
| `-MaxOnsetMs` | `20` | `audio`: warn when an `sfx` or `ui` file takes longer than this to come within 10 dB of its loudest 10 ms (`onsetMs`) |
| `-Clients` | `4` | `soak`: headless clients started next to the one server |
| `-MaxGrowthMbPerHour` | `0` (report only) | `soak`: fail (`soak-leak`) when a process's memory grows faster than this |
| `-JunkPps` | `0` (off) | `soak`: flood the server's own port on `127.0.0.1` with this many junk UDP packets a second (loopback only), to measure how it holds up; reported under `soak.junk` |
| `-Json` | off | One JSON document on stdout, logs on stderr ([json.md](json.md)) |
| `-Quiet` | off | Godot and dotnet output only in `<Results>/godot-ci.log`, not on the console. Use with `-Json` for agents |
| `-Do`, `-Id`, `-Game` | `status` | `plan`: `init`, `status`, `done -Id <gate>`, `add`, `move -Id <task> -Column`, `sync`, `link` |
| `-Title`, `-Column`, `-Board` | | `plan add` title; `add`/`move` column; `sync` Trello board; `link -Column` the card's list, `link -Board` the plan's board |
| `-Feature`, `-Card` | | `plan add`/`link`: the GDD feature a task delivers (`F3`); `link`: the task's Trello card id |
| `-McpDiagnostics` | off | `init`: also register minimal-godot-mcp (GDScript diagnostics, game console) |
| `-Mcp` | `none` | `init`: `godot-mcp` registers that editor MCP server; `godot-ai` prints its steps |
| `-Agents` | off | `init`: also add AGENTS.md, CLAUDE.md, the skills and the `godot-verifier` subagent |
| `-Plugin` | off | `init`: AGENTS.md and CLAUDE.md, and enable this kit as a Claude Code plugin in `.claude/settings.json` instead of copying skills |

**Workflow inputs** (`godot.yml`), all optional:

| Input | Default | |
|---|---|---|
| `project`, `godot-version`, `runners`, `filter` | detected | As the script parameters |
| `coverage`, `min-coverage` | off | Coverage report; fail below a percentage |
| `pr-comment` | `true` | Results comment on pull requests (needs `pull-requests: write`) |
| `exports` | none | `all`, or a comma list of preset names |
| `run-exports` | `false` | Launch each export on a runner of its own OS |
| `release` | `false` | Publish exports as a GitHub Release on tags (needs `contents: write`); exports of a tag carry its version (`-GameVersion`) |
| `runs-on` | `ubuntu-latest` | `windows-latest` also works |
| `lfs`, `submodules`, `retention-days` | | Checkout options and artifact retention |

**Your own workflow:** the composite action runs one command with setup and caching, then uploads the
results or the build.
```yaml
      - uses: nick-vas/Godot_TestSuite/.github/actions/godot@main
        with:
          command: export        # test, build or export
          preset: Windows
      - run: echo "upload the Windows build to itch.io, Steam, ..."
```

**Cost:** jobs run in the repository that calls the workflow. They're free on public repositories; on private
ones they use your Actions minutes, and Linux runners are the cheapest (Windows minutes count about 2×).
One test job builds once for every framework. Exports and Windows runners only run when you ask for them.

**Claude Code cloud sessions** run Linux. Install PowerShell in the environment's setup script, then use
the script as usual:
```bash
mkdir -p /opt/pwsh && curl -fsSL https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/powershell-7.6.6-linux-x64.tar.gz | tar xz -C /opt/pwsh && ln -sf /opt/pwsh/pwsh /usr/local/bin/pwsh
```

More on each framework, the five most popular Godot test projects, and how to set each one up:
[godot-pipelines.md](godot-pipelines.md).

**`architecture.json`** (optional, in the Godot project folder) configures the `architecture` runner:

```json
{ "rules": { "parent-path": "error", "per-frame-alloc": "off" }, "maxAutoloads": 6 }
```

| Rule | Warns when |
|---|---|
| `parent-path` | a node path climbs two or more levels (`../..`, `GetParent().GetParent()`) |
| `ui-mutates-state` | a UI script (extends a Control type, or lives under `ui/`, `hud/`, `menu/`) assigns to an autoload's field |
| `per-frame-lookup` | `_Process`/`_PhysicsProcess` looks up nodes (`GetNode`, `$Node`, `FindChild`, groups) |
| `per-frame-alloc` | C# `_Process`/`_PhysicsProcess` allocates (collections, `StringName`/`NodePath`, an action name as a string literal such as `Input.IsActionPressed("jump")`, interpolated strings, LINQ), even in a rare branch |
| `event-not-unsubscribed` | a script subscribes to an autoload's C# event without `-=`, or connects a GDScript lambda to an autoload's signal without `disconnect` |
| `too-many-autoloads` | the project has more autoloads than `maxAutoloads` (default 8) |
| `audio-on-master` | a scene saves an `AudioStreamPlayer`, `AudioStreamPlayer2D` or `AudioStreamPlayer3D` with no bus, so it plays on Master and no volume setting but the master one reaches it |
| `enet-server-channels` | `create_server`/`CreateServer` is given a channel count: Godot 4.7.x passes it as the server's incoming bandwidth limit in bytes per second, so every client's input stalls |
| `untrusted-load` | `load`, `GD.Load` or `ResourceLoader.Load` (or a threaded load) is given a path that starts with `user://`: a `.tres` or `.tscn` that a player, a mod or a download put there runs any script embedded in it |
| `culture-parse` | C# `float.Parse`, `double.Parse`, `decimal.Parse` (or `TryParse`) without `CultureInfo`, `NumberFormatInfo` or another format provider on the line: on a German system `"0.5"` parses as 5, on a French one it throws |
| `steam-removed-api` | a call to `IsSteamRunningOnSteamDeck` or `RequestCurrentStats` (either casing): removed or deprecated in Steamworks SDK 1.65, and gone from GodotSteam 4.21+ and Steamworks.NET 1.65 |
| `steam-env-dotnet` | C# `Environment.SetEnvironmentVariable("SteamAppId"` or `SteamGameId`: on Linux and macOS .NET keeps its own copy of the environment, so the native Steam API never sees it; `OS.SetEnvironment` works |
| `frame-dependent-lerp` | `_Process`/`_process` lerps a value toward a target and assigns it back to the same value, with a weight that has no `delta` in it: `Position = Position.Lerp(target, 0.1f)`, `x = Mathf.Lerp(x, target, 0.1f)`, `x += (target - x) * 0.1f`, GDScript `lerp`, `lerpf`, `lerp_angle`, `.lerp`, `.slerp`. A fixed fraction per frame converges faster at 144 fps than at 30 and ignores time scale; `1 - Mathf.Exp(-rate * delta)` does not. Not flagged: a weight that names `delta` (or a variable assigned from it), a lerp between two other values, `_physics_process` (a fixed rate), a call split over lines or made from a helper method ([why](gdc/juicing-your-cameras.md)) |

Each rule is `warning` (default: reported, never fails), `error` (fails the runner) or `off`. Test folders and `addons/` are
not scanned. The fixtures in `tests/architecture-fixtures` show one example of each.

**`assets.json`** (in the Godot project folder) says where each image, sound, model, font and shader came from. `doctor`
reads it when the project has such files, and warns about:

- files with no entry
- entries with no `source`
- non-commercial licences (`CC-BY-NC-*`)
- GPL-family licences
- licences it does not recognise
- commissioned work with no `agreement`, with `rights` other than `assigned` or `licensed`, or licensed with no `uses`

It also reports how many files need a credit (attribution licences such as `CC-BY-4.0` and `MIT`):

```json
{ "assets": [
  { "path": "art/kenney_ui/**", "source": "https://kenney.nl/assets/ui-pack", "author": "Kenney", "licence": "CC0-1.0" },
  { "path": "shaders/dissolve.gdshader", "source": "https://godotshaders.com/shader/...", "author": "...", "licence": "MIT" },
  { "path": "art/player/**", "source": "own", "licence": "proprietary" },
  { "path": "art/boss/**", "source": "commissioned", "author": "Jane Doe", "licence": "proprietary",
    "agreement": "WFH-2026-03", "rights": "assigned" },
  { "path": "music/**", "source": "commissioned", "author": "Max Mo", "licence": "LicenseRef-MaxMo-Music",
    "agreement": "MM-2026-01", "rights": "licensed", "uses": ["game", "trailer", "store"] }
] }
```

The `path` patterns work like this:

- They are relative to the project.
- `**` crosses folders; `*` and `?` stay within one.
- The first entry that matches a file wins.

The `licence` field takes an SPDX identifier, or `LicenseRef-<name>` for custom terms such as the Sonniss bundles.

`"source": "commissioned"` marks work made for the game by anyone else: a contractor, a freelancer, a co-founder. Under US
copyright the maker owns it unless a signed agreement says otherwise, so besides `licence` (`proprietary` when assigned,
`LicenseRef-<name>` for a licence's own terms) such an entry has:

- `agreement`: a reference to the signed document (an id, or a path kept outside the shipped project); never the contract
  itself in a public repository
- `rights`: `assigned` (the studio owns it: work for hire or an IP assignment) or `licensed` (the maker keeps it)
- `uses` (licensed only): what the licence covers, as the agreement words it, such as `game`, `trailer`, `store`,
  `soundtrack`, `merchandise`

`doctor` lists licensed entries with their uses. `credits` treats commissioned work as the game's own (no third-party credit)
unless its `licence` asks for one. The rules: `godot-legal` section 4 and [gdc/contract-law-201.md](gdc/contract-law-201.md).

**`credits`** builds the game's credits from `assets.json`: `CREDITS.md`, `credits.json` (for a credits screen) and
`THIRD-PARTY-NOTICES.txt` (each asset's copyright line and licence text, Godot's MIT text and its third-party components read
from the engine, and the .NET runtime's notices for a C# game). It fails (`credits-invalid`) when an entry lacks what its
licence asks for. Optional fields help: `title`, `copyright` (the original copyright line), `modified` (what you changed),
`licenceFile` and `noticeFile` (paths of the upstream licence and NOTICE files). Licence texts for MIT, ISC, BSD-2-Clause,
BSD-3-Clause, Apache-2.0, OFL-1.1 and Zlib come with the kit (`ci/godot/templates/licences`). `export` copies
`THIRD-PARTY-NOTICES.txt` next to each executable. The rules: the `godot-credits` skill and [store-and-legal.md](store-and-legal.md).

**`store/steam/`** (optional, in the Godot project folder, with an empty `store/.gdignore` so Godot does not ship it) holds
the Steam store art. `doctor` checks the current sizes (`header_capsule` 920x430, `small_capsule` 462x174, `main_capsule`
1232x706, `vertical_capsule` 748x896, `library_capsule` 600x900, `library_header` 920x430, `library_hero` 3840x1240 PNG,
`library_logo` PNG with transparency, 1280 wide or 720 tall, `shortcut_icon` 256 or 512 square, `app_icon` 184x184 JPEG,
optional `page_background` 1438x810), at least five `screenshot*` files at 1920x1080 or more in 16:9, and
`short_description.txt` (plain text, no links or time-limited wording, 300 characters at most). Wrong sizes and formats FAIL;
missing files and short description problems WARN.

**`juice.json`** (optional, in the Godot project folder) turns on the `juice` runner: Godot plays the game headless at a fixed
60 fps for `frames` frames (default 1800) with `args` (plus `-GameArgs`), and each rule checks that every `event` was followed
by each `feedback` within `withinMs` (default 100) of game time:

```json
{ "frames": 1800, "args": ["--autoplay", "--seed=1"],
  "rules": [ { "event": "brick_hit", "feedback": ["flash", "sfx"], "withinMs": 100 } ] }
```

The game prints `[juice] event <name> <ms>` and `[juice] feedback <name> <ms>`, with `<ms>` its game time in milliseconds. A
rule fails when an event went unanswered, or never happened (the bot did not reach it). Events too close to the end of the run
to be answered are ignored. `tests/juice-fixture` is a minimal example (`-GameArgs --late` makes it fail).

**The `l10n` runner** is picked when the project has translation CSVs (imported as translations, or a first header cell
`keys` or `key`), `.po` files or translation remaps. It runs without Godot and has six cases: `duplicate keys` (the same key
and context twice), `untranslated` (an empty cell; an empty or fuzzy PO entry; fewer plural forms than the language needs,
counted for 15 common languages; others are not counted), `missing keys` (literal keys in `tr`, `Tr`, `TrN`, `atr`
and `TranslationServer.Translate` calls that no table has; test folders are skipped), `too long` (a CSV cell over the
row's `_max` characters or `_lines` lines; `_max_<locale>` overrides `_max`), `translation remaps` (a remap target that does
not exist or names no locale) and `localized audio` (a remapped sound whose sample rate, channels or bit depth differ from
the source's, whose length is outside 0.5 to 2 times the source's, or whose loudness is more than 2 LU away; skipped with a
warning without ffmpeg; `l10n.json` sets `voiceDurationMin`, `voiceDurationMax` and `voiceLoudnessLu`).
`tests/l10n-fixture` has one of each; see [localization.md](localization.md).

**`textsize.json`** (optional, in the Godot project folder) turns on the `textsize` runner, which measures every visible text
on the listed scenes (the main scene by default) at each resolution (1280x800 by default, the Steam Deck), headless: the stretch
scale comes from the project settings and the letters' height from the font. A font size under `minPx` (9) fails; capitals under
`minPx` or a size under `wantPx` (12) are warnings. Integer scaling with a base bigger than the window fails (drawn 1:1, cut off).
Subtitles are text in the `subtitleGroup` node group (`subtitles`), or inside a node in it, hidden or not; their sizes are
given at 1080p and scaled with each window's height: a font size under `subtitleMinPx` (28) fails, under `subtitleWantPx` (46)
warns (`subtitle-below-recommended`). The numbers come from two GDC talks ([docs/gdc/subtitles-are-changing.md](gdc/subtitles-are-changing.md)).
`-Runners textsize` runs it without the file, with the defaults.

```json
{ "scenes": ["res://ui/menu.tscn", "res://ui/hud.tscn"], "resolutions": ["1280x800", "1280x720"], "minPx": 9, "wantPx": 12,
  "subtitleGroup": "subtitles", "subtitleMinPx": 28, "subtitleWantPx": 46 }
```

**`layout.json`** (optional, in the Godot project folder) turns on the `layout` runner, which lays out the listed scenes (the main
scene by default), headless, at each profile and fails on controls that are off screen, outside the profile's safe area, or too small
to touch (`minTouchDp`, 48) or click (`minPointerPx`, 24 CSS px). Profiles: `phone_portrait` (1080x2400 at 420 dpi, a 128 px top inset
and 66 px bottom), `phone_landscape`, `tablet` (2048x1536 at 264 dpi) and `ultrawide` (3440x1440, mouse), or
`name:WIDTHxHEIGHT@DPI[:touch][:insets=L,T,R,B]`. If the game has a `SafeArea` autoload with `set_insets`/`SetInsets(left, top, right,
bottom)`, each profile's insets are passed to it first, so the game's own safe-area handling is measured. `checks` limits what is
reported. `-Runners layout` runs it without the file, with the defaults.

```json
{ "scenes": ["res://ui/menu.tscn"], "profiles": ["phone_portrait", "tablet", "foldable:1812x2176@374:touch:insets=0,96,0,48"],
  "minTouchDp": 48, "minPointerPx": 24, "checks": ["off-screen", "unsafe-area", "small-target"] }
```

**`data.json`** (optional, in the Godot project folder) turns on the `data` runner, which checks the game's data tables without
Godot. Each table names its file (JSON: an array of objects or an object keyed by id; or CSV), its `id` column and its fields:
`type` (`string`, `int`, `number`, `bool`), `min`/`max`, `enum`, `pattern`, `ref` (another table whose ids the value must name),
`list` (a JSON array, or `;` between values in a CSV cell) and `optional`. Columns that data.json does not list fail (`"extra": "allow"`
to permit them), and so does a CSV table without a committed `.import` saying `importer="keep"`: Godot imports every `.csv` as a
translation otherwise, and the exported game cannot read the file.

```json
{ "tables": {
    "items":   { "file": "data/items.json", "id": "id", "fields": { "price": { "type": "int", "min": 0 }, "rarity": { "enum": ["common", "rare"] } } },
    "enemies": { "file": "data/enemies.csv", "id": "id", "fields": { "hp": { "type": "int", "min": 1 }, "drops": { "ref": "items", "list": true } } } } }
```
