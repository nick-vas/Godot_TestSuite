# A stand-in for the Claude Code CLI on the game programme (benchmark/game-benchmark.json): it does each task's work in the
# folder it runs in, the way a session would, well when $env:FAKE_GAME_MODE is 'good' and badly when it is 'bad', so the
# grader is tested against both. It also stands in for the judge (layers 3 and 4 of benchmark/PLAN.md). The prompt arrives on stdin; each call is appended to $env:FAKE_CLAUDE_LOG.
$arguments = @($args)
if ($arguments -contains '--version') { '9.9.9 (Claude Code)'; exit 0 }
$prompt = [Console]::In.ReadToEnd()
$good = $env:FAKE_GAME_MODE -eq 'good'
[ordered]@{ prompt = $prompt; cwd = (Get-Location).Path; seesGame = (Test-Path -LiteralPath 'project.godot')
    seesKit = (Test-Path -LiteralPath 'AGENTS.md') -or (Test-Path -LiteralPath 'benchmark'); args = $arguments } |
    ConvertTo-Json -Compress -Depth 4 | Add-Content -LiteralPath $env:FAKE_CLAUDE_LOG

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
