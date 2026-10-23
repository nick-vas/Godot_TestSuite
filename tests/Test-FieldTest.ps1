# Self-test for the benchmark's private field test (benchmark/FieldTest.ps1, -GameSource of
# benchmark/Invoke-TokenBenchmark.ps1), with the stand-in CLI (tests/game-benchmark/fake-game-claude.ps1): the mutant
# planter (only the game's own code, never strings, comments, tests or C# generics; an order fixed by the seed), and
# whole runs on copies of examples/gdscript and examples/csharp, where good work passes every template that applies,
# bad work fails it for a reason reported only as a kind, and the summary holds numbers only. Needs Godot, the .NET
# build for C# (GODOT_BIN, or the kit installs it); -NoCSharp leaves the C# game out (it takes about 15 minutes). Calls
# no model and costs nothing.
param([switch]$NoCSharp)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$bench = Join-Path $root 'benchmark/Invoke-TokenBenchmark.ps1'
$fake = Join-Path $PSScriptRoot 'game-benchmark/fake-game-claude.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) "field-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$privateTemp = Join-Path $work 'tmp'
New-Item -ItemType Directory -Force $privateTemp | Out-Null
$saved = @{}
foreach ($name in 'FAKE_CLAUDE_LOG', 'FAKE_GAME_MODE', 'FAKE_FIELD_ORIGINAL', 'TMPDIR') { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
$env:FAKE_CLAUDE_LOG = Join-Path $work 'calls.jsonl'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

if (-not $env:GODOT_BIN -or -not (Test-Path -LiteralPath $env:GODOT_BIN) -or (-not $NoCSharp -and $env:GODOT_BIN -notmatch '_mono')) {
    $setup = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') setup -Json -Quiet -Project (Join-Path $root 'examples/csharp/game') 2>$null
    $env:GODOT_BIN = @(Get-ChildItem -LiteralPath $(if ($env:GODOT_TOOLS_DIR) { $env:GODOT_TOOLS_DIR } else { Join-Path $HOME '.hyperdot' }) -Recurse -File |
        Where-Object { $_.Name -match '^Godot_v[\d.]+-stable_mono_(linux\.x86_64|linux_x86_64|win64_console\.exe)$' } | Select-Object -First 1 | ForEach-Object FullName) | Select-Object -First 1
    Write-Host "Godot: $env:GODOT_BIN ($(@($setup).Count) line(s) from setup)"
}

# The planter, called directly.
function Write-Text([string]$Path, [string]$Text) { New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null; [IO.File]::WriteAllText($Path, $Text) }
function Write-BenchLog([string]$Message) { Write-Verbose $Message }
. (Join-Path $root 'benchmark/GameProgramme.ps1')
. (Join-Path $root 'benchmark/FieldTest.ps1')
$planted = Join-Path $work 'planter'
Write-Text "$planted/project.godot" "config_version=5`n"
Write-Text "$planted/logic.gd" "extends Node`n# a + b in a comment`nfunc f(a, b):`n`tprint(`"a - b in a string`")`n`treturn a + b`n"
Write-Text "$planted/Logic.cs" "using System.Collections.Generic;`n[assembly: System.Reflection.AssemblyVersion(`"1.0`")]`nclass Logic {`n    int F(int a, int b) {`n        var list = new List<int>();`n        /* a - b`n           a * b */`n        if (a < b) { return a; } // a / b`n        return list.Count;`n    }`n}`n"
Write-Text "$planted/test/test_logic.gd" "extends GutTest`n`nfunc test_f():`n`tassert_eq(1 + 1, 2)`n"
Write-Text "$planted/addons/thing/thing.gd" "extends Node`nfunc g(a):`n`treturn a * 2`n"
$candidates = @(Get-MutantCandidates $planted)
$described = @($candidates | ForEach-Object { "$($_.file):$($_.line) $(($_.replace -split "`n")[-1].Trim())" })
Assert-True (($described -join ' | ') -eq 'Logic.cs:8 if (a <= b) { return a; } // a / b | logic.gd:5 return a - b') "mutants go only in code, never in comments, strings, generics, attributes, tests or add-ons ($($described -join ' | '))"
function Get-Order([int]$Seed) {
    $order = Get-SeededOrder (Get-MutantCandidates (Join-Path $root 'examples/gdscript')) $Seed
    return @($order | ForEach-Object { "$($_.file):$($_.line):$($_.replace)" })
}
$first = Get-Order 7; $again = Get-Order 7; $other = Get-Order 8
Assert-True ($first.Count -ge 4 -and ($first -join '|') -eq ($again -join '|') -and ($first -join '|') -ne ($other -join '|')) "a seed fixes the order of $($first.Count) candidates, another seed changes it"
Assert-True ((ConvertTo-FieldReason 'changed test/test_score.gd; tests fail: test_hidden_x') -eq 'changed a file it was to leave alone; the game''s checks fail') 'failures are reported as kinds, without names'

# One field run with the stand-in; the sessions' calls are the lines the log gained.
function Invoke-Field([string]$Source, [string]$Mode, [string[]]$Arguments) {
    $env:FAKE_GAME_MODE = $Mode
    $out = & pwsh -NoProfile -File $bench -GameSource $Source -Claude $fake -OutputDir (Join-Path $work "results-$Mode") -Json @Arguments 2>$null
    $code = $LASTEXITCODE
    $doc = @($out | Where-Object { $_ -match '^\{' }) | Select-Object -Last 1
    $json = if ($doc) { $doc | ConvertFrom-Json }
    $folder = if ($json -and $json.PSObject.Properties['folder']) { $json.folder }
    $rows = if ($folder) { @(Get-Content -LiteralPath (Join-Path $folder 'results.json') -Raw | ConvertFrom-Json) } else { @() }
    $md = if ($folder -and (Test-Path -LiteralPath (Join-Path $folder 'field-test.md'))) { Get-Content -LiteralPath (Join-Path $folder 'field-test.md') -Raw } else { '' }
    return [pscustomobject]@{ Code = $code; Json = $json; Rows = $rows; Folder = $folder; Markdown = $md }
}
function Get-Row($Run, [string]$Template) { return @($Run.Rows | Where-Object task -eq "field.$Template") | Select-Object -First 1 }
# Nothing of the game in what is reported: no file, folder, test or function name.
function Test-NumbersOnly($Run, [string[]]$Names) {
    $text = $Run.Markdown + (Get-Content -LiteralPath (Join-Path $Run.Folder 'results.json') -Raw) + (Get-Content -LiteralPath (Join-Path $Run.Folder 'field-test.json') -Raw)
    return @($Names | Where-Object { $text -match [regex]::Escape($_) }).Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $Run.Folder 'responses'))
}

try {
    $env:TMPDIR = $privateTemp
    $gd = Join-Path $root 'examples/gdscript'
    $env:FAKE_FIELD_ORIGINAL = $gd
    $dry = Invoke-Field $gd 'good' @('-DryRun')
    Assert-True ($dry.Code -eq 0 -and $dry.Json.configurations -eq 4 -and $dry.Json.calls -eq 16 -and $dry.Json.budgetUsd -eq 10) "a dry run plans every template under the four configurations within the ceiling ($(if ($dry.Json) { "$($dry.Json.calls) sessions, $($dry.Json.estimateUsd) USD" }))"
    Assert-True ((Invoke-Field $gd 'good' @('-SaveResponses', '-DryRun')).Code -ne 0) 'answers and diffs are never saved'

    $good = Invoke-Field $gd 'good' @('-Model', 'sonnet')
    Assert-True ($good.Code -eq 0 -and $good.Rows.Count -eq 2 -and @($good.Rows | Where-Object success).Count -eq 2) "GDScript: good work passes fix-mutant and write-tests ($(@($good.Rows | ForEach-Object { "$($_.task) $($_.success) $($_.reasons)" }) -join '; '))"
    Assert-True ($good.Markdown -match '\| fix-mutant \| sonnet \| 1 \| 1 \|' -and $good.Markdown -match '\| write-tests \| sonnet \| 1 \| 1 \|') 'the summary has a row per template and configuration'
    Assert-True ($good.Markdown -match 'doctor-green \(`doctor` is already green\)' -and $good.Markdown -match 'bot-finish \(the game has no playthrough\.json\)') 'templates with nothing to work on are listed as not applicable'
    Assert-True ($good.Folder -and (Test-NumbersOnly $good @('score', '.gd', 'test_', 'examples', 'main', $gd))) 'the report holds numbers only, nothing of the game'
    $calls = @(Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True (@($calls | Where-Object { $_.prompt -match 'too few tests of [^:]*\.gd: bugs' }).Count -eq 1) 'write-tests names the code its planted bugs are in, to the session only'
    Assert-True (@($calls | Where-Object { $_.cwd -like "$gd*" }).Count -eq 0 -and -not (& git -C $root status --porcelain -- examples/gdscript)) 'sessions work in copies; the game itself is untouched'

    $bad = Invoke-Field $gd 'bad' @('-Model', 'haiku', '-Plugin')
    $fix = Get-Row $bad 'fix-mutant'; $tests = Get-Row $bad 'write-tests'
    Assert-True ($bad.Code -eq 0 -and $fix -and -not $fix.success -and $fix.reasons -eq 'the game''s checks fail') "GDScript: a bug left in fails fix-mutant ($(if ($fix) { $fix.reasons }))"
    Assert-True ($tests -and -not $tests.success -and $tests.reasons -match 'its tests miss a planted bug') "GDScript: tests that check nothing fail write-tests ($(if ($tests) { $tests.reasons }))"
    Assert-True ($bad.Markdown -match '\| fix-mutant \| haiku \+ plugin \| 1 \| 0 \|') 'the configuration is named in the summary'

    # doctor-green, on a copy whose doctor fails: an asset placeholder past its due date.
    $broken = Join-Path $work 'doctor-game'
    Copy-Item -LiteralPath $gd -Destination $broken -Recurse
    Write-Text "$broken/assets.json" '{ "assets": [ { "path": "main.tscn", "licence": "CC0-1.0", "author": "me", "placeholder": true, "due": "2020-01-01" } ] }'
    $env:FAKE_FIELD_ORIGINAL = $broken
    $doctorGood = Invoke-Field $broken 'good' @('-Model', 'sonnet', '-TaskId', 'field.doctor-green')
    $doctorBad = Invoke-Field $broken 'bad' @('-Model', 'sonnet', '-TaskId', 'field.doctor-green')
    Assert-True ($doctorGood.Rows.Count -eq 1 -and $doctorGood.Rows[0].success) "doctor-green passes once doctor is green ($(if ($doctorGood.Rows.Count) { $doctorGood.Rows[0].reasons }))"
    Assert-True ($doctorBad.Rows.Count -eq 1 -and -not $doctorBad.Rows[0].success -and $doctorBad.Rows[0].reasons -eq '`doctor` still fails') "doctor-green fails while doctor fails ($(if ($doctorBad.Rows.Count) { $doctorBad.Rows[0].reasons }))"
    Assert-True ((Invoke-Field $broken 'good' @('-Model', 'sonnet', '-TaskId', 'field.bot-finish')).Code -ne 0) 'a run where no template applies stops before any session'

    if (-not $NoCSharp) {
        # The whole C# example (the solution is above the Godot project): a copy of what git tracks.
        $cs = Join-Path $root 'examples/csharp'
        $env:FAKE_FIELD_ORIGINAL = $cs
        $csGood = Invoke-Field $cs 'good' @('-Model', 'sonnet', '-TaskId', 'field.fix-mutant,field.write-tests')
        Assert-True ($csGood.Code -eq 0 -and $csGood.Rows.Count -eq 2 -and @($csGood.Rows | Where-Object success).Count -eq 2) "C#: good work passes fix-mutant and write-tests ($(@($csGood.Rows | ForEach-Object { "$($_.task) $($_.success) $($_.reasons)" }) -join '; '))"
        Assert-True ($csGood.Folder -and (Test-NumbersOnly $csGood @('.cs', 'Example', 'examples', $cs))) 'C#: the report holds numbers only'
        $csCalls = @(Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.prompt -match 'The Godot project is in game/' })
        Assert-True ($csCalls.Count -eq 2) 'C#: the prompt says where the Godot project is'
    }
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failures.Count) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All field test checks passed'
exit 0
