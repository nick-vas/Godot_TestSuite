# A stand-in for the Claude Code CLI on the game programme (benchmark/game-benchmark.json): it does each task's work in the
# folder it runs in, the way a session would, well when $env:FAKE_GAME_MODE is 'good' and badly when it is 'bad', so the
# grader is tested against both. It also stands in for the judge (layers 3 and 4 of benchmark/PLAN.md). The prompt arrives on stdin; each call is appended to $env:FAKE_CLAUDE_LOG.
#
# For the isolation self-test (tests/Test-BenchmarkIsolation.ps1) it also reports who it ran as and whether it could read
# each path in $env:FAKE_PROBE ('|'-separated; '..' is the folder its game is in), runs Godot with FAKE_RUN_GODOT, and on
# request misbehaves: FAKE_LINGER leaves a process running, FAKE_HOSTILE plants a link at the path FAKE_HOSTILE_LINK
# pointing to FAKE_CANARY and a git setting that would run a command when the grader runs git. For the field test (tests/Test-FieldTest.ps1) it does the
# field templates, restoring the game's code from $env:FAKE_FIELD_ORIGINAL when it is good.
$arguments = @($args)
if ($arguments -contains '--version') { '9.9.9 (Claude Code)'; exit 0 }
$prompt = [Console]::In.ReadToEnd()
$good = $env:FAKE_GAME_MODE -eq 'good'
function Test-Readable([string]$Path) {
    try {
        if (Test-Path -LiteralPath $Path -PathType Container) { Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Out-Null }
        else { [IO.File]::ReadAllText($Path) | Out-Null }
        return $true
    } catch { return $false }
}
$probes = [ordered]@{}
foreach ($path in @(if ($env:FAKE_PROBE) { $env:FAKE_PROBE -split '\|' | Where-Object { $_ } })) {
    $probes[$path] = Test-Readable $(if ($path -eq '..') { Split-Path (Get-Location).Path } else { $path })
}
$pluginAt = [Array]::IndexOf($arguments, '--plugin-dir')
[ordered]@{ prompt = $prompt; cwd = (Get-Location).Path; seesGame = (Test-Path -LiteralPath 'project.godot')
    seesKit = (Test-Path -LiteralPath 'AGENTS.md') -or (Test-Path -LiteralPath 'benchmark'); args = $arguments
    user = [Environment]::UserName; uid = $(if ($IsLinux) { "$(& id -u)" }); home = $HOME
    godotVersion = $(if ($env:FAKE_RUN_GODOT) { "$(& $env:GODOT_BIN --headless --version 2>$null)".Trim() }); probes = $probes; godotBin = $env:GODOT_BIN
    pluginReadable = $(if ($pluginAt -ge 0) { Test-Readable (Join-Path $arguments[$pluginAt + 1] 'AGENTS.md') } else { $null })
    pluginHasBenchmark = $(if ($pluginAt -ge 0) { Test-Path -LiteralPath (Join-Path $arguments[$pluginAt + 1] 'benchmark') } else { $null })
    token = [string]$env:CLAUDE_CODE_OAUTH_TOKEN; notPassed = [bool]$env:FAKE_NOT_PASSED } |
    ConvertTo-Json -Compress -Depth 4 | Add-Content -LiteralPath $env:FAKE_CLAUDE_LOG
# Misbehaving is for sessions; the judge runs as the runner, outside any isolation.
$judging = $prompt -match '^You are (grading|comparing)'
if ($env:FAKE_LINGER -and -not $judging) { Start-Process -FilePath 'sleep' -ArgumentList '600' | Out-Null }
if ($env:FAKE_HOSTILE -and -not $judging) {
    New-Item -ItemType Directory -Force (Split-Path (Join-Path $PWD $env:FAKE_HOSTILE_LINK)) | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $PWD $env:FAKE_HOSTILE_LINK) -Target $env:FAKE_CANARY -Force | Out-Null
    & git config core.fsmonitor "touch '$($env:FAKE_CANARY).git-ran'" 2>$null
}

function Edit-File([string]$Path, [string]$Find, [string]$Replace) {
    $text = [IO.File]::ReadAllText((Join-Path $PWD $Path))
    [IO.File]::WriteAllText((Join-Path $PWD $Path), $text.Replace($Find, $Replace))
}
# GDScript indents with tabs: each four leading spaces of the text here becomes one.
function Write-File([string]$Path, [string]$Text) {
    $tabbed = [regex]::Replace(($Text -replace "`r", ''), '(?m)^(?:    )+', { param($m) "`t" * ($m.Value.Length / 4) })
    [IO.File]::WriteAllText((Join-Path $PWD $Path), $tabbed)
}

$answer = 'Done.'
# As a judge: a score from $env:FAKE_JUDGE_SCORE (5 by default); comparing, the work that says GOOD wins.
if ($prompt -match '^You are grading') {
    $answer = "{`"score`": $(if ($env:FAKE_JUDGE_SCORE) { $env:FAKE_JUDGE_SCORE } else { 5 }), `"why`": `"stand-in`"}"
} elseif ($prompt -match '^You are comparing') {
    $a = [regex]::Match($prompt, '(?s)WORK A BEGINS(.*?)WORK A ENDS').Groups[1].Value
    $b = [regex]::Match($prompt, '(?s)WORK B BEGINS(.*?)WORK B ENDS').Groups[1].Value
    $better = if ($a -match 'GOOD' -and $b -notmatch 'GOOD') { 'A' } elseif ($b -match 'GOOD' -and $a -notmatch 'GOOD') { 'B' } else { 'even' }
    $answer = "{`"better`": `"$better`", `"why`": `"stand-in`"}"
} else {
switch -Regex ($prompt) {
    'A test in this Godot' {
        $answer = 'test_every_fifth_hit_raises_the_multiplier in test/test_score.gd, line 7, expected 25 but got 20. The test is wrong: the fifth hit doubles 10 to 20.'
        # The bad session "fixes" the test it was told to leave alone.
        if (-not $good) { Edit-File 'test/test_score.gd' 'score.hit(10), 25)' 'score.hit(10), 20)' }
    }
    'multiplier no longer goes up' {
        if ($good) { Edit-File 'score.gd' 'combo / 6' 'combo / 5' }
        else { Edit-File 'test/test_score.gd' 'test_main_scene_scores_on_ready' 'skip_main_scene_scores_on_ready' }
        $answer = 'Fixed the multiplier step in score.gd; the tests pass.'
    }
    'Add a best score' {
        if ($good) {
            Edit-File 'score.gd' "var combo := 0`n" "var combo := 0`nvar best := 0`n"
            Edit-File 'score.gd' "`tpoints += gained`n" "`tpoints += gained`n`tbest = maxi(best, points)`n"
            Add-Content -LiteralPath 'score.gd' -Value "`nfunc reset() -> void:`n`tpoints = 0`n`tcombo = 0" -NoNewline
            Write-File 'test/test_best.gd' @'
extends GutTest

func test_reset_keeps_the_best():
    var score := Score.new()
    score.hit(10)
    score.reset()
    assert_eq(score.points, 0)
    assert_eq(score.best, 10)
'@
        } else {
            Edit-File 'score.gd' "var combo := 0`n" "var combo := 0`nvar best := 0`n"
        }
        $answer = 'Added best and reset() with a test.'
    }
    'thin tests' {
        if ($good) {
            Write-File 'test/test_score_rules.gd' @'
extends GutTest

func test_the_fifth_hit_is_the_first_double():
    var score := Score.new()
    for i in 4:
        assert_eq(score.hit(10), 10)
    assert_eq(score.hit(10), 20)

func test_a_miss_restarts_the_combo_and_keeps_the_points():
    var score := Score.new()
    for i in 5:
        score.hit(10)
    score.miss()
    assert_eq(score.points, 60)
    assert_eq(score.hit(10), 10)

func test_twelve_hits_add_up():
    var score := Score.new()
    for i in 12:
        score.hit(10)
    assert_eq(score.points, 230)
'@
        } else {
            Write-File 'test/test_score_rules.gd' @'
extends GutTest

func test_a_hit_scores():
    var score := Score.new()
    assert_true(score.hit(10) > 0)
'@
        }
        $answer = 'Wrote test/test_score_rules.gd.'
    }
    'failed its tests since a recent change|can no longer finish it since a recent change' {
        # The field test's planted bugs: the good session puts the game's own code back as it was.
        if ($good) {
            $original = $env:FAKE_FIELD_ORIGINAL
            foreach ($file in @(Get-ChildItem -LiteralPath $original -Recurse -File -Include '*.gd', '*.cs' | Where-Object { $_.FullName -notmatch '[\\/](addons|\.godot|bin|obj)[\\/]' })) {
                $relative = [IO.Path]::GetRelativePath($original, $file.FullName)
                $here = Join-Path $PWD $relative
                if ((Test-Path -LiteralPath $here) -and [IO.File]::ReadAllText($here) -ne [IO.File]::ReadAllText($file.FullName)) { Copy-Item -LiteralPath $file.FullName -Destination $here -Force }
            }
        }
        $answer = 'Found the bug and fixed it; the tests pass.'
    }
    'has too few tests of (.+?): bugs' {
        # The good session copies the tests of the named code into new files (C# classes renamed); the bad one writes a
        # test that checks nothing.
        $names = @($Matches[1] -split ', ' | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) })
        $tests = @(Get-ChildItem -LiteralPath $PWD -Recurse -File -Include '*.gd', '*.cs' | Where-Object {
                $_.FullName -notmatch '[\\/](addons|\.godot|bin|obj)[\\/]' -and ([IO.File]::ReadAllText($_.FullName) -match '(?m)^extends\s+GutTest|\[(Test|Fact|TestCase|Theory)\b')
            })
        if ($good) {
            $mine = @($tests | Where-Object { $t = [IO.File]::ReadAllText($_.FullName); @($names | Where-Object { $t -match [regex]::Escape($_) }).Count })
            if ($mine.Count -eq 0) { $mine = $tests }
            foreach ($test in $mine) {
                $copy = Join-Path $test.DirectoryName ($test.BaseName + 'More' + $test.Extension)
                $text = [IO.File]::ReadAllText($test.FullName)
                if ($test.Extension -eq '.cs') {
                    # Every class the file declares gets a new name, with its constructors and the file's references to it.
                    foreach ($class in @([regex]::Matches($text, '\bclass\s+(\w+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)) {
                        $text = [regex]::Replace($text, "\b$class\b", "${class}More")
                    }
                }
                [IO.File]::WriteAllText($copy, $text)
            }
        } elseif (Test-Path -LiteralPath (Join-Path $PWD 'addons/gut')) {
            Write-File 'test/test_more.gd' "extends GutTest`n`nfunc test_something():`n    assert_true(true)`n"
        }
        $answer = 'Wrote new tests.'
    }
    'Hyperdot''s checks report problems' {
        if ($good -and (Test-Path -LiteralPath 'assets.json')) { Remove-Item -LiteralPath 'assets.json' -Force }
        $answer = 'doctor is green.'
    }
    'Designers want' {
        Edit-File 'main.gd' "var score := Score.new()`n" "@export var hit_value := 10`n`nvar score := Score.new()`n"
        if ($good) { Edit-File 'main.gd' 'score.hit(10)' 'score.hit(hit_value)' }
        $answer = 'hit_value is exported.'
    }
}
}
[ordered]@{
    type = 'result'; subtype = 'success'; is_error = $false; result = $answer; num_turns = 4; ttft_ms = 150; duration_ms = 900
    total_cost_usd = 0.01; usage = [ordered]@{ input_tokens = 3; cache_creation_input_tokens = 1000; cache_read_input_tokens = 5000; output_tokens = 40 }
    modelUsage = [ordered]@{ 'claude-fake-1' = [ordered]@{ inputTokens = 3; outputTokens = 40 } }
} | ConvertTo-Json -Compress -Depth 5
