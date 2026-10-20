# Reference

**Script** (`ci/godot/godot-ci.ps1`): commands `test` (default), `build`, `export`, `setup`, `detect`,
`doctor`, `init`, `plan`, `bench`, `shot` and `status`.

| Parameter | Default | |
|---|---|---|
| `-Project` | detected | Folder with `project.godot` |
| `-Solution` | nearest `.sln` | What `dotnet build` / `dotnet test` run on |
| `-GodotVersion` | from csproj, else `4.7.2` | e.g. `4.7.2`, `4.8-rc1` |
| `-Runners` | detected | `validate`, `dotnet`, `gdunit4`, `godottest`, `gut`, `flows`, `smoke`; `none` to only build |
| `-Filter` | | Passed to each runner's filter |
| `-Coverage` | off | One merged coverage report |
| `-MinCoverage` | `0` (off) | Fail below this line coverage percentage |
| `-Preset` | every preset | `export`: which presets |
| `-Run` | off | `export`: launch builds this machine can run |
| `-Results`, `-Output` | `test-results`, `build` | Where results and exports go (`bench` defaults to `bench-results`, `shot` to `screenshots`) |
| `-Frames` | `120` | How long smoke runs and launched exports play; how long `shot` waits before each picture |
| `-GameArgs` | | Your game's flags, passed after `--` to smoke runs, `export -Run`, `bench` and `shot`; comma-separated |
| `-Scene` | main scene | `bench` (first scene), `shot` (every scene): `res://` paths |
| `-Seconds`, `-Warmup` | `10`, `3` | `bench`: how long to measure, after a warm-up that is not counted |
| `-BudgetMs` | `0` (off) | `bench`: fail when the p99 frame time is above this |
| `-Label` | | `bench`: the run's name in `bench.csv` |
| `-Resolution` | project setting | `bench`, `shot`: window size, e.g. `1920x1080` |
| `-Uncapped`, `-MaxFps` | off, `0` | `bench`: V-Sync off; or a frame-rate cap |
| `-Headless` | off | `bench`: no window (CPU timings only; works without a display) |
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
