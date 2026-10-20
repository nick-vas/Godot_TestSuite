#Requires -Version 7.2
# Stop hook: Claude may not end its turn while the game's code or scenes changed after the last passing test run.
# It reads the project's run history (.godot/godot-ci-history.jsonl, written by godot-ci.ps1) and the changed files git
# reports. Each set of changes is blocked once: if Claude stops again without a new test run, it is let through, because
# it was told and must now explain why the tests were not run (no Godot on this machine, for example). That keeps the
# gate from looping. Set GODOT_CI_STOP_GATE=off to disable it.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Exit-Allow { exit 0 }

try {
    if ($env:GODOT_CI_STOP_GATE -eq 'off') { Exit-Allow }
    $hookInput = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
    $cwd = if ($hookInput -and $hookInput['cwd']) { $hookInput['cwd'] } else { $PWD.Path }
    # A folder with .gdignore is not a game (this kit's own repository has one at its root).
    if (Test-Path -LiteralPath (Join-Path $cwd '.gdignore')) { Exit-Allow }

    # The shallowest project.godot at or below the working folder, skipping addons and .gdignore'd folders.
    $project = @(Get-ChildItem -LiteralPath $cwd -Filter project.godot -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](addons|\.godot)[\\/]' } |
        Where-Object {
            $dir = $_.Directory
            $ignored = $false
            while ($dir -and $dir.FullName.Length -gt $cwd.Length) {
                if (Test-Path -LiteralPath (Join-Path $dir.FullName '.gdignore')) { $ignored = $true; break }
                $dir = $dir.Parent
            }
            -not $ignored
        } | Sort-Object { $_.FullName.Length } | Select-Object -First 1)
    if ($project.Count -eq 0) { Exit-Allow }
    $projectDir = $project[0].DirectoryName

    # What changed: files git reports as modified or new, or, outside git, every source file.
    $codePattern = '\.(cs|gd|tscn|tres|gdshader|csproj|sln|cfg|godot)$|\.flow\.json$'
    $skipPattern = '(^|[\\/])(\.godot|addons|test-results|bench-results|screenshots|build|bin|obj)([\\/]|$)'
    $files = @()
    $status = & git -C $cwd status --porcelain --untracked-files=all 2>$null
    if ($LASTEXITCODE -eq 0) {
        $root = (& git -C $cwd rev-parse --show-toplevel).Trim()
        $files = @($status | ForEach-Object { $_.Substring(3).Trim('"') -replace '^.* -> ', '' } |
            Where-Object { $_ -match $codePattern -and $_ -notmatch $skipPattern } |
            ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path -LiteralPath $_ })
    } else {
        $files = @(Get-ChildItem -LiteralPath $projectDir -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match $codePattern -and $_.FullName.Substring($projectDir.Length) -notmatch $skipPattern } |
            ForEach-Object FullName)
    }
    if ($files.Count -eq 0) { Exit-Allow }
    $newest = ($files | ForEach-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc } | Measure-Object -Maximum).Maximum

    $history = Join-Path $projectDir '.godot/godot-ci-history.jsonl'
    $tests = @(if (Test-Path -LiteralPath $history) {
        Get-Content -LiteralPath $history | Where-Object { Test-Json -Json $_ -ErrorAction SilentlyContinue } | ConvertFrom-Json |
            Where-Object { $_.command -eq 'test' }
    })
    $lastOk = @($tests | Where-Object ok | Select-Object -Last 1)
    if ($lastOk.Count -gt 0 -and ([datetime]$lastOk[0].time).ToUniversalTime() -ge $newest) { Exit-Allow }
    $lastRun = @($tests | Select-Object -Last 1)
    # Tests ran after the last change and failed: Claude has the result and must report it, not loop.
    if ($hookInput['stop_hook_active'] -and $lastRun.Count -gt 0 -and ([datetime]$lastRun[0].time).ToUniversalTime() -ge $newest) { Exit-Allow }

    # Block each set of changes once.
    $state = Join-Path $projectDir '.godot/godot-ci-stop-gate'
    $stamp = "$($newest.Ticks)"
    if ((Test-Path -LiteralPath $state) -and (Get-Content -LiteralPath $state -Raw).Trim() -eq $stamp) { Exit-Allow }
    New-Item -ItemType Directory -Force (Split-Path $state) | Out-Null
    Set-Content -LiteralPath $state -Value $stamp -NoNewline

    $kit = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../ci/godot/godot-ci.ps1')) -replace '\\', '/'
    $projectArg = if ($projectDir -ne $cwd) { " -Project `"$($projectDir -replace '\\', '/')`"" } else { '' }
    $shown = @($files | Select-Object -First 5 | ForEach-Object { [System.IO.Path]::GetRelativePath($cwd, $_) -replace '\\', '/' })
    $more = if ($files.Count -gt 5) { " and $($files.Count - 5) more" } else { '' }
    $when = if ($lastOk.Count -gt 0) { "since the last passing test run ($($lastOk[0].time))" } else { 'and no passing test run is recorded' }
    $reason = "Godot files changed $when`: $($shown -join ', ')$more. Run pwsh `"$kit`" test -Json -Quiet$projectArg and fix " +
        "what fails before finishing. If the tests cannot run here, say so and why instead of reporting the work as done."
    [ordered]@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
    exit 0
} catch {
    # A broken gate must never trap the session.
    exit 0
}
