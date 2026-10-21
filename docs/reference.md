# Reference

**Script** (`ci/godot/godot-ci.ps1`): commands `test` (default), `build`, `export`, `setup`, `detect`,
`doctor`, `init`, `plan`, `bench`, `shot`, `status` and `audio`.

| Parameter | Default | |
|---|---|---|
| `-Project` | detected | Folder with `project.godot` |
| `-Solution` | nearest `.sln` | What `dotnet build` / `dotnet test` run on |
| `-GodotVersion` | from csproj, else `4.7.2` | e.g. `4.7.2`, `4.8-rc1` |
| `-Runners` | detected | `validate`, `architecture`, `dotnet`, `gdunit4`, `godottest`, `gut`, `flows`, `smoke`, `juice`; `none` to only build |
| `-Filter` | | Passed to each runner's filter |
| `-Coverage` | off | One merged coverage report |
| `-MinCoverage` | `0` (off) | Fail below this line coverage percentage |
| `-Preset` | every preset | `export`: which presets |
| `-Run` | off | `export`: launch builds this machine can run |
| `-Results`, `-Output` | `test-results`, `build` | Where results and exports go (`bench` defaults to `bench-results`, `shot` to `screenshots`) |
| `-Frames` | `120` | How long smoke runs and launched exports play; how long `shot` waits before each picture |
| `-GameArgs` | | Your game's flags, passed after `--` to smoke runs, `export -Run`, `bench` and `shot`; comma-separated |
| `-Scene` | main scene | `bench` and `audio -Mix` (first scene), `shot` (every scene): `res://` paths |
| `-Seconds`, `-Warmup` | `10`, `3` | `bench`: how long to measure, after a warm-up that is not counted; `audio -Mix`: how long to record (default 60) |
| `-BudgetMs` | `0` (off) | `bench`: fail when the p99 frame time is above this |
| `-Label` | | `bench`: the run's name in `bench.csv` |
| `-Resolution` | project setting | `bench`, `shot`: window size, e.g. `1920x1080` |
| `-Baseline` | | `shot`: a folder of earlier screenshots; each new one is compared with the one of the same name (not the `-Output` folder) |
| `-Uncapped`, `-MaxFps` | off, `0` | `bench`: V-Sync off; or a frame-rate cap |
| `-Headless` | off | `bench`: no window (CPU timings only; works without a display) |
| `-Mix` | off | `audio`: also record the game's own mix with Movie Maker (needs a display) and judge its loudness |
| `-TargetLufs` | `-24` | `audio -Mix`: the integrated loudness the mix must reach, within 2 LU; `-18` for phones and handhelds |
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
| `release` | `false` | Publish exports as a GitHub Release on tags (needs `contents: write`) |
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
| `per-frame-alloc` | C# `_Process`/`_PhysicsProcess` allocates (collections, `StringName`/`NodePath`, interpolated strings, LINQ), even in a rare branch |
| `event-not-unsubscribed` | a script subscribes to an autoload's C# event without `-=`, or connects a GDScript lambda to an autoload's signal without `disconnect` |
| `too-many-autoloads` | the project has more autoloads than `maxAutoloads` (default 8) |
| `audio-on-master` | a scene saves an `AudioStreamPlayer`, `AudioStreamPlayer2D` or `AudioStreamPlayer3D` with no bus, so it plays on Master and no volume setting but the master one reaches it |

Each rule is `warning` (default: reported, never fails), `error` (fails the runner) or `off`. Test folders and `addons/` are
not scanned. The fixtures in `tests/architecture-fixtures` show one example of each.

**`assets.json`** (in the Godot project folder) says where each image, sound, model, font and shader came from. `doctor`
reads it when the project has such files, and warns about:

- files with no entry
- entries with no `source`
- non-commercial licences (`CC-BY-NC-*`)
- GPL-family licences
- licences it does not recognise

It also reports how many files need a credit (attribution licences such as `CC-BY-4.0` and `MIT`):

```json
{ "assets": [
  { "path": "art/kenney_ui/**", "source": "https://kenney.nl/assets/ui-pack", "author": "Kenney", "licence": "CC0-1.0" },
  { "path": "shaders/dissolve.gdshader", "source": "https://godotshaders.com/shader/...", "author": "...", "licence": "MIT" },
  { "path": "art/player/**", "source": "own", "licence": "proprietary" }
] }
```

The `path` patterns work like this:

- They are relative to the project.
- `**` crosses folders; `*` and `?` stay within one.
- The first entry that matches a file wins.

The `licence` field takes an SPDX identifier, or `LicenseRef-<name>` for custom terms such as the Sonniss bundles.

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
