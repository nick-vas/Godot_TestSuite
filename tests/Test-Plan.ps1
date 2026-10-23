#!/usr/bin/env pwsh
# Self-test of the plan's gates on a fresh plan: slice.debt and prototype.trailer are automatic and turn true when
# docs/TECH-DEBT.md and docs/TRAILER.md exist (and `plan -Do done` refuses them), slice.budget is manual and names a real
# `bench` command, the trailer template asks what its gate says, and every gate id, template and hyperdot.ps1 flag that
# the plan or any skill quotes exists. The release timeline (plan.json "release") warns on fixed days when Steam's dates
# cannot be kept, and `plan -Json` reports it. The `tests` gate and doctor's test check
# count test frameworks only (not data tables or flows). A hand-broken plan.json fails `plan` with invalid-plan and is a
# warning in `status`. `init` never overwrites an existing test/test_example.gd. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$templates = Join-Path $root 'ci/godot/templates'
$dir = Join-Path ([IO.Path]::GetTempPath()) "plan-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-PlanJson([string[]]$Arguments) {
    return pwsh -NoProfile -File $ci plan -Json -Project $dir @Arguments 2>$null | ConvertFrom-Json
}

$template = Get-Content -LiteralPath (Join-Path $templates 'plan.json') -Raw | ConvertFrom-Json -Depth 10
$gateIds = @(foreach ($phase in $template.phases) { foreach ($gate in $phase.gates) { $gate.id } })

# Flags quoted after "hyperdot.ps1 <command>" in a gate's text must be parameters of the script.
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ci, [ref]$null, [ref]$null)
$parameters = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($phase in $template.phases) {
    foreach ($gate in $phase.gates) {
        foreach ($quote in [regex]::Matches($gate.text, 'hyperdot\.ps1 \w+(?<rest>[^:;,)]*)')) {
            foreach ($flag in [regex]::Matches($quote.Groups['rest'].Value, '(?<=\s)-(?<name>[A-Za-z]+)')) {
                Assert-True ($flag.Groups['name'].Value -in $parameters) "$($gate.id) quotes -$($flag.Groups['name'].Value), a hyperdot.ps1 parameter"
            }
        }
    }
}

# Gate ids any skill names exist in the template (plan.json is copied once, so a renamed gate would strand them).
foreach ($skillFile in @(Get-ChildItem -LiteralPath (Join-Path $root '.agents/skills') -Filter 'SKILL.md' -Recurse)) {
    $skill = Get-Content -LiteralPath $skillFile.FullName -Raw
    foreach ($quoted in [regex]::Matches($skill, '`(?<id>(concept|prototype|slice|production|beta|launch|post)\.[a-z0-9]+)`')) {
        Assert-True ($quoted.Groups['id'].Value -in $gateIds) "$($skillFile.Directory.Name) names gate $($quoted.Groups['id'].Value), which plan.json has"
    }
}

# Templates the planning and store-page skills tell an agent to copy exist.
foreach ($skillName in 'godot-game-plan', 'godot-store-page') {
    $text = Get-Content -LiteralPath (Join-Path $root ".agents/skills/$skillName/SKILL.md") -Raw
    foreach ($quoted in [regex]::Matches($text, 'ci/godot/templates/(?<file>[A-Za-z0-9._-]+)')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $templates $quoted.Groups['file'].Value)) "$skillName names templates/$($quoted.Groups['file'].Value), which exists"
    }
}
$planSkill = Get-Content -LiteralPath (Join-Path $root '.agents/skills/godot-game-plan/SKILL.md') -Raw
Assert-True ($planSkill -match 'prototype\.trailer') 'godot-game-plan explains prototype.trailer'

# The trailer template asks what the gate promises, in the talk's order: genre, then hook, content last; three standout
# moments; a feedback column for every mechanic.
$trailerPath = Join-Path $templates 'TRAILER.md'
$trailer = (Test-Path -LiteralPath $trailerPath) ? (Get-Content -LiteralPath $trailerPath -Raw) : ''
Assert-True ($trailer -ne '') 'templates/TRAILER.md exists'
$genre = $trailer.IndexOf('| Genre (first 5 seconds)'); $hook = $trailer.IndexOf('| Hook'); $content = $trailer.IndexOf('| Content (last')
Assert-True ($genre -ge 0 -and $hook -gt $genre -and $content -gt $hook) 'the trailer template orders genre (first 5 seconds), hook, then content'
$moments = [regex]::Match($trailer, '(?s)## Three standout moments\r?\n(?<body>.*?)(\r?\n## |\z)')
Assert-True ($moments.Success -and @([regex]::Matches($moments.Groups['body'].Value, '(?m)^[1-3]\.')).Count -eq 3) 'the trailer template has three standout moments to fill'
Assert-True ($trailer -match '(?m)^\| Mechanic \|.*\| On-screen feedback a viewer sees \|') 'the trailer template pairs each mechanic with its on-screen feedback'

# The release timeline (plan.json "release"), on fixed days: Steam's 21 days after the fee, 2 weeks of Coming Soon,
# 7 business days per review (the store page before the build), the date lock, and the Next Fest demo deadline.
foreach ($lib in 'Common', 'Plan') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$fields = @($template.release.PSObject.Properties.Name)
Assert-True (@($script:ReleaseDateFields | Where-Object { $_ -notin $fields }).Count -eq 0 -and $fields -contains 'pressPreview') "the plan template has every release field: $($fields -join ', ')"
Assert-True ((Get-BusinessDayCount ([datetime]'2027-03-04') ([datetime]'2027-03-15')) -eq 7 -and (Get-BusinessDayBefore ([datetime]'2027-03-15') 7) -eq [datetime]'2027-03-04') 'business days skip the weekend'

$onTime = Get-ReleaseTimeline ([pscustomobject]@{ date = '2027-03-15'; steamFeePaid = '2027-01-04'; comingSoon = '2026-12-01'; storePageSubmitted = '2026-11-16'
        buildSubmitted = $null; nextFest = '2027-02-22'; demoSubmitted = '2027-01-25'; pressPreview = $false }) ([datetime]'2027-01-04')
$t = $onTime.timeline
Assert-True ($onTime.warnings.Count -eq 0) "a timeline that keeps every rule has no warnings: $($onTime.warnings -join ' | ')"
Assert-True ($t.date -eq '2027-03-15' -and $t.daysLeft -eq 70 -and $t.businessDaysLeft -eq 50 -and -not $t.dateLocked) "days and business days left: $($t | ConvertTo-Json -Compress)"
Assert-True ($t.deadlines.steamFee -eq '2027-02-22' -and $t.deadlines.comingSoon -eq '2027-03-01' -and $t.deadlines.buildReview -eq '2027-03-04' -and
    $t.deadlines.storePageReview -eq '2026-11-20' -and $t.deadlines.dateLock -eq '2027-03-01' -and $t.deadlines.demoReview -eq '2027-02-01') "deadlines: $($t.deadlines | ConvertTo-Json -Compress)"

$late = Get-ReleaseTimeline ([pscustomobject]@{ date = '2027-03-15'; steamFeePaid = '2027-03-01'; comingSoon = '2027-03-05'; storePageSubmitted = '2027-03-01'
        nextFest = '2027-02-22'; demoSubmitted = '2027-02-10' }) ([datetime]'2027-03-08')
foreach ($expected in @(
        @('app fee was paid on 2027-03-01, 14 days before release.*at least 21 days', 'a fee paid 14 days before release warns'),
        @('Coming Soon page goes live on 2027-03-05, 10 days before release.*at least 2 weeks', 'Coming Soon 10 days before release warns'),
        @('store page was submitted for review 4 business day\(s\) before its Coming Soon date', 'a store page submitted 4 business days ahead warns'),
        @('^5 business day\(s\) left before release and release\.buildSubmitted is not set', 'no build submitted with 5 business days left warns'),
        @('Next Fest demo was submitted on 2027-02-10, after the 2027-02-01 deadline \(3 weeks', 'a demo submitted after the 3-week deadline warns'))) {
    Assert-True (@($late.warnings | Where-Object { $_ -match $expected[0] }).Count -eq 1) $expected[1]
}
Assert-True ($late.warnings.Count -eq 5) "nothing else: $($late.warnings -join ' | ')"
Assert-True ($late.timeline.dateLocked -and @($late.notes | Where-Object { $_ -match 'is locked' }).Count -eq 1) 'a week before release the date is locked (a note, not a warning)'

$unset = Get-ReleaseTimeline ([pscustomobject]@{ date = '2027-03-15'; comingSoon = 'next week' }) ([datetime]'2027-03-08')
foreach ($expected in "release.comingSoon 'next week' is not a date", 'release.steamFeePaid is not set', 'release.comingSoon is not set', 'release.buildSubmitted is not set') {
    Assert-True (@($unset.warnings | Where-Object { $_.Contains($expected) }).Count -eq 1) "unset dates close to release warn: $expected"
}
Assert-True ($unset.warnings.Count -eq 4) "nothing else when dates are unset: $($unset.warnings -join ' | ')"

$order = Get-ReleaseTimeline ([pscustomobject]@{ date = '2027-06-01'; steamFeePaid = '2027-01-04'; comingSoon = '2027-02-01'; storePageSubmitted = '2027-05-03'
        buildSubmitted = '2027-04-01'; nextFest = '2027-06-14'; pressPreview = $true }) ([datetime]'2027-01-04')
Assert-True (@($order.warnings | Where-Object { $_ -match 'build was submitted for review before the store page' }).Count -eq 1) 'a build submitted before the store page warns'
Assert-True (@($order.warnings | Where-Object { $_ -match 'Next Fest \(2027-06-14\) is on or after release' }).Count -eq 1) 'a Next Fest after release warns'
Assert-True ($order.timeline.deadlines.demoReview -eq '2027-05-10') 'the press preview moves the demo deadline to 5 weeks before'
$none = Get-ReleaseTimeline ([pscustomobject]@{ date = $null }) ([datetime]'2027-01-04')
Assert-True ($null -eq $none.timeline -and $none.warnings.Count -eq 0) 'no release date, no timeline'

try {
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Plan Fixture""`n"
    pwsh -NoProfile -File $ci plan -Do init -Project $dir 2>$null | Out-Null
    $planPath = Join-Path $dir 'plan/plan.json'
    Assert-True (Test-Path -LiteralPath $planPath) 'plan -Do init writes plan/plan.json'

    $fresh = Get-Content -LiteralPath $planPath -Raw

    # The prototype phase: concept dropped from this copy, so the prototype is the current phase.
    $plan = $fresh | ConvertFrom-Json -Depth 10
    $plan.phases = @($plan.phases | Where-Object id -eq 'prototype')
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
    $d = Invoke-PlanJson @()
    $next = @($d.nextActions)
    $ids = @($next | ForEach-Object id)
    $trailerGate = $next | Where-Object id -eq 'prototype.trailer'
    Assert-True ($d.ok -and $d.currentPhase.id -eq 'prototype') 'the prototype is the current phase'
    Assert-True ($trailerGate -and $trailerGate.auto -and $trailerGate.check -eq 'file:docs/TRAILER.md') 'prototype.trailer is open and checked automatically from docs/TRAILER.md'
    Assert-True ($trailerGate -and $trailerGate.text -match 'genre' -and $trailerGate.text -match 'hook' -and
        $trailerGate.text -match 'standout moments' -and $trailerGate.text -match 'on-screen feedback') 'prototype.trailer names genre, hook, standout moments and on-screen feedback'
    Assert-True ($trailerGate -and [array]::IndexOf($ids, 'prototype.trailer') -lt [array]::IndexOf($ids, 'prototype.loop') -and
        [array]::IndexOf($ids, 'prototype.trailer') -lt [array]::IndexOf($ids, 'prototype.verdict')) 'the trailer is written before the loop is built and before the verdict'
    $refused = Invoke-PlanJson @('-Do', 'done', '-Id', 'prototype.trailer')
    Assert-True (-not $refused.ok -and $refused.error.code -eq 'auto-gate') 'plan -Do done refuses prototype.trailer (auto-gate)'
    New-Item -ItemType Directory -Force (Join-Path $dir 'docs') | Out-Null
    if ($trailer) { Set-Content -LiteralPath (Join-Path $dir 'docs/TRAILER.md') -Value $trailer.Replace('{{GAME}}', 'Plan Fixture') }
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'prototype.trailer' -notin @($d.nextActions | ForEach-Object id)) 'prototype.trailer is done once docs/TRAILER.md exists'

    # Earlier phases are the user's to finish; dropping them from this copy makes the slice the current phase.
    $plan = $fresh | ConvertFrom-Json -Depth 10
    $plan.phases = @($plan.phases | Where-Object id -eq 'vertical-slice')
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8

    $d = Invoke-PlanJson @()
    $next = @($d.nextActions)
    $ids = @($next | ForEach-Object id)
    $debt = $next | Where-Object id -eq 'slice.debt'
    $budget = $next | Where-Object id -eq 'slice.budget'
    $verdict = $next | Where-Object id -eq 'slice.verdict'
    Assert-True ($d.ok -and $d.currentPhase.id -eq 'vertical-slice') 'the vertical slice is the current phase'
    Assert-True ($debt -and $debt.auto -and $debt.check -eq 'file:docs/TECH-DEBT.md') 'slice.debt is open and checked automatically from docs/TECH-DEBT.md'
    Assert-True ($budget -and -not $budget.auto -and $budget.text -match 'bench -Scene \S+.* -BudgetMs ' -and $budget.text -match 'level of detail') 'slice.budget is manual and names bench -Scene ... -BudgetMs at production density'
    Assert-True ($verdict -and $verdict.text -match 'tech demo' -and $verdict.text -match 'tech debt') 'slice.verdict weighs the experience and the tech debt'
    Assert-True ([array]::IndexOf($ids, 'slice.debt') -lt [array]::IndexOf($ids, 'slice.verdict') -and
        [array]::IndexOf($ids, 'slice.budget') -lt [array]::IndexOf($ids, 'slice.verdict')) 'the debt and budget gates come before the verdict'

    $refused = Invoke-PlanJson @('-Do', 'done', '-Id', 'slice.debt')
    Assert-True (-not $refused.ok -and $refused.error.code -eq 'auto-gate') 'plan -Do done refuses slice.debt (auto-gate)'

    New-Item -ItemType Directory -Force (Join-Path $dir 'docs') | Out-Null
    Copy-Item -LiteralPath (Join-Path $templates 'TECH-DEBT.md') (Join-Path $dir 'docs/TECH-DEBT.md')
    $doneBefore = @($d.phases)[0].gatesDone
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'slice.debt' -notin @($d.nextActions | ForEach-Object id) -and @($d.phases)[0].gatesDone -eq $doneBefore + 1) 'slice.debt is done once docs/TECH-DEBT.md exists'

    $d = Invoke-PlanJson @('-Do', 'done', '-Id', 'slice.budget')
    Assert-True ($d.ok -and 'slice.budget' -notin @($d.nextActions | ForEach-Object id)) 'slice.budget is marked done by hand'

    # plan -Do reopen undoes done for a manual gate; an automatic gate, an unknown gate and a missing -Id are refused.
    $d = Invoke-PlanJson @('-Do', 'reopen', '-Id', 'slice.budget')
    Assert-True ($d.ok -and 'slice.budget' -in @($d.nextActions | ForEach-Object id)) 'plan -Do reopen opens slice.budget again'
    $gate = @((Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json).phases.gates | Where-Object id -eq 'slice.budget')[0]
    Assert-True (-not $gate.PSObject.Properties['done']) 'and plan.json no longer marks it done'
    $d = Invoke-PlanJson @('-Do', 'reopen', '-Id', 'slice.budget')
    Assert-True ($d.ok -and 'slice.budget' -in @($d.nextActions | ForEach-Object id)) 'reopening an open gate changes nothing'
    foreach ($case in @(@('slice.debt', 'auto-gate'), @('no.such.gate', 'unknown-gate'), @('', 'invalid-arguments'))) {
        $refused = Invoke-PlanJson @('-Do', 'reopen', '-Id', $case[0])
        Assert-True (-not $refused.ok -and $refused.error.code -eq $case[1]) "plan -Do reopen -Id '$($case[0])' fails with $($case[1]): $(if (-not $refused.ok) { $refused.error.code })"
    }
    $d = Invoke-PlanJson @('-Do', 'done', '-Id', 'slice.budget')
    Assert-True ($d.ok -and 'slice.budget' -notin @($d.nextActions | ForEach-Object id)) 'and it can be marked done again'

    # plan -Json reports the release timeline; five days out with no other date, the app fee is flagged and the date locked.
    Assert-True ($null -eq $d.release) 'a plan without a release date reports no release'
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 10
    $plan.release.date = [datetime]::UtcNow.Date.AddDays(5).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and $d.release.daysLeft -eq 5 -and $d.release.dateLocked -eq $true -and $d.release.deadlines.steamFee) "plan -Json reports the release: $($d.release | ConvertTo-Json -Compress)"
    Assert-True (@($d.warnings | Where-Object { $_ -match 'release\.steamFeePaid is not set' }).Count -eq 1) "plan warns that the app fee is not recorded five days before release: $($d.warnings -join ' | ')"

    # The tests gate and doctor's test check count test frameworks only: data tables and flows are checks, not tests.
    Set-Content -LiteralPath (Join-Path $dir 'data.json') -Value '{}'
    Set-Content -LiteralPath (Join-Path $dir 'start.flow.json') -Value '{ "steps": [] }'
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'slice.tests' -in @($d.nextActions | ForEach-Object id)) 'slice.tests stays open with only the data and flows runners'
    $doctor = pwsh -NoProfile -File $ci doctor -Json -Project $dir 2>$null | ConvertFrom-Json
    Assert-True (@($doctor.checks | Where-Object { $_.status -eq 'WARN' -and $_.message -match '^No tests found' }).Count -eq 1) "doctor warns that there are no tests: $(@($doctor.checks | Where-Object { $_.message -match 'test' } | ForEach-Object message) -join ' | ')"
    Set-Content -LiteralPath (Join-Path $dir 'test_paddle.gd') -Value "extends GutTest`n`nfunc test_paddle():`n`tassert_true(true)`n"
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'slice.tests' -notin @($d.nextActions | ForEach-Object id)) 'slice.tests is done once a GUT test exists'
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

# A day-first culture (Greek here) must read the phase's start time back: it once failed with "String '10/23/2026
# 05:57:27' was not recognized as a valid DateTime" on every plan command after init.
$culture = Join-Path ([IO.Path]::GetTempPath()) "plan-culture-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force $culture | Out-Null
    Set-Content -LiteralPath (Join-Path $culture 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Culture""`n"
    $command = "[cultureinfo]::CurrentCulture = 'el-GR'; & '$ci' plan -Do init -Project '$culture' *> `$null; & '$ci' plan -Do add -Title Task -Json -Project '$culture' 2>`$null"
    $added = pwsh -NoProfile -Command $command | ConvertFrom-Json
    Assert-True ($added.ok) 'plan reads its start time back under a day-first culture (el-GR)'
    Assert-True ((ConvertTo-UtcTime ([datetime]::new(2026, 10, 23, 5, 57, 27, [DateTimeKind]::Utc))) -eq [datetime]::new(2026, 10, 23, 5, 57, 27, [DateTimeKind]::Utc) -and
        (ConvertTo-UtcTime '2026-10-23T05:57:27.0000000Z') -eq [datetime]::new(2026, 10, 23, 5, 57, 27, [DateTimeKind]::Utc)) 'ConvertTo-UtcTime keeps a UTC DateTime and reads an ISO string as the same instant'
} finally {
    Remove-Item -LiteralPath $culture -Recurse -Force -ErrorAction SilentlyContinue
}

# A hand-broken plan: plan fails with invalid-plan (not unexpected-error), and status, which never fails on what it finds,
# warns and reports plan as null.
$broken = Join-Path ([IO.Path]::GetTempPath()) "plan-broken-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force $broken | Out-Null
    Set-Content -LiteralPath (Join-Path $broken 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Broken""`n"
    pwsh -NoProfile -File $ci plan -Do init -Project $broken 2>$null | Out-Null
    $brokenPath = Join-Path $broken 'plan/plan.json'
    $good = Get-Content -LiteralPath $brokenPath -Raw
    $noWip = $good | ConvertFrom-Json -Depth 10
    $noWip.PSObject.Properties.Remove('wipLimit')
    $badCheck = $good | ConvertFrom-Json -Depth 10
    $badCheck.phases[0].gates[1] | Add-Member -NotePropertyName check -NotePropertyValue 'files:docs/x.md' -Force
    foreach ($case in @(@('no wipLimit', ($noWip | ConvertTo-Json -Depth 10), 'wipLimit'), @('an unknown check', ($badCheck | ConvertTo-Json -Depth 10), 'files:docs/x\.md'),
            @('broken JSON', '{ "phases": [', 'not valid JSON'))) {
        Set-Content -LiteralPath $brokenPath -Value $case[1] -Encoding utf8
        $d = pwsh -NoProfile -File $ci plan -Json -Project $broken 2>$null | ConvertFrom-Json
        Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-plan' -and $d.error.message -match $case[2]) "plan with $($case[0]) fails with invalid-plan: $($d.error.code) $($d.error.message)"
        $s = pwsh -NoProfile -File $ci status -Json -Project $broken 2>$null | ConvertFrom-Json
        Assert-True ($s.ok -and $null -eq $s.plan -and @($s.warnings | Where-Object { $_ -match 'cannot be read' -and $_ -match $case[2] }).Count -eq 1) "status with $($case[0]) warns and reports no plan: $(if ($s.ok) { $s.warnings -join ' | ' } else { $s.error.message })"
    }
} finally {
    Remove-Item -LiteralPath $broken -Recurse -Force -ErrorAction SilentlyContinue
}

# init sets up the project the plan's gates check: it adds a starter test, but never over a file the user already has
# (here a test of that name that extends GUT's script by path, so it is not found as a GutTest).
$starter = Join-Path ([IO.Path]::GetTempPath()) "plan-init-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force (Join-Path $starter 'test') | Out-Null
    Set-Content -LiteralPath (Join-Path $starter 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Starter""`n"
    $mine = "extends ""res://addons/gut/test.gd""`n`nfunc test_mine():`n`tassert_true(true)`n"
    Set-Content -LiteralPath (Join-Path $starter 'test/test_example.gd') -Value $mine -NoNewline
    $d = pwsh -NoProfile -File $ci init -Json -Project $starter 2>$null | ConvertFrom-Json
    Assert-True ((Get-Content -LiteralPath (Join-Path $starter 'test/test_example.gd') -Raw) -ceq $mine) 'init leaves an existing test/test_example.gd as it was'
    Assert-True (@($d.steps | Where-Object { $_.status -eq 'skipped' -and $_.message -match 'test_example\.gd exists' }).Count -eq 1) "init says it skipped it: $(@($d.steps | ForEach-Object message) -join ' | ')"
} finally {
    Remove-Item -LiteralPath $starter -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) plan check(s) failed" }
Write-Host 'plan self-test passed'
# One kit run failed on purpose (the refused gate); GitHub's pwsh wrapper would exit with its code.
exit 0
