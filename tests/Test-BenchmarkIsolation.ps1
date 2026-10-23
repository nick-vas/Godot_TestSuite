# Self-test for the benchmark's isolation of sessions (benchmark/Isolation.ps1, benchmark/PLAN.md section 6), with the
# stand-in CLI (tests/game-benchmark/fake-game-claude.ps1) on the one-genre test programme: run with -Isolate, a session
# runs as a user made for the run and cannot read the benchmark, a hidden test or the folder beside its game, while its
# work is still graded; without it, the same probes can read them (so the probe is real). The session also leaves a
# process running, a link where the grader writes a hidden test and a git setting that runs a command: none may outlive
# the session or reach the runner. Needs Linux, root or passwordless sudo, and Godot (GODOT_BIN, or the kit installs
# it); elsewhere it says so and passes. Calls no model and costs nothing.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$bench = Join-Path $root 'benchmark/Invoke-TokenBenchmark.ps1'
$fake = Join-Path $PSScriptRoot 'game-benchmark/fake-game-claude.ps1'
$programme = Join-Path $PSScriptRoot 'game-benchmark/programme/programme.json'
$hidden = Join-Path $PSScriptRoot 'game-benchmark/programme/games/toy/gdscript/hidden/test_hidden_multiplier.gd'

if (-not $IsLinux) { Write-Host 'Sessions are isolated on Linux only; nothing to check here'; exit 0 }
$isRoot = (& id -u) -eq '0'
if (-not $isRoot) {
    & sudo -n true 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host 'Isolation needs root or passwordless sudo; nothing to check here'; exit 0 }
}

$work = Join-Path ([IO.Path]::GetTempPath()) "isolation-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$shared = Join-Path $work 'shared'
$privateTemp = Join-Path $work 'tmp'
New-Item -ItemType Directory -Force $shared, $privateTemp | Out-Null
# The log and the canary are where the session user can reach them: the log to write its calls, the canary to aim at.
& chmod 755 $work
& chmod 1777 $shared
$log = Join-Path $shared 'calls.jsonl'
$canary = Join-Path $shared 'canary.txt'
Set-Content -LiteralPath $log -Value $null -NoNewline
Set-Content -LiteralPath $canary -Value 'untouched' -NoNewline
& chmod 666 $log
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

if (-not $env:GODOT_BIN -or -not (Test-Path -LiteralPath $env:GODOT_BIN)) {
    $setup = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') setup -Json -Quiet -Project (Join-Path $root 'examples/gdscript') 2>$null
    $env:GODOT_BIN = @(Get-ChildItem -LiteralPath $(if ($env:GODOT_TOOLS_DIR) { $env:GODOT_TOOLS_DIR } else { Join-Path $HOME '.hyperdot' }) -Recurse -File |
        Where-Object { $_.Name -match '^Godot_v[\d.]+-stable(_mono)?_linux\.x86_64$' } | Sort-Object { $_.Name -match '_mono' } |
        Select-Object -First 1 | ForEach-Object FullName) | Select-Object -First 1
    Write-Host "Godot: $env:GODOT_BIN ($(@($setup).Count) line(s) from setup)"
}

$saved = @{}
$settings = [ordered]@{
    FAKE_CLAUDE_LOG = $log; TMPDIR = $privateTemp; FAKE_RUN_GODOT = '1'
    FAKE_PROBE = "$root/benchmark/PLAN.md|$hidden|..|$root"
    # What reaches the session: the CLI's credentials, and the names listed here; nothing else of the runner's.
    CLAUDE_CODE_OAUTH_TOKEN = 'sk-ant-oat-stand-in'; FAKE_NOT_PASSED = '1'
    HYPERDOT_ISOLATE_ENV = 'FAKE_GAME_MODE,FAKE_CLAUDE_LOG,FAKE_PROBE,FAKE_RUN_GODOT,FAKE_LINGER,FAKE_HOSTILE,FAKE_HOSTILE_LINK,FAKE_CANARY'
}
foreach ($name in @($settings.Keys) + @('FAKE_GAME_MODE', 'FAKE_LINGER', 'FAKE_HOSTILE', 'FAKE_HOSTILE_LINK', 'FAKE_CANARY', 'HYPERDOT_ISOLATE_VIA', 'HYPERDOT_ISOLATE')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}
foreach ($name in $settings.Keys) { [Environment]::SetEnvironmentVariable($name, $settings[$name]) }
$runner = [Environment]::UserName
$repoMode = (& stat -c '%a' $root).Trim()

# One run of the test programme; the sessions' calls are those the log gained, the judge's left out.
function Invoke-Run([string[]]$Arguments, [string]$Mode = 'good') {
    $env:FAKE_GAME_MODE = $Mode
    $before = @(Get-Content -LiteralPath $log).Count
    $out = & pwsh -NoProfile -File $bench -SpecPath $programme -Claude $fake -OutputDir (Join-Path $work "results-$Mode") -Repeat 1 -Json @Arguments 2>$null
    $code = $LASTEXITCODE
    $doc = @($out | Where-Object { $_ -match '^\{' }) | Select-Object -Last 1
    $json = if ($doc) { $doc | ConvertFrom-Json }
    $rows = if ($json) { @(Get-Content -LiteralPath (Join-Path $json.folder 'results.json') -Raw | ConvertFrom-Json) } else { @() }
    $calls = @(Get-Content -LiteralPath $log | Select-Object -Skip $before | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.prompt -notmatch '^You are grading' })
    return [pscustomobject]@{ Code = $code; Rows = $rows; Calls = $calls }
}
function Test-Probes($Call, [bool]$Readable) {
    return @($Call.probes.PSObject.Properties | Where-Object { [bool]$_.Value -ne $Readable }).Count -eq 0 -and @($Call.probes.PSObject.Properties).Count -eq 4
}

try {
    # Without isolation the session runs as the runner and reads everything the probe asks for: the probe works.
    $open = Invoke-Run @('-TaskId', 'toy.prototype.gdscript.fix-bug')
    Assert-True ($open.Code -eq 0 -and $open.Calls.Count -eq 1 -and $open.Calls[0].user -eq $runner) "without isolation the session is the runner ($(@($open.Calls | ForEach-Object user) -join ', '))"
    Assert-True ($open.Calls.Count -eq 1 -and (Test-Probes $open.Calls[0] $true)) 'without isolation it reads the benchmark, a hidden test, the folder beside its game and the checkout'

    # Isolated: graded as before, but the session cannot read any of it, and what it leaves behind dies with it.
    $env:FAKE_LINGER = '1'; $env:FAKE_HOSTILE = '1'; $env:FAKE_HOSTILE_LINK = 'test/test_hidden_multiplier.gd'; $env:FAKE_CANARY = $canary
    $iso = Invoke-Run @('-Tier', 'min', '-Isolate')
    foreach ($name in 'FAKE_LINGER', 'FAKE_HOSTILE', 'FAKE_HOSTILE_LINK', 'FAKE_CANARY') { [Environment]::SetEnvironmentVariable($name, $null) }
    Assert-True ($iso.Code -eq 0 -and $iso.Rows.Count -eq 2 -and @($iso.Rows | Where-Object success).Count -eq 2) "isolated, good work still passes its grading ($(@($iso.Rows | Where-Object { -not $_.success } | ForEach-Object { "$($_.task): $($_.reasons)" }) -join '; '))"
    $users = @($iso.Calls | ForEach-Object user | Sort-Object -Unique)
    Assert-True ($iso.Calls.Count -eq 2 -and $users.Count -eq 1 -and $users[0] -like 'hyperdot-s*' -and $users[0] -ne $runner) "every session runs as the run's own user ($($users -join ', '))"
    Assert-True (@($iso.Calls | Where-Object { -not (Test-Probes $_ $false) }).Count -eq 0) 'isolated, it cannot read the benchmark, a hidden test, the folder beside its game or the checkout'
    Assert-True (@($iso.Calls | Where-Object { -not $_.seesGame }).Count -eq 0) 'isolated, it works in its game'
    Assert-True (@($iso.Calls | Where-Object { $_.token -ne 'sk-ant-oat-stand-in' -or $_.notPassed }).Count -eq 0) 'the CLI''s credentials reach the session; the runner''s other variables do not'
    Assert-True (@($iso.Calls | Where-Object { $_.godotVersion -notmatch '^4\.' }).Count -eq 0) "the session user can run Godot ($(@($iso.Calls | ForEach-Object godotVersion) -join ', '))"
    Assert-True (@($iso.Calls | Where-Object { $_.home -notlike "$privateTemp/hyperdot-isolated-*" }).Count -eq 0) 'its HOME is the run''s own'
    Assert-True ((Get-Content -LiteralPath $canary -Raw) -eq 'untouched') 'the grader does not write a hidden test through a link the session left'
    Assert-True (-not (Test-Path -LiteralPath "$canary.git-ran")) 'the grader''s git does not run what the session configured'
    $uid = @($iso.Calls | ForEach-Object uid | Select-Object -First 1)
    Assert-True ($uid -and @(& ps -eo 'uid=' | ForEach-Object Trim | Where-Object { $_ -eq "$uid" }).Count -eq 0) 'nothing the session started is still running'
    Assert-True (-not (& getent passwd $users[0])) 'the session user is removed'
    Assert-True ((& stat -c '%a' $root).Trim() -eq $repoMode) "the checkout's mode is restored ($repoMode)"
    Assert-True (@(Get-ChildItem -LiteralPath $privateTemp -Force -Filter 'hyperdot-*').Count -eq 0) 'the run leaves none of its folders in the temporary folder'

    # The other launcher (sudo), with the plugin: the session reads the kit's copy it loads, without the benchmark;
    # bad work still fails on its grading.
    if (Get-Command sudo -CommandType Application -ErrorAction SilentlyContinue) {
        $env:HYPERDOT_ISOLATE_VIA = 'sudo'
        $sudo = Invoke-Run @('-TaskId', 'toy.prototype.gdscript.fix-bug', '-Isolate', '-Plugin') 'bad'
        $env:HYPERDOT_ISOLATE_VIA = $null
        $call = @($sudo.Calls) | Select-Object -First 1
        Assert-True ($call -and $call.user -like 'hyperdot-s*' -and (Test-Probes $call $false)) 'through sudo too, the session is the run''s user and reads none of it'
        Assert-True ($call -and $call.pluginReadable -eq $true -and $call.pluginHasBenchmark -eq $false) 'with the plugin it reads the kit''s copy, which has no benchmark'
        Assert-True ($sudo.Rows.Count -eq 1 -and -not $sudo.Rows[0].success -and $sudo.Rows[0].gameReasons -match 'tests fail') "bad work fails its grading ($(if ($sudo.Rows.Count) { $sudo.Rows[0].gameReasons }))"
    }
    # A dry run makes no user.
    $before = @(& getent passwd | Where-Object { $_ -like 'hyperdot-s*' }).Count
    $dry = & pwsh -NoProfile -File $bench -SpecPath $programme -Claude $fake -Tier min -Isolate -DryRun 2>$null
    Assert-True ($LASTEXITCODE -eq 0 -and @(& getent passwd | Where-Object { $_ -like 'hyperdot-s*' }).Count -eq $before) 'a dry run isolates nothing'
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failures.Count) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All isolation checks passed'
exit 0
