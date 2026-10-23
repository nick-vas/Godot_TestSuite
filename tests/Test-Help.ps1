#!/usr/bin/env pwsh
# Self-test of `help` and its one source, docs/help.md: every command in hyperdot.ps1's -Command set, every skill in
# .agents/skills and every subagent in agents/ has an entry there with a one-line summary, and no entry names one that
# does not exist; the kit calls its pages quote bind. Then `help` itself, from a folder with no project: the list, a
# command's, a skill's and a subagent's page, an unknown name and a name given to another command. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}

foreach ($lib in 'Common', 'Context', 'Help') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$helpFile = Join-Path $root 'docs/help.md'
$entries = @(Read-HelpEntries $helpFile)
$subjects = Get-HelpSubjects
foreach ($kind in $subjects.Keys) {
    $listed = @($entries | Where-Object kind -eq $kind | ForEach-Object name)
    $missing = @($subjects[$kind] | Where-Object { $_ -notin $listed })
    $stale = @($listed | Where-Object { $_ -notin $subjects[$kind] })
    Assert-True ($missing.Count -eq 0) "every $kind has an entry in docs/help.md$(if ($missing) { ": add ### $($missing -join ', ### ') under its section" })"
    Assert-True ($stale.Count -eq 0) "every $kind entry exists$(if ($stale) { ": $($stale -join ', ') no longer does" })"
}
$twice = @($entries | ForEach-Object { $_.name } | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
Assert-True ($twice.Count -eq 0) "no name has two entries$(if ($twice) { ": $($twice -join ', ')" })"
$noSummary = @($entries | Where-Object { -not $_.summary -or $_.summary.Length -gt 200 } | ForEach-Object name)
Assert-True ($noSummary.Count -eq 0) "each entry starts with a summary line of at most 200 characters$(if ($noSummary) { ": $($noSummary -join ', ')" })"

# The pages quote calls as `hyperdot.ps1 <command> [-Flag value]`: each must name a real command and real flags.
$calls = ([System.IO.File]::ReadAllText($helpFile) -replace '(?m)^(\s*)hyperdot\.ps1', '$1pwsh hyperdot.ps1') -replace '[\[\]|]', ' '
$problems = @(Get-KitCommandProblems $calls 'docs/help.md')
Assert-True ($problems.Count -eq 0) "every call in docs/help.md binds$(if ($problems) { ': ' + ($problems -join ' | ') })"

# The command itself, run where there is no Godot project at all.
$empty = Join-Path ([System.IO.Path]::GetTempPath()) "help-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $empty | Out-Null
function Invoke-Help([string[]]$HelpArgs) {
    Push-Location $empty
    try { $out = & pwsh -NoProfile -File $ci @HelpArgs 2>$null | Out-String } finally { Pop-Location }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
try {
    $r = Invoke-Help @('help', '-Json')
    $d = $r.Text | ConvertFrom-Json
    $total = @($subjects.Values | ForEach-Object { $_ }).Count
    Assert-True ($r.Code -eq 0 -and $d.ok -and $d.command -eq 'help' -and @($d.entries).Count -eq $total) "help -Json lists all $total entries without a project: $(@($d.entries).Count)"
    Assert-True (@($d.entries | Where-Object { $_.name -eq 'shot' -and $_.kind -eq 'command' -and $_.summary }).Count -eq 1) 'each entry has a name, kind and summary'

    $r = Invoke-Help @('help')
    $absent = @(foreach ($e in $entries) { if ($r.Text -notmatch "(?m)^  $([regex]::Escape($e.name))\s{2,}\S") { $e.name } })
    Assert-True ($r.Code -eq 0 -and $absent.Count -eq 0) "help prints one line per entry$(if ($absent) { ": missing $($absent -join ', ')" })"

    $d = (Invoke-Help @('help', 'shot', '-Json')).Text | ConvertFrom-Json
    Assert-True ($d.ok -and $d.entry.kind -eq 'command' -and $d.entry.page -match 'hyperdot\.ps1 shot ') "help shot returns the command's page: $($d.entry | ConvertTo-Json -Compress)"
    $d = (Invoke-Help @('help', '/game', '-Json')).Text | ConvertFrom-Json
    Assert-True ($d.ok -and $d.entry.kind -eq 'skill' -and $d.entry.when -match '^Use when' -and $d.entry.start -match '/game' -and $d.entry.file -eq '.agents/skills/game/SKILL.md') "help /game adds when and how to start it: $($d.entry | ConvertTo-Json -Compress)"
    $d = (Invoke-Help @('help', 'godot-verifier', '-Json')).Text | ConvertFrom-Json
    Assert-True ($d.ok -and $d.entry.kind -eq 'subagent' -and $d.entry.when) 'help godot-verifier returns the subagent page'
    $r = Invoke-Help @('help', 'game')
    Assert-True ($r.Code -eq 0 -and $r.Text -match '(?m)^game \(skill\): ' -and $r.Text -match '(?m)^When: Use when') 'help game prints the page as text'

    $r = Invoke-Help @('help', 'shto', '-Json')
    $d = $r.Text | ConvertFrom-Json
    Assert-True ($r.Code -eq 1 -and $d.error.code -eq 'invalid-arguments' -and $d.error.message -match 'did you mean shot') "an unknown name suggests the closest: $($d.error.message)"
    $r = Invoke-Help @('test', 'shot', '-Json')
    $d = $r.Text | ConvertFrom-Json
    Assert-True ($r.Code -eq 1 -and $d.error.code -eq 'invalid-arguments') 'a name given to another command is refused'
} finally {
    Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) help check(s) failed" }
Write-Host 'help self-test passed'
# Some kit runs failed on purpose (the refusals); GitHub's pwsh wrapper would exit with the last one's code.
exit 0
