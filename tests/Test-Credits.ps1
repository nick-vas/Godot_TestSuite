#!/usr/bin/env pwsh
# Self-test of the credits generator on tests/credits-fixture (one of each case: a CC BY credit, a CC BY 3.0 credit without
# its title, MIT from the standard text, OFL from the asset's own licence file, CC0 thanks, commissioned work assigned to the
# studio, commissioned work under a credit licence, MPL-2.0 with its source URL, and four errors), then the `credits` command end to end on its
# clean sub-project, which reads the engine's notices from Godot (needs Godot).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Credits') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$fixture = Join-Path $PSScriptRoot 'credits-fixture'
$out = Join-Path ([IO.Path]::GetTempPath()) "credits-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

try {
    $r = New-GameCredits -ManifestPath (Join-Path $fixture 'assets.json') -OutDir $out -GameName 'Credits Fixture' `
        -LicenceTextDir (Join-Path $root 'ci/godot/templates/licences') -EngineNoticesJson (Join-Path $fixture 'engine-notices.json')
    $errors = @($r.errors | ForEach-Object { "$($_.code) $($_.path)" })
    $warnings = @($r.warnings | ForEach-Object { "$($_.code) $($_.path)" })
    Assert-True ($errors -contains 'credit-author-missing art/no_author.png') 'CC BY without an author is an error'
    Assert-True ($errors -contains 'licence-blocked music/theme.ogg') 'a non-commercial licence is an error'
    Assert-True ($errors -contains 'copyright-missing shaders/water.gdshader') 'MIT without a copyright line is an error'
    Assert-True ($errors -contains 'source-offer-missing addons/rust_ai/**') 'MPL-2.0 whose source is not a URL is an error'
    Assert-True ($errors.Count -eq 4) "only those four errors: $($errors -join ' | ')"
    Assert-True ($warnings -contains 'mpl-modified addons/rust_ai/**') 'modified MPL-2.0 files warn that the changes are MPL-2.0 too'
    Assert-True (-not ($errors -match 'rust_physics') -and -not ($warnings -match 'rust_physics')) 'MPL-2.0 with a source URL and no copyright line is fine'
    Assert-True ($warnings -contains 'credit-title-missing art/castle/**') 'CC BY 3.0 without a title warns'
    Assert-True (-not ($warnings -match 'art/boss')) 'commissioned work under its agreement is not warned about as a bought asset'
    Assert-True (-not $r.ok) 'errors make the result not ok'

    $md = Get-Content -LiteralPath (Join-Path $out 'CREDITS.md') -Raw
    Assert-True ($md -match '"Knight Sprite" by Jane Doe \(https://opengameart\.org/content/knight\), licensed under CC BY 4\.0') 'a CC BY credit names title, author, source and licence'
    Assert-True ($md -match 'Ann Lee .*; modified: recoloured') 'a modified work says so'
    Assert-True ($md -match 'Rain by Kenney \(CC0 1\.0\)') 'CC0 works get a thank-you line'
    Assert-True ($md -notmatch 'art/player') 'the game''s own work is not credited as third-party'
    Assert-True ($md -notmatch 'art/boss|Ivy Ng') 'commissioned work assigned to the studio is not credited as third-party'
    Assert-True ($md -match '"Last Light" by Max Mo, licensed under CC BY 4\.0') 'commissioned work under a credit licence gets its credit, with no source URL asked for'

    $notices = Get-Content -LiteralPath (Join-Path $out 'THIRD-PARTY-NOTICES.txt') -Raw
    Assert-True ($notices -match 'Copyright \(c\) 2021 Sam Roe' -and $notices -match 'Permission is hereby granted') 'MIT notices carry the copyright line and the licence text'
    Assert-True ($notices -notmatch '<year>|<copyright holders>') 'no template placeholders are left'
    Assert-True ($notices -match 'The source code of these files is available at https://github\.com/example/rust-physics under the MPL 2\.0 licence' -and $notices -match 'Mozilla Public License Version 2\.0') 'MPL-2.0 notices say where the source is and carry the licence text'
    Assert-True ($notices -match 'Sample Sans Project Authors' -and $notices -match 'SIL Open Font License') 'the font ships its own licence file'
    Assert-True ($notices -match 'Godot Engine 4\.7\.2' -and $notices -match 'The FreeType Project' -and $notices -match 'based in part on the work of the FreeType Team') 'the engine''s notices and its components'' licences are included'

    $json = Get-Content -LiteralPath (Join-Path $out 'credits.json') -Raw | ConvertFrom-Json
    Assert-True ($json.schema -eq 'game-credits/1' -and @($json.sections | Where-Object id -eq 'attribution').entries.Count -ge 2) 'credits.json has the attribution section for the in-game screen'

    # End to end: the command reads Godot's own notices from the engine.
    $clean = Join-Path $fixture 'clean'
    $cleanOut = Join-Path $out 'clean'
    $d = pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') credits -Json -Project $clean -Output $cleanOut 2>$null | ConvertFrom-Json
    Assert-True ($d.ok -and $d.credits.credits -eq 1 -and $d.credits.notices -ge 2) "credits on a clean manifest passes: $($d | ConvertTo-Json -Depth 4 -Compress)"
    $engine = Get-Content -LiteralPath (Join-Path $cleanOut 'THIRD-PARTY-NOTICES.txt') -Raw
    Assert-True ($engine -match 'Godot Engine contributors' -and $engine -match 'FreeType') 'the command includes the engine''s real notices'
    $bad = pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') credits -Json -Project $fixture -Output (Join-Path $out 'bad') 2>$null | ConvertFrom-Json
    Assert-True (-not $bad.ok -and $bad.error.code -eq 'credits-invalid' -and @($bad.credits.errors).Count -eq 4) 'the command fails with credits-invalid and lists the problems'
} finally {
    Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) credits check(s) failed" }
Write-Host 'credits self-test passed'
# The last kit run failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
