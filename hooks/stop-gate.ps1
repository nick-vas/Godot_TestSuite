#Requires -Version 7.2
# Stop hook: Claude may not end its turn while the game's code or scenes changed after the last passing full test run.
# It reads the project's run history (.godot/hyperdot-history.jsonl, written by hyperdot.ps1) and the changed files git
# reports. Each set of changes is blocked once: if Claude stops again without a new test run, it is let through, because
# it was told and must now explain why the tests were not run (no Godot on this machine, for example). That keeps the
# gate from looping. Set HYPERDOT_STOP_GATE=off to disable it.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Exit-Allow { exit 0 }

# Runners that run the game's own tests; validate, smoke and the rest only check that it loads and holds together.
$script:TestRunners = 'dotnet', 'gdunit4', 'godottest', 'gut'
$script:Detected = $null

# The runners a plain `test` would run on the project, from the kit's own detection; $null when that fails.
function Get-DetectedRunners([string]$ProjectDir) {
    if ($null -eq $script:Detected) {
        $script:Detected = @{ Runners = $null }
        try {
            $kitScript = Join-Path $PSScriptRoot '../ci/godot/hyperdot.ps1'
            $result = & (Get-Process -Id $PID).Path -NoProfile -File $kitScript detect -Json -Project $ProjectDir 2>$null | ConvertFrom-Json
            if ($result -and $result.ok) { $script:Detected.Runners = @($result.runners) }
        } catch { }
    }
    return $script:Detected.Runners
}

# A run that could have caught a broken change: no -Filter, and the game's tests ran (a real test runner, or every
# detected runner when the project has no tests). `-Runners none`, `-Runners validate` or a filtered run is not one.
function Test-FullRun($Run, [string]$ProjectDir) {
    if (-not $Run.PSObject.Properties['scope'] -or -not $Run.scope) { return $false }
    if ($Run.scope.PSObject.Properties['filter'] -and $Run.scope.filter) { return $false }
    $ran = @(if ($Run.scope.PSObject.Properties['runners']) { $Run.scope.runners | Where-Object { $_ } })
    if (@($ran | Where-Object { $_ -in $script:TestRunners }).Count -gt 0) { return $true }
    $detected = Get-DetectedRunners $ProjectDir
    if ($null -eq $detected -or @($detected | Where-Object { $_ -in $script:TestRunners }).Count -gt 0) { return $false }
    return @($detected | Where-Object { $_ -notin $ran }).Count -eq 0
}

# When a file last changed; a deleted one has no time of its own, so its nearest remaining folder's (which changed when it went).
function Get-ChangeTime([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    while (-not $item) {
        $Path = Split-Path $Path
        if (-not $Path) { return $null }
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
    return $item.LastWriteTimeUtc
}

# The paths of NUL-separated git output (-z): no quoting, so names with spaces or non-ASCII letters come through as they are.
function Split-GitPaths([object[]]$Output) {
    return @(($Output -join "`n") -split "`0" | Where-Object { $_ })
}

try {
    if ($env:HYPERDOT_STOP_GATE -eq 'off') { Exit-Allow }
    # git writes UTF-8; read it as such on Windows too, where the console code page is often something else.
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $raw = [Console]::In.ReadToEnd()
    $hookInput = if ($raw -and $raw.Trim()) { $raw | ConvertFrom-Json -AsHashtable } else { $null }
    if ($hookInput -isnot [System.Collections.IDictionary]) { $hookInput = @{} }
    $cwd = if ($hookInput['cwd']) { $hookInput['cwd'] } else { $PWD.Path }
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
    $projectDir = if ($project.Count -gt 0) { $project[0].DirectoryName } else { $null }
    # Or the game the working folder is inside (Claude working in its scripts/ folder), unless a .gdignore'd folder on
    # the way up says this is not the game's own code (the kit placed inside a game).
    if (-not $projectDir) {
        $dir = (Get-Item -LiteralPath $cwd).Parent
        while ($dir) {
            if (Test-Path -LiteralPath (Join-Path $dir.FullName '.gdignore')) { break }
            if (Test-Path -LiteralPath (Join-Path $dir.FullName 'project.godot')) { $projectDir = $dir.FullName; break }
            $dir = $dir.Parent
        }
    }
    if (-not $projectDir) { Exit-Allow }

    $history = Join-Path $projectDir '.godot/hyperdot-history.jsonl'
    # The history from before the Hyperdot rename, moved once (the kit does the same on its next run).
    $oldHistory = Join-Path $projectDir '.godot/godot-ci-history.jsonl'
    if (-not (Test-Path -LiteralPath $history) -and (Test-Path -LiteralPath $oldHistory)) { Move-Item -LiteralPath $oldHistory -Destination $history }
    $tests = @(if (Test-Path -LiteralPath $history) {
        Get-Content -LiteralPath $history | Where-Object { Test-Json -Json $_ -ErrorAction SilentlyContinue } | ConvertFrom-Json |
            Where-Object { $_.command -eq 'test' }
    })
    # The newest passing full run, looking back from the end so a run with the game's tests needs no detection.
    $lastOk = @()
    for ($i = $tests.Count - 1; $i -ge 0; $i--) {
        if ($tests[$i].ok -and (Test-FullRun $tests[$i] $projectDir)) { $lastOk = @($tests[$i]); break }
    }
    $lastRun = @($tests | Select-Object -Last 1)

    # What changed: files git reports as modified, new or deleted, plus those committed since the last passing run (its
    # history line records the commit), or, outside git, every source file.
    $codePattern = '\.(cs|gd|tscn|scn|tres|res|gdshader|gdshaderinc|csproj|sln|cfg|godot|json|csv|po)$'
    $skipPattern = '(^|[\\/])(\.godot|addons|test-results|bench-results|audio-results|soak-results|screenshots|build|bin|obj)([\\/]|$)'
    $files = @()
    $root = @(& git -C $cwd rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and $root.Count -gt 0) {
        $root = "$($root[0])".Trim()
        $fields = @(Split-GitPaths @(& git -C $root -c core.quotePath=false status --porcelain=v1 -z --untracked-files=all 2>$null))
        $paths = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $fields.Count; $i++) {
            if ($fields[$i].Length -lt 4) { continue }
            $paths.Add($fields[$i].Substring(3))
            # A rename or copy is followed by its old name.
            if ($fields[$i][0] -in 'R', 'C') { $i++ }
        }
        $since = @(@($lastOk) + @($tests | Select-Object -Last 1) | Where-Object { $_.PSObject.Properties['commit'] -and $_.commit } | Select-Object -First 1)
        if ($since.Count -gt 0) {
            $committed = @(Split-GitPaths @(& git -C $root -c core.quotePath=false diff --name-only -z $since[0].commit HEAD -- 2>$null))
            if ($LASTEXITCODE -eq 0) { foreach ($p in $committed) { $paths.Add($p) } }
        }
        $files = @($paths | Sort-Object -Unique | Where-Object { $_ -match $codePattern -and $_ -notmatch $skipPattern } |
            ForEach-Object { Join-Path $root $_ })
    } else {
        $files = @(Get-ChildItem -LiteralPath $projectDir -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match $codePattern -and $_.FullName.Substring($projectDir.Length) -notmatch $skipPattern } |
            ForEach-Object FullName)
    }
    if ($files.Count -eq 0) { Exit-Allow }
    $newest = (@($files | ForEach-Object { Get-ChangeTime $_ } | Where-Object { $_ }) | Measure-Object -Maximum).Maximum
    if (-not $newest) { Exit-Allow }

    if ($lastOk.Count -gt 0 -and ([datetime]$lastOk[0].time).ToUniversalTime() -ge $newest) { Exit-Allow }
    # Tests ran after the last change and failed: Claude has the result and must report it, not loop.
    if ($hookInput['stop_hook_active'] -and $lastRun.Count -gt 0 -and ([datetime]$lastRun[0].time).ToUniversalTime() -ge $newest) { Exit-Allow }

    # Block each set of changes once.
    $state = Join-Path $projectDir '.godot/hyperdot-stop-gate'
    $stamp = "$($newest.Ticks)"
    if ((Test-Path -LiteralPath $state) -and (Get-Content -LiteralPath $state -Raw).Trim() -eq $stamp) { Exit-Allow }
    New-Item -ItemType Directory -Force (Split-Path $state) | Out-Null
    Set-Content -LiteralPath $state -Value $stamp -NoNewline

    $kit = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../ci/godot/hyperdot.ps1')) -replace '\\', '/'
    $projectArg = if ($projectDir -ne $cwd) { " -Project `"$($projectDir -replace '\\', '/')`"" } else { '' }
    $shown = @($files | Select-Object -First 5 | ForEach-Object {
        $name = [System.IO.Path]::GetRelativePath($cwd, $_) -replace '\\', '/'
        if (Test-Path -LiteralPath $_) { $name } else { "$name (deleted)" }
    })
    $more = if ($files.Count -gt 5) { " and $($files.Count - 5) more" } else { '' }
    $when = if ($lastOk.Count -gt 0) { "since the last passing full test run ($($lastOk[0].time))" } else { 'and no passing full test run is recorded' }
    $reason = "Godot files changed $when`: $($shown -join ', ')$more. Run pwsh `"$kit`" test -Json -Quiet$projectArg (without -Filter, " +
        "and with the game's tests among the runners) and fix what fails before finishing. If the tests cannot run here, say so " +
        "and why instead of reporting the work as done."
    [ordered]@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
    exit 0
} catch {
    # A broken gate must never trap the session.
    exit 0
}
