# Contributing

- PowerShell 7.2+, strict mode. See [AGENTS.md](AGENTS.md) for the conventions (array unrolling, stable error codes, `-Json`).
- Before a pull request, run on both examples: `pwsh ci/godot/godot-ci.ps1 test -Project examples/breakout/game` and
  `-Project examples/gdscript`. Both must be green, with `-Json` output still valid.
- Changing a package version or Godot version: re-run both examples on that version and update `docs/godot-pipelines.md` and
  the `godot-test-loop` skill.
- New `error.code`: add it to `docs/json.md`. Never rename one.
- New or changed skill: keep each `SKILL.md` under 16 KB, with `name` and `description` front matter, and make sure every
  command in it runs.
