---
name: godot-test-frameworks
description: Use when choosing or setting up a test framework for a Godot 4.x project, or pinning compatible test package versions.
---

# Choosing a Godot test framework

| Situation | Use | Why |
|---|---|---|
| GDScript project | **GUT** | Largest GDScript community; the suite installs the right release for your Godot |
| C# logic with no engine types | **xUnit/NUnit/MSTest** (`dotnet` runner) | Fastest, no Godot start-up, coverlet coverage works |
| C# code that needs nodes/scenes | **gdUnit4Net** `[TestSuite]` + `[RequireGodotRuntime]` | `dotnet test` + IDE test explorer; scene runner, mocking |
| C# code that only runs in the live game; coverage of engine-only code | **GoDotTest** | Tests run inside the real game process; coverage via coverlet console |
| Any project, zero tests to write | `smoke` + `validate` (always on) | Loads everything, plays the main scene, fails on any error |

Mix them: a class library with xUnit for pure logic, gdUnit4Net for scenes, GoDotTest if you need in-game coverage.
Keep engine-free logic in plain classes so most tests need no Godot at all.

## Versions verified on Godot 4.7.2 / .NET 8

```xml
<Project Sdk="Godot.NET.Sdk/4.7.2">
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.14.1" />
<PackageReference Include="gdUnit4.api" Version="5.0.0" />
<PackageReference Include="gdUnit4.test.adapter" Version="3.0.0" />   <!-- 3.1.x needs a pre-release api -->
<PackageReference Include="Chickensoft.GoDotTest" Version="2.0.47" />
<PackageReference Include="coverlet.collector" Version="10.1.0" />
```
GUT: v9.7.1 for Godot 4.7 (v9.6.1 for 4.6, v9.5.0 for 4.5, v9.4.0 for 4.4). GUT releases are tied to one Godot
minor; the suite installs the matching one and keeps it in step when you upgrade Godot. An `addons/gut` you
committed yourself (no `.godot-ci-version` file) is never touched.

## Setup notes

- **gdUnit4Net**: the suite writes the `.runsettings` (`GODOT_BIN`, `--headless`). Tests without
  `[RequireGodotRuntime]` run as plain .NET; with it they run inside Godot. Add `gdunit4_testadapter*/` to `.gitignore`.
- **GoDotTest**: needs a small scene whose script calls `GoTest.RunTests(...)`; the suite finds it and runs
  `--run-tests --quit-on-finish`.
- **GUT**: `test_*.gd` extending `GutTest`; a `.gutconfig.json` overrides folders and prefix.
- Run `godot-ci.ps1 init` to add a starter test with release-safe packaging.

Coverage caveat: tests inside the engine (`[RequireGodotRuntime]`) are invisible to coverlet's `dotnet` collector.
Use GoDotTest for in-engine coverage, or accept dotnet-side coverage as a floor on the pure logic.
