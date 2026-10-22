#!/usr/bin/env pwsh
# Self-test of error keys (Activision's error buckets for Call of Duty, docs/gdc/call-of-duty-error-keys.md): an error line
# becomes a key with what changes between runs (numbers, addresses, line numbers) taken out and its project file kept; each
# history line records its run's keys and commit; status -Json groups the history by key in recurringErrors (count, first
# and last seen, commands) and warns when the latest failure's error is older than the current commit. The first part is
# synthetic (no Godot); the second runs the kit on tests/errorkeys-fixture and needs Godot (GODOT_BIN, or the kit installs
# it) and git; -NoGodot runs only the first part.
param([switch]$NoGodot)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$kit = Join-Path $root 'ci/godot/godot-ci.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# --- Keys: what changes between runs is taken out, what tells errors apart is kept --------------------------------------
$a = Get-ErrorKey 'ERROR: Index p_index = 7 is out of bounds (size() = 3).'
$b = Get-ErrorKey 'ERROR: Index p_index = 12 is out of bounds (size() = 4).'
Assert-True ($a -ceq $b -and $a -ceq 'ERROR: Index p_index = N is out of bounds (size() = N).') "lines that differ only in numbers share a key: $a"
Assert-True ($a -cne (Get-ErrorKey 'ERROR: Index p_index = 7 is out of bounds (size() = 3).' 'res://enemy.gd')) 'the same message from a named script is another key'
Assert-True ((Get-ErrorKey 'ERROR: x' 'res://a.gd') -cne (Get-ErrorKey 'ERROR: x' 'res://b.gd')) 'the same message from two scripts: two keys'
Assert-True ((Get-ErrorKey 'ERROR: Cannot open file') -cne (Get-ErrorKey 'ERROR: Cannot load file')) 'different messages: different keys'
$k = Get-ErrorKey "`e[91mSCRIPT ERROR: Parse Error: x at res://levels/level2.tscn:41 in   res://ui/hud_3.gd:7`e[0m"
Assert-True ($k -ceq 'SCRIPT ERROR: Parse Error: x at res://levels/level2.tscn in res://ui/hud_3.gd') "colour codes and line numbers go, digits in res:// paths stay: $k"
$k = Get-ErrorKey 'ERROR: Node @Node2D@23 (<Object#9223372036854775807>) freed at 0x7f3a2c001b40, Vector2(1.5, -2)'
Assert-True ($k -ceq 'ERROR: Node @Node2D@N (<Object#N>) freed at X, Vector2(N, -N)') "node names, object ids and addresses are taken out, type names stay: $k"
Assert-True ((Get-ErrorKey ('ERROR: ' + ('x' * 500))).Length -eq 240) 'a key is at most 240 characters'

# --- Details: Godot 4.7.2 puts the location under the error line --------------------------------------------------------
# As Godot 4.7.2 printed them for tests/errorkeys-fixture's push_error and for a call on null.
$log = @(
    'Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org',
    'ERROR: Wave 7 spawned 21 enemies outside the arena',
    '   at: push_error (core/variant/variant_utility.cpp:1023)',
    '   GDScript backtrace (most recent call first):',
    '       [0] _ready (res://main.gd:7)',
    'ERROR: Wave 12 spawned 36 enemies outside the arena',
    '   at: push_error (core/variant/variant_utility.cpp:1023)',
    '   GDScript backtrace (most recent call first):',
    '       [0] _ready (res://main.gd:7)',
    "SCRIPT ERROR: Invalid access to property or key 'foo' on a base object of type 'Nil'.",
    '          at: _ready (res://main.gd:8)',
    'ERROR: Parameter "singleton" is null.',
    'ERROR: From a test helper',
    '   GDScript backtrace (most recent call first):',
    '       [0] fail (res://addons/gut/test.gd:90)',
    '       [1] test_spawn (res://test/test_spawn.gd:12)')
$details = @(Get-GodotErrorDetails $log)
Assert-True ($details.Count -eq 4) "known engine noise is left out: $($details.Count) error lines"
Assert-True ($details[0].Key -ceq 'ERROR: Wave N spawned N enemies outside the arena at res://main.gd' -and $details[0].Key -ceq $details[1].Key -and
    $details[0].File -eq 'res://main.gd' -and $details[0].Line -eq 7) "the same push_error with other numbers: one key, at the frame under it ($($details[0].Key))"
Assert-True ($details[2].File -eq 'res://main.gd' -and $details[2].Line -eq 8 -and $details[2].Key -like '*of type ''Nil''. at res://main.gd') "a script error takes its at: line ($($details[2].Key))"
Assert-True ($details[3].File -eq 'res://test/test_spawn.gd' -and $details[3].Line -eq 12) "frames in addons/ are skipped when the project has one: $($details[3].File)"

# --- A run's keys -----------------------------------------------------------------------------------------------------
$run = @($log) + @(
    '[godot-ci] Godot reported errors:',
    '  ERROR: Wave 7 spawned 21 enemies outside the arena',
    '================================================================',
    'handle_crash: Program crashed with signal 11',
    '[godot-ci] /root/.godot-ci/4.7.2-stable-mono/Godot_v4.7.2-stable_mono_linux.x86_64 was still running after 1800 s and was stopped (raise GODOT_CI_TIMEOUT if it needs longer)')
$keys = @(Get-RunErrorKeys $run @('soak key'))
Assert-True ($keys.Count -eq 6 -and $keys[0] -eq 'soak key' -and $keys[1] -ceq $details[0].Key) "distinct keys in order, given ones first; the kit's reprint without a location is not a second key: $($keys -join ' | ')"
Assert-True ($keys -ccontains 'Program crashed with signal 11' -and $keys -ccontains 'Godot_v4.7.2-stable_mono_linux.x86_64 was still running at the time limit and was stopped') 'a crash (signal kept) and a time-out are keys too'
Assert-True (@(Get-RunErrorKeys @(1..50 | ForEach-Object { "ERROR: message $([char](65 + $_ % 26))$([char](65 + [int][math]::Floor($_ / 26)))" })).Count -eq 20) 'a run keeps at most 20 keys'
Assert-True (@(Get-RunErrorKeys @('nothing wrong')).Count -eq 0) 'a clean log has no keys'
Enable-JsonMode 'build'
Set-EngineErrors $details
$json = @($script:JsonDoc['engineErrors'])
Assert-True ($json.Count -eq 4 -and $json[0].key -ceq $details[0].Key -and $json[0].file -eq 'res://main.gd' -and $json[0].line -eq 7 -and
    $json[0].message -eq 'ERROR: Wave 7 spawned 21 enemies outside the arena' -and $script:RunErrorKeys.Count -eq 4) 'engineErrors[] items carry message, file, line and key, and the keys reach the history'
$script:JsonMode = $false; $script:JsonDoc = [ordered]@{}; $script:RunErrorKeys.Clear()

# --- The history line gets the run's keys and commit -------------------------------------------------------------------
$project = Join-Path ([IO.Path]::GetTempPath()) "errorkeys-$PID"
New-Item -ItemType Directory -Force (Join-Path $project '.godot') | Out-Null
try {
    Start-RunLog (Join-Path $project 'test-results/godot-ci.log')
    Start-RunHistory 'build' $project
    foreach ($line in $log) { Write-RunLog $line }
    Add-RunHistory $false 'engine-errors'
    $script:RunLogWriter.Dispose(); $script:RunLogWriter = $null; $script:RunLogPath = $null
    $line = Get-Content -LiteralPath (Join-Path $project '.godot/godot-ci-history.jsonl') | ConvertFrom-Json
    Assert-True ($line.PSObject.Properties['commit'] -and $null -eq $line.commit -and @($line.errorKeys).Count -eq 3 -and $line.errorKeys[0] -ceq $details[0].Key) `
        "Add-RunHistory records the keys of the run log while it is still open, and commit null outside git: $(@($line.errorKeys) -join ' | ')"
} finally {
    Remove-Item -LiteralPath $project -Recurse -Force
}

# --- status: grouped by key -------------------------------------------------------------------------------------------
function New-Line([string]$Time, [string]$Command, [bool]$Ok, [string]$Commit, [string[]]$Keys) {
    [ordered]@{ time = $Time; command = $Command; ok = $Ok; commit = $Commit; errorKeys = @($Keys) } | ConvertTo-Json -Compress | ConvertFrom-Json
}
$history = @(
    ('{"time":"2026-10-01T09:00:00Z","command":"test","ok":false}' | ConvertFrom-Json),
    (New-Line '2026-10-02T09:00:00Z' 'test' $false 'aaa1111' @('K', 'background')),
    (New-Line '2026-10-03T09:00:00Z' 'build' $true 'aaa1111' @('background')),
    (New-Line '2026-10-10T09:00:00Z' 'export' $false 'bbb2222' @('K')),
    (New-Line '2026-10-11T09:00:00Z' 'test' $true 'bbb2222' @('passing only')),
    (New-Line '2026-10-21T09:00:00Z' 'test' $false 'ccc3333' @('K', 'N'))
)
$recurring = @(Get-RecurringErrors $history)
$kEntry = @($recurring | Where-Object { $_.key -ceq 'K' })
Assert-True ($kEntry.Count -eq 1 -and $kEntry[0].count -eq 3 -and $kEntry[0].failedRuns -eq 3 -and $kEntry[0].firstSeen.commit -eq 'aaa1111' -and
    ([datetime]$kEntry[0].firstSeen.time).ToUniversalTime().Day -eq 2 -and $kEntry[0].lastSeen.commit -eq 'ccc3333' -and (@($kEntry[0].commands) -join ',') -eq 'test,export') `
    "a key in 3 runs: count 3, first seen at aaa1111 on the 2nd, last at ccc3333, in test and export ($($kEntry | ConvertTo-Json -Compress -Depth 4))"
Assert-True ((@($recurring | ForEach-Object key) -join ',') -ceq 'K,N,background') "most recently seen first, keys of passing runs only left out: $(@($recurring | ForEach-Object key) -join ',')"
$bg = @($recurring | Where-Object { $_.key -eq 'background' })
Assert-True ($bg[0].count -eq 2 -and $bg[0].failedRuns -eq 1) 'count includes passing runs, failedRuns does not'
$older = @(Get-OlderErrors $history $recurring)
Assert-True ((@($older | ForEach-Object key) -join ',') -ceq 'K') "the latest failure's error first seen at an earlier commit is older than the change; the new one is not: $(@($older | ForEach-Object key) -join ',')"
$sameCommit = @($history[0..4]) + @((New-Line '2026-10-21T09:00:00Z' 'test' $false 'bbb2222' @('passing only')))
Assert-True (@(Get-OlderErrors $sameCommit @(Get-RecurringErrors $sameCommit)).Count -eq 0) 'an error first seen at the current commit is not older'
$noGit = @((New-Line '2026-10-01T09:00:00Z' 'test' $false $null @('K')), (New-Line '2026-10-21T08:00:00Z' 'test' $false $null @('L')),
    (New-Line '2026-10-21T09:00:00Z' 'test' $false $null @('K', 'L')))
Assert-True (((@(Get-OlderErrors $noGit @(Get-RecurringErrors $noGit)) | ForEach-Object key) -join ',') -ceq 'K') 'outside git, older means first seen more than a day before'
$passed = @($history) + @((New-Line '2026-10-22T09:00:00Z' 'test' $true 'ccc3333' @()))
Assert-True (@(Get-OlderErrors $passed @(Get-RecurringErrors $passed)).Count -eq 0) 'nothing is older when the latest run passed'

if ($NoGodot) {
    if ($failures.Count -gt 0) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
    Write-Host 'synthetic checks passed (-NoGodot: the kit was not run)'
    exit 0
}

# --- The kit on tests/errorkeys-fixture, in a git repository of its own --------------------------------------------------
$game = Join-Path ([IO.Path]::GetTempPath()) "errorkeys-fixture-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
Copy-Item -Recurse (Join-Path $PSScriptRoot 'errorkeys-fixture') $game
function Invoke-Git([string[]]$GitArgs) { & git -C $game -c user.name=test -c user.email=test@example.com @GitArgs 2>&1 | Out-Null; if ($LASTEXITCODE) { throw "git $GitArgs failed" } }
function Invoke-Kit([string[]]$KitArgs) {
    $extra = if ($KitArgs[0] -eq 'test') { @('-Runners', 'smoke', '-Results', (Join-Path $game 'test-results')) } else { @() }
    $out = pwsh -NoProfile -File $kit @KitArgs -Json -Quiet -Project $game @extra 2>$null
    return ($out | Out-String | ConvertFrom-Json)
}
$wave = 'ERROR: Wave N spawned N enemies outside the arena at res://main.gd'
try {
    Invoke-Git @('init', '-q'); Invoke-Git @('add', '-A'); Invoke-Git @('commit', '-q', '-m', 'one')
    $first = (& git -C $game rev-parse --short HEAD).Trim()
    $r = Invoke-Kit @('test')
    $line = @(Get-Content -LiteralPath (Join-Path $game '.godot/godot-ci-history.jsonl'))[-1] | ConvertFrom-Json
    Assert-True (-not $r.ok -and (@($line.errorKeys) -join ' | ') -ceq $wave -and $line.commit -eq $first) `
        "the smoke run printed the error twice with other numbers: one key, at commit $($line.commit) ($(@($line.errorKeys) -join ' | '))"

    Set-Content -LiteralPath (Join-Path $game 'notes.txt') -Value 'a change'
    Invoke-Git @('add', '-A'); Invoke-Git @('commit', '-q', '-m', 'two')
    $env:ERROR_KEYS_FIXTURE = '2'
    $r = Invoke-Kit @('test')
    $s = Invoke-Kit @('status')
    $byKey = @{}; foreach ($e in @($s.recurringErrors)) { $byKey[$e.key] = $e }
    $new = 'ERROR: The arena has no exit at res://main.gd'
    Assert-True ($byKey.ContainsKey($wave) -and $byKey[$wave].count -eq 2 -and $byKey[$wave].firstSeen.commit -eq $first -and $byKey.ContainsKey($new) -and $byKey[$new].count -eq 1) `
        "status: the old error in 2 runs since $first, the new one in 1 ($(@($s.recurringErrors | ForEach-Object { "$($_.key) x$($_.count)" }) -join '; '))"
    $warning = @($s.warnings | Where-Object { $_ -like '*first seen*' })
    Assert-True ($warning.Count -eq 1 -and $warning[0] -like "*commit $first*$wave*") "status warns that the old error predates the current commit, and only that one: $($warning -join ' / ')"
} finally {
    Remove-Item Env:ERROR_KEYS_FIXTURE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $game -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'error keys group a run''s errors across runs; the history records them with the commit; status shows recurrence and what predates the change'
exit 0
