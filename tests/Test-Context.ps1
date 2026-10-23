#!/usr/bin/env pwsh
# Self-test of doctor's check of the agent instructions (AGENTS.md, CLAUDE.md and their imports): kit commands and flags
# that do not exist, files that do not exist, imports that load nothing, and files over 200 lines. Also holds the kit's
# own AGENTS.md template, skills and docs to the same rule for kit commands. Needs git; not Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}

foreach ($lib in 'Common', 'Context') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }

# The kit holds itself to the rule: every hyperdot.ps1 call in the template, the skills and the docs binds.
$sources = @(Get-Item (Join-Path $root 'ci/godot/templates/AGENTS.md')) + @(Get-ChildItem (Join-Path $root '.agents/skills') -Recurse -Filter 'SKILL.md') +
    @(Get-ChildItem (Join-Path $root 'docs') -Filter '*.md') + @(Get-ChildItem (Join-Path $root 'agents') -Filter '*.md') + @(Get-Item (Join-Path $root 'README.md'))
$kitProblems = @(foreach ($file in $sources) {
    Get-KitCommandProblems ([System.IO.File]::ReadAllText($file.FullName)) ([System.IO.Path]::GetRelativePath($root, $file.FullName))
})
Assert-True ($kitProblems.Count -eq 0) "every kit call in the template, skills and docs binds$(if ($kitProblems) { ': ' + ($kitProblems -join ' | ') })"

# What PowerShell binds: exact names, unique prefixes; not ambiguous prefixes or unknown names.
$params = (Get-KitCommandLine).parameters
Assert-True ((Resolve-KitParameter 'Json' $params) -eq 'Json') 'an exact parameter binds'
Assert-True ((Resolve-KitParameter 'Runn' $params) -eq 'Runners') 'a unique prefix binds'
Assert-True ($null -eq (Resolve-KitParameter 'Quite' $params)) 'a misspelt flag does not bind'
Assert-True ($null -eq (Resolve-KitParameter 'Re' $params)) 'an ambiguous prefix does not bind'

# Imports: outside code, relative, path-like only.
$imports = @(Get-InstructionImports "@AGENTS.md`nSee ``@README`` and mail a@b.com or ask @someone.`n``````text`n@docs/in-fence.md`n```````n@Design\ Docs/plan.md")
Assert-True (($imports -join '|') -eq 'AGENTS.md|Design Docs/plan.md') "imports skip code, mail addresses and handles: $($imports -join '|')"

$dir = Join-Path ([System.IO.Path]::GetTempPath()) "context-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force (Join-Path $dir 'scripts'), (Join-Path $dir 'scenes'), (Join-Path $dir 'docs') | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Context`"`n"
    Set-Content -LiteralPath (Join-Path $dir 'scripts/player.gd') 'extends Node'
    Set-Content -LiteralPath (Join-Path $dir 'scenes/Main.tscn') '[gd_scene format=3]'
    & git -C $dir init -q
    $template = (Get-Content -LiteralPath (Join-Path $root 'ci/godot/templates/AGENTS.md') -Raw) -replace '\{\{SUITE\}\}', 'tools/kit/ci/godot/hyperdot.ps1'
    Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') $template
    Set-Content -LiteralPath (Join-Path $dir 'CLAUDE.md') '@AGENTS.md'

    # A fresh init: the template names files a new game does not have yet (docs/lessons.md, res://ui/Menu.tscn), and none
    # of that is the game's mistake.
    $fresh = @(Get-InstructionProblems $dir)
    Assert-True ($fresh.Count -eq 1 -and $fresh[0].Status -eq 'OK') "a freshly initialised project passes: $(@($fresh | ForEach-Object Message) -join ' | ')"

    Add-Content -LiteralPath (Join-Path $dir 'AGENTS.md') @(
        '', '## This game',
        '- Quick check: `pwsh tools/kit/ci/godot/hyperdot.ps1 test -Json -Quite`',
        '- Perf: `pwsh tools/kit/ci/godot/hyperdot.ps1 benchmark -Json`',
        '- Only GUT: `pwsh tools/kit/ci/godot/hyperdot.ps1 test -Runn gut -Json`',
        '- The player is `scripts/player.gd`; enemies think in `scripts/enemies/brain.gd`.',
        '- The first level is res://scenes/Main.tscn; the old hub res://scenes/Hub.tscn was cut.',
        '- Tests live in `test/*.gd`; see https://example.com/a/b.html.'
    )
    Set-Content -LiteralPath (Join-Path $dir 'CLAUDE.md') "@AGENTS.md`n@docs/style.md`n"
    Set-Content -LiteralPath (Join-Path $dir 'docs/style.md') ((@('# Style') + @(1..205 | ForEach-Object { "- rule $_" })) -join "`n")
    Set-Content -LiteralPath (Join-Path $dir 'docs/notes.md') "@missing/old.md`n"
    Add-Content -LiteralPath (Join-Path $dir 'docs/style.md') "`n@notes.md"
    $broken = @(Get-InstructionProblems $dir)
    $text = @($broken | ForEach-Object { "$($_.Status) $($_.Message)" }) -join "`n"
    Assert-True ($text -match "-Quite is not a kit parameter") "a misspelt flag is reported: $text"
    Assert-True ($text -match "'benchmark' is not a kit command") 'an unknown command is reported'
    Assert-True ($text -notmatch '-Runn ') 'a unique prefix is not reported'
    Assert-True ($text -match 'scripts/enemies/brain\.gd' -and $text -notmatch 'scripts/player\.gd') 'a missing file is reported, an existing one is not'
    Assert-True ($text -match 'res://scenes/Hub\.tscn' -and $text -notmatch 'res://scenes/Main\.tscn') 'a missing res:// path is reported, an existing one is not'
    Assert-True ($text -notmatch 'test/\*\.gd|example\.com') 'globs and URLs are left alone'
    Assert-True ($text -match 'docs/notes\.md: @missing/old\.md') 'an import two hops down that loads nothing is reported'
    Assert-True ($text -match 'docs/style\.md \(20[0-9] lines\)') 'an imported file over 200 lines is reported'
    Assert-True ($text -match 'AGENTS\.md:\d+ -Quite') 'problems name the file and line'
    Assert-True (@($broken | Where-Object Status -eq 'FAIL').Count -eq 0) 'instruction problems never fail doctor'

    # End to end: doctor shows them.
    $json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') doctor -Project $dir -Json 2>$null | Out-String | ConvertFrom-Json
    $messages = @($json.checks | ForEach-Object message) -join "`n"
    Assert-True ($messages -match 'commands or flags it does not have' -and $messages -match 'name files that do not exist') 'doctor reports them'
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) context check(s) failed" }
Write-Host 'context self-test passed'
exit 0
