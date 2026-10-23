# Sessions as a separate user (benchmark/PLAN.md, section 6), dot-sourced by Invoke-TokenBenchmark.ps1.
#
# A session that can run commands could read the checkout the benchmark runs from, hidden tests and graders included.
# With isolation each session runs as a user made for the run, whose only readable folders are its game copy (and, with
# -Plugin, the copy of the kit without the benchmark it loads):
#
#   <temp>/hyperdot-isolated-<id>/            mode 711: the session reaches its game by name but cannot list the folder
#     private/                                 mode 700: the runner's own files (each game's .git, kept for grading)
#     home/                                    the session user's HOME, made afresh for every session
#     godot/                                   a copy of Godot, when the session user cannot run the runner's
#     bin/                                     the CLI, when it is a script (the self-test's stand-in)
#     hyperdot-game-<id>/                      a game copy: the session user's while it runs, the runner's again after
#
# The runner's temporary folder moves into it for the run, so stage fixtures and other runner files are not in a folder
# the session user can list, and the checkout loses its permissions for others (restored at the end). Needs Linux and
# root or passwordless sudo (useradd, chown, runuser or sudo, pkill); anywhere else it warns and sessions run as the
# runner, as they did before.

$script:Isolation = $null

# Runs a program; returns its exit code and output. -Elevated runs it as root (directly when already root, else sudo -n).
function Invoke-IsolationCommand([string[]]$Command, [switch]$Elevated) {
    $all = @(if ($Elevated -and $script:Isolation) { $script:Isolation.Elevate }) + $Command
    $out = & $all[0] @($all | Select-Object -Skip 1) 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = (@($out | ForEach-Object { "$_" }) -join "`n") }
}

function Assert-IsolationCommand([string[]]$Command, [string]$What) {
    $result = Invoke-IsolationCommand $Command -Elevated
    if ($result.Code -ne 0) { throw "Isolation: $What failed (exit $($result.Code)): $($result.Out)" }
}

# Whether the session user can do what `test` checks: -r (read), -x (run or enter), -w (write).
function Test-SessionAccess([string]$Flag, [string]$Path) {
    $iso = $script:Isolation
    $launch = if ($iso.Launcher -eq 'runuser') { @('runuser', '-u', $iso.User, '--') } else { @('sudo', '-n', '-u', $iso.User, '--') }
    $result = Invoke-IsolationCommand (@($launch) + @('test', $Flag, $Path)) -Elevated
    return $result.Code -eq 0
}

# Why sessions cannot run as another user here; empty when they can.
function Get-IsolationProblem {
    if (-not $IsLinux) { return 'sessions run as a separate user only on Linux' }
    foreach ($tool in 'useradd', 'userdel', 'chown', 'chmod', 'pkill', 'stat') {
        if (-not (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)) { return "$tool is missing" }
    }
    if ((& id -u) -ne '0') {
        if (-not (Get-Command sudo -CommandType Application -ErrorAction SilentlyContinue)) { return 'it needs root or passwordless sudo, and there is no sudo' }
        & sudo -n true 2>$null
        if ($LASTEXITCODE -ne 0) { return 'it needs root or passwordless sudo' }
    }
    return ''
}

# Makes the session user and the folders, and closes the checkout to it. Returns $false (after a warning) where it
# cannot, and the run goes on without isolation.
function Initialize-SessionIsolation([string]$RepoRoot, [string]$Program) {
    $problem = Get-IsolationProblem
    if ($problem) {
        Write-BenchLog "WARNING: not isolating the sessions ($problem). They run as this user and can read whatever it can, the benchmark's hidden tests included."
        return $false
    }
    $isRoot = (& id -u) -eq '0'
    $via = if ($env:HYPERDOT_ISOLATE_VIA) { $env:HYPERDOT_ISOLATE_VIA } elseif ($isRoot -and (Get-Command runuser -CommandType Application -ErrorAction SilentlyContinue)) { 'runuser' } else { 'sudo' }
    if ($via -notin 'runuser', 'sudo') { throw "HYPERDOT_ISOLATE_VIA must be runuser or sudo, not '$via'" }
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $base = Join-Path ([System.IO.Path]::GetTempPath()) "hyperdot-isolated-$id"
    $script:Isolation = [pscustomobject]@{
        User = "hyperdot-s$id"; Base = $base; Home = (Join-Path $base 'home'); Private = (Join-Path $base 'private')
        Elevate = @(if (-not $isRoot) { 'sudo'; '-n' }); Launcher = $via; Runner = "$(& id -u):$(& id -g)"
        OldTemp = $env:TMPDIR; RepoRoot = $RepoRoot; RepoMode = $null; Program = @(); GodotBin = $env:GODOT_BIN; DotnetRoot = $null; UserMade = $false
    }
    try {
        New-Item -ItemType Directory -Force $base, $script:Isolation.Private | Out-Null
        Assert-IsolationCommand @('chmod', '711', $base) 'opening the run folder to the session user'
        Assert-IsolationCommand @('chmod', '700', $script:Isolation.Private) 'closing the runner''s folder'
        $shell = if (Test-Path -LiteralPath '/usr/sbin/nologin') { '/usr/sbin/nologin' } else { '/bin/false' }
        Assert-IsolationCommand @('useradd', '--system', '--no-create-home', '--home-dir', $script:Isolation.Home, '--shell', $shell, '--user-group', $script:Isolation.User) 'making the session user'
        $script:Isolation.UserMade = $true
        # Everything the runner makes from here on (stage fixtures, the kit's copy, game copies) lands in the run folder.
        $env:TMPDIR = $base
        # The session user reaches every file another user can; close the checkout to others for the run.
        if (Test-SessionAccess '-x' $RepoRoot) {
            $script:Isolation.RepoMode = (Invoke-IsolationCommand @('stat', '-c', '%a', $RepoRoot)).Out.Trim()
            Assert-IsolationCommand @('chmod', 'o-rwx', $RepoRoot) 'closing the checkout to other users'
        }
        if (Test-SessionAccess '-r' (Join-Path $RepoRoot 'benchmark')) { throw "Isolation: the session user can still read $RepoRoot/benchmark" }
        # The CLI must be runnable by the session user; a script (the stand-in) is copied where it can read it.
        if ($Program -like '*.ps1') {
            $bin = Join-Path $base 'bin'
            New-Item -ItemType Directory -Force $bin | Out-Null
            $copy = Join-Path $bin (Split-Path $Program -Leaf)
            Copy-Item -LiteralPath (Resolve-Path -LiteralPath $Program).Path -Destination $copy -Force
            Assert-IsolationCommand @('chmod', '-R', 'a+rX', $bin) 'opening the CLI to the session user'
            $script:Isolation.Program = @((Get-Command pwsh -CommandType Application)[0].Source, '-NoProfile', '-File', $copy)
        } else {
            $found = @(Get-Command $Program -CommandType Application -ErrorAction SilentlyContinue)
            if ($found.Count -eq 0) { throw "Claude Code not found: $Program (npm install -g @anthropic-ai/claude-code, or pass -Claude)" }
            $script:Isolation.Program = @($found[0].Source)
        }
        if (-not (Test-SessionAccess '-x' $script:Isolation.Program[0])) {
            throw "Isolation: the session user cannot run $($script:Isolation.Program[0]); install it where every user can (npm install -g as root puts it in /usr/local)"
        }
        Write-BenchLog "Sessions run as $($script:Isolation.User) (via $via); only their game copy is theirs to read"
        return $true
    } catch {
        Remove-SessionIsolation
        throw
    }
}

# A folder the session user cannot reach (the runner's home), copied into the run folder where it can.
function Copy-ForSession([string]$From, [string]$Name, [string]$What) {
    $to = Join-Path $script:Isolation.Base $Name
    Write-BenchLog "Copying $What where the session user can run it ($to)"
    New-Item -ItemType Directory -Force $to | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $From -Force)) { Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $to $item.Name) -Recurse -Force }
    Assert-IsolationCommand @('chmod', '-R', 'a+rX', $to) "opening the copy of $What to the session user"
    return $to
}

# Godot for the sessions: the runner's, when the session user can run it; otherwise a copy of its folder (with the .NET
# build's GodotSharp beside it). The same for a .NET SDK the kit installed in the runner's home (DOTNET_ROOT).
function Grant-SessionGodot {
    $iso = $script:Isolation
    if (-not $iso) { return }
    if ($env:DOTNET_ROOT -and (Test-Path -LiteralPath (Join-Path $env:DOTNET_ROOT 'dotnet') -PathType Leaf) -and -not (Test-SessionAccess '-x' (Join-Path $env:DOTNET_ROOT 'dotnet'))) {
        $iso.DotnetRoot = Copy-ForSession $env:DOTNET_ROOT 'dotnet' '.NET'
    }
    if (-not $env:GODOT_BIN -or -not (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) { return }
    $iso.GodotBin = $env:GODOT_BIN
    if (Test-SessionAccess '-x' $env:GODOT_BIN) { return }
    $iso.GodotBin = Join-Path (Copy-ForSession (Split-Path $env:GODOT_BIN) 'godot' 'Godot') (Split-Path $env:GODOT_BIN -Leaf)
    if (-not (Test-SessionAccess '-x' $iso.GodotBin)) { throw "Isolation: the session user cannot run the copy of Godot at $($iso.GodotBin)" }
}

# What a session's process gets: credentials and network settings by inheritance (never on a command line, where other
# users could read them), paths on the command line of `env`. Nothing of the runner's own state (its HOME, its Claude
# Code configuration, NuGet cache or coverage folder) passes.
function Get-SessionEnvironment {
    $names = [System.Collections.Generic.List[string]]::new()
    $exact = 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'no_proxy', 'all_proxy', 'NODE_EXTRA_CA_CERTS',
    'SSL_CERT_FILE', 'SSL_CERT_DIR', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TERM', 'DISPLAY', 'CI', 'DOTNET_ROOT', 'DOTNET_CLI_TELEMETRY_OPTOUT', 'DOTNET_NOLOGO',
    'HYPERDOT_TIMEOUT'
    $extra = @(if ($env:HYPERDOT_ISOLATE_ENV) { $env:HYPERDOT_ISOLATE_ENV -split ',' | ForEach-Object Trim | Where-Object { $_ } })
    foreach ($entry in @([Environment]::GetEnvironmentVariables().GetEnumerator())) {
        $name = [string]$entry.Key
        $credential = ($name -like 'ANTHROPIC_*') -or ($name -like 'CLAUDE_CODE_*' -and $name -notin 'CLAUDE_CODE_SESSION_ID', 'CLAUDE_CODE_REMOTE_SESSION_ID')
        if ($credential -or $name -in $exact -or $name -in $extra) { $names.Add($name) }
    }
    $environment = [ordered]@{}
    foreach ($name in ($names | Sort-Object -Unique)) { $environment[$name] = [Environment]::GetEnvironmentVariable($name) }
    return $environment
}

# The program, arguments and environment that start the CLI as the session user.
function Get-SessionStart([string[]]$Arguments) {
    $iso = $script:Isolation
    $environment = Get-SessionEnvironment
    $path = @(if ($iso.GodotBin) { Split-Path $iso.GodotBin }) + @(if ($iso.DotnetRoot) { $iso.DotnetRoot }) + @($env:PATH -split ':' | Where-Object { $_ }) -join ':'
    $set = @("PATH=$path", "HOME=$($iso.Home)", "USER=$($iso.User)", "LOGNAME=$($iso.User)", "TMPDIR=$(Join-Path $iso.Home 'tmp')")
    if ($iso.GodotBin) { $set += "GODOT_BIN=$($iso.GodotBin)" }
    if ($iso.DotnetRoot) { $set += "DOTNET_ROOT=$($iso.DotnetRoot)" }
    $command = @('/usr/bin/env') + $set + @($iso.Program) + @($Arguments)
    if ($iso.Launcher -eq 'runuser') {
        $all = @($iso.Elevate) + @('runuser', '-u', $iso.User, '--') + $command
    } else {
        $keep = @($environment.Keys)
        $all = @('sudo', '-n', '-u', $iso.User, '-H') + @(if ($keep.Count) { "--preserve-env=$($keep -join ',')" }) + @('--') + $command
    }
    return [pscustomobject]@{ FileName = $all[0]; Arguments = @($all | Select-Object -Skip 1); Environment = $environment }
}

# Every process of the session user, ended; a session must leave nothing running that could watch its game being graded.
function Stop-SessionProcesses {
    $iso = $script:Isolation
    if (-not $iso -or -not $iso.UserMade) { return }
    for ($i = 0; $i -lt 20; $i++) {
        $result = Invoke-IsolationCommand @('pkill', '-KILL', '-u', $iso.User) -Elevated
        if ($result.Code -eq 1) { return }
        Start-Sleep -Milliseconds 250
    }
    Write-BenchLog "WARNING: processes of $($iso.User) are still running"
}

# Before a session: a fresh HOME, and the game copy handed to the session user (its .git kept aside for grading).
function Enter-IsolatedSession([string]$GameDir) {
    $iso = $script:Isolation
    Assert-IsolationCommand @('rm', '-rf', '--', $iso.Home) 'clearing the session HOME'
    New-Item -ItemType Directory -Force (Join-Path $iso.Home 'tmp') | Out-Null
    Assert-IsolationCommand @('chown', '-R', "$($iso.User):$($iso.User)", $iso.Home) 'handing HOME to the session user'
    Assert-IsolationCommand @('chmod', '700', $iso.Home) 'closing HOME'
    if (-not $GameDir) { return }
    $git = Join-Path $GameDir '.git'
    if (Test-Path -LiteralPath $git) { Copy-Item -LiteralPath $git -Destination (Join-Path $iso.Private "$(Split-Path $GameDir -Leaf).git") -Recurse -Force }
    Assert-IsolationCommand @('chown', '-R', '-h', "$($iso.User):$($iso.User)", $GameDir) 'handing the game to the session user'
    Assert-IsolationCommand @('chmod', '700', $GameDir) 'closing the game to everyone else'
}

# After a session: its processes ended, the game the runner's again and closed to others. Links leading out of the game
# and special files go (the grader writes hidden tests into the game as the runner, and must not write through a link),
# and the .git from before the session comes back (a session's git configuration could run commands when the grader
# runs git).
function Exit-IsolatedSession([string]$GameDir) {
    $iso = $script:Isolation
    Stop-SessionProcesses
    if ($GameDir -and (Test-Path -LiteralPath $GameDir)) {
        Assert-IsolationCommand @('chown', '-R', '-h', $iso.Runner, $GameDir) 'handing the game back to the runner'
        Assert-IsolationCommand @('chmod', '-R', 'u+rwX,go-rwx', $GameDir) 'closing the game'
        $root = (Resolve-Path -LiteralPath $GameDir).Path.TrimEnd('/') + '/'
        $removed = 0
        foreach ($line in @((Invoke-IsolationCommand @('find', $GameDir, '(', '-type', 'l', '-o', '-type', 'p', '-o', '-type', 's', '-o', '-type', 'b', '-o', '-type', 'c', ')', '-print0')).Out -split "`0" | Where-Object { $_ })) {
            $item = Get-Item -LiteralPath $line -Force -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            if ($item.LinkType) {
                $target = (Invoke-IsolationCommand @('readlink', '-m', $line)).Out.Trim()
                if ("$target/".StartsWith($root) -and $target -notlike "$root.git*") { continue }
            }
            Remove-Item -LiteralPath $line -Force -Recurse -ErrorAction SilentlyContinue
            $removed++
        }
        if ($removed) { Write-BenchLog "  removed $removed link(s) out of the game or special file(s) the session left" }
        $kept = Join-Path $iso.Private "$(Split-Path $GameDir -Leaf).git"
        if (Test-Path -LiteralPath $kept) {
            Remove-Item -LiteralPath (Join-Path $GameDir '.git') -Recurse -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $kept -Destination (Join-Path $GameDir '.git')
        }
    }
    Invoke-IsolationCommand @('rm', '-rf', '--', $iso.Home) -Elevated | Out-Null
}

# The end of the run: the session user and the run folder removed, the checkout's mode and the temporary folder restored.
function Remove-SessionIsolation {
    $iso = $script:Isolation
    if (-not $iso) { return }
    Stop-SessionProcesses
    if ($iso.UserMade) {
        $gone = $false
        for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
            $gone = (Invoke-IsolationCommand @('userdel', $iso.User) -Elevated).Code -eq 0
            if (-not $gone) { Stop-SessionProcesses; Start-Sleep -Milliseconds 500 }
        }
        if (-not $gone) { Write-BenchLog "WARNING: could not remove the user $($iso.User); remove it with userdel" }
    }
    if ($iso.RepoMode) { Invoke-IsolationCommand @('chmod', $iso.RepoMode, $iso.RepoRoot) -Elevated | Out-Null }
    if ($iso.OldTemp) { $env:TMPDIR = $iso.OldTemp } else { Remove-Item Env:TMPDIR -ErrorAction SilentlyContinue }
    if ($iso.Base -and (Test-Path -LiteralPath $iso.Base)) { Invoke-IsolationCommand @('rm', '-rf', '--', $iso.Base) -Elevated | Out-Null }
    $script:Isolation = $null
}
