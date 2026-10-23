# The interchangeable test runners. Each writes JUnit or TRX into its own results folder and is then
# summarised the same way (Write-TestSummary).
#
#   dotnet     dotnet test on the solution: xUnit, NUnit, MSTest and any gdUnit4Net suites in it
#   gdunit4    gdUnit4Net only, on the Godot project's csproj; [RequireGodotRuntime] tests run in headless Godot
#   godottest  Chickensoft GoDotTest: the game runs its own suites from a runner scene
#   gut        GUT (GDScript): .gutconfig.json if present, else test_*.gd next to any GutTest script
#   smoke      plays the main scene for N frames and fails on any engine or script error
#   validate   loads every script, scene and resource and instantiates every scene (tools/validate.gd)
#   architecture  a static scan of the scripts for structural problems (lib/Architecture.ps1); warnings unless configured
#   juice      a bot run that checks each gameplay event got its feedback in time (lib/Juice.ps1, juice.json)
#   playthrough  the game's bot plays to the ending; fails unless every milestone line is logged, in order
#              (lib/Playthrough.ps1, playthrough.json)
#   l10n       translation tables: duplicate, untranslated, missing and too long keys; translation remaps and localized
#              sounds against their source, with ffmpeg (lib/Localization.ps1); every character of every translation
#              against the project's fonts, in headless Godot (tools/glyphs.gd)
#   data       data tables against data.json: ids, fields, types, ranges, references (lib/Data.ps1); no Godot needed
#   textsize   text sizes in real pixels on a small screen such as the Steam Deck's (lib/TextSize.ps1, textsize.json)
#   layout     screens on phones, a tablet and an ultrawide: off screen, notch, touch target size (lib/Layout.ps1, layout.json)
#
# -Filter means: dotnet/gdunit4 `dotnet test --filter`; godottest suite name; gut test name.

# gdUnit4Net reads GODOT_BIN and the Godot arguments from here; other frameworks ignore the GdUnit4
# section. No TreatNoTestsAsError: with a filter, projects without a match would fail the run, and
# Write-TestSummary already fails runs that report nothing. CompileProcessTimeout: gdUnit4Net rebuilds the project in
# the editor before running, and its 20 s default runs out on a loaded machine or a cold Windows runner; the kit
# then runs no Godot test and only the exit code says so.
function New-RunSettings([string]$ResultsDir) {
    $path = Join-Path $ResultsDir 'godot.runsettings'
    Set-Content -LiteralPath $path -Encoding utf8 -Value @"
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <RunConfiguration>
    <MaxCpuCount>1</MaxCpuCount>
    <TestSessionTimeout>1800000</TestSessionTimeout>
    <EnvironmentVariables>
      <GODOT_BIN>$([System.Security.SecurityElement]::Escape($env:GODOT_BIN))</GODOT_BIN>
    </EnvironmentVariables>
  </RunConfiguration>
  <GdUnit4>
    <Parameters>--headless</Parameters>
    <DisplayName>FullyQualifiedName</DisplayName>
    <CaptureStdOut>true</CaptureStdOut>
    <CompileProcessTimeout>180000</CompileProcessTimeout>
  </GdUnit4>
</RunSettings>
"@
    return $path
}

function Invoke-DotnetTest([string]$Target, [string]$ResultsDir, [string]$Filter, [bool]$Coverage, [string]$Prefix) {
    $arguments = @('test', $Target, '--settings', (New-RunSettings $ResultsDir), '--results-directory', $ResultsDir,
        '--logger', "trx;LogFilePrefix=$Prefix")
    if ($Filter) { $arguments += '--filter', $Filter }
    if ($Coverage) { $arguments += '--collect', 'XPlat Code Coverage' }
    Start-LogGroup "dotnet test $Target"
    $code = Invoke-Logged dotnet $arguments
    Stop-LogGroup
    return $code
}

# One case per file from tools/validate.gd's markers; errors printed between a file's markers fail it.
function ConvertFrom-ValidateLog([string]$LogFile, [string]$Marker = 'validate') {
    $cases = @(); $current = $null; $buffer = @(); $outside = @(); $since = @()
    $lines = @(Get-Content -LiteralPath $LogFile | ForEach-Object { $_ -replace "`e\[[0-9;]*m", '' })
    # Godot 4.5+: validate.gd's logger prints each file's errors on stdout before its end marker ("@@validate error").
    # stderr reaches the log out of order with stdout, so its lines between a file's markers may be another file's: then
    # only the logger's lines are the file's, and stderr counts as outside any file.
    $logged = @($lines | Where-Object { $_.StartsWith("@@$Marker error ") }).Count -gt 0
    foreach ($line in $lines) {
        if ($line -match "^@@$Marker begin (?<path>.+)`$") {
            $current = $Matches.path; $buffer = @(); $since = @()
        } elseif ($current -and $line.StartsWith("@@$Marker end $current ")) {
            # Matched by the known path rather than a regex: paths may contain spaces.
            $status = $line.Substring("@@$Marker end $current ".Length)
            $problems = @(Select-GodotErrors $buffer)
            if ($status -ne 'ok') { $problems = @($status) + $problems }
            $cases += @{ Name = $current; Failure = ($problems -join "`n") }
            $current = $null
        } elseif ($current) {
            $since += $line
            if ($line.StartsWith("@@$Marker error ")) { $buffer += $line.Substring("@@$Marker error ".Length) }
            elseif ($logged) { $outside += $line }
            else { $buffer += $line }
        } else {
            $outside += $line
        }
    }
    # A file whose end marker never came stopped Godot (a crash, OS.crash, a time-out): it fails, with what was printed
    # after its begin marker, rather than being left out.
    if ($current) {
        $crash = @($since | Where-Object { $_ -match 'Program crashed with signal|was still running after' } | ForEach-Object { $_.Trim() })
        $cases += @{ Name = $current; Failure = (@("Godot stopped while checking this file") + $crash + @(Select-GodotErrors $since)) -join "`n" }
    }
    # Errors outside any file (before the first: autoloads, project settings; with the logger, all of stderr) belong to the
    # project as a whole, unless a file already reported the same error (stderr can reach the log away from its file's markers).
    $reported = ($cases | ForEach-Object { $_.Failure }) -join "`n"
    $startup = @(Select-GodotErrors $outside | Where-Object { -not $reported.Contains(($_ -replace '^\s*(SHADER ERROR|SCRIPT ERROR|ERROR):\s*', '').Trim()) })
    if ($startup.Count -gt 0) { $cases += @{ Name = 'project startup'; Failure = ($startup -join "`n") } }
    return $cases
}

# GUT skips a test script that does not load (a parse error) with a warning, "Ignoring script ... because it does not
# extend GutTest", and the run still passes. Such a script fails as a case named after the file, with its parse error when
# the log has one: one that extends GutTest on disk, or that the log says failed to load (it may extend another test).
function Get-GutLoadFailures([string]$LogFile, [string]$ProjectDir) {
    $lines = @(Get-Content -LiteralPath $LogFile | ForEach-Object { $_ -replace "`e\[[0-9;]*m", '' })
    $seen = @{}
    foreach ($line in $lines) {
        if ($line -notmatch 'Ignoring script (?<res>res://.+?) because it does not extend GutTest') { continue }
        $res = $Matches.res
        if ($seen.ContainsKey($res)) { continue }
        $seen[$res] = $true
        $why = @(for ($i = 0; $i -lt $lines.Count - 1; $i++) {
            if ($lines[$i] -match '^\s*SCRIPT ERROR:' -and $lines[$i + 1].Contains("($res`:")) { "$($lines[$i].Trim()) $($lines[$i + 1].Trim())" }
        })
        $failedToLoad = @($lines | Where-Object { $_.Contains("Failed to load script `"$res`"") }).Count -gt 0
        $file = Join-Path $ProjectDir $res.Substring(6)
        $isTest = (Test-Path -LiteralPath $file) -and (Get-Content -LiteralPath $file -Raw) -match '(?m)^extends\s+GutTest\b'
        if (-not ($isTest -or $failedToLoad -or $why)) { continue }
        @{ Name = $res; Failure = (@("$res does not load, so GUT skipped its tests") + $why) -join "`n" }
    }
}

function Invoke-TestRunner {
    param([string]$Runner, $Info, [string]$ResultsDir, [string]$Filter, [bool]$Coverage, [int]$Frames, [string[]]$GameArgs, [int]$FixedFps = 0)

    if (Test-Path -LiteralPath $ResultsDir) { Remove-Item -LiteralPath $ResultsDir -Recurse -Force }
    New-Item -ItemType Directory -Force $ResultsDir | Out-Null
    $godot = $env:GODOT_BIN
    $project = $Info.ProjectDir
    $code = 0

    switch ($Runner) {
        'dotnet' {
            if (-not $Info.Solution) { Stop-GodotCi "dotnet runner: no .sln/.csproj found (pass -Solution)" }
            $code = Invoke-DotnetTest $Info.Solution $ResultsDir $Filter $Coverage 'dotnet'
        }
        'gdunit4' {
            $csproj = if ($Info.Solution -like '*.csproj') { $Info.Solution } else {
                (Get-ChildItem -LiteralPath $project -File -Filter '*.csproj' | Select-Object -First 1).FullName }
            if (-not $csproj) { Stop-GodotCi "gdunit4 runner: no .csproj in $project" }
            if ((Get-Content -LiteralPath $csproj -Raw) -notmatch 'gdUnit4\.test\.adapter') {
                Stop-GodotCi "gdunit4 runner: $csproj does not reference gdUnit4.test.adapter"
            }
            $code = Invoke-DotnetTest $csproj $ResultsDir $Filter $Coverage 'gdunit4'
        }
        'godottest' {
            $log = Join-Path $ResultsDir 'godottest.log'
            $sceneArgs = if ($Info.GoDotTestScene) { @($Info.GoDotTestScene) } else { @() }
            $testArgs = @('--headless', '--path', $project) + $sceneArgs + @("--run-tests$(if ($Filter) { "=$Filter" })", '--quit-on-finish')
            Start-LogGroup "GoDotTest $($Info.GoDotTestScene)"
            if ($Coverage) {
                # The editor runs the Debug build; an ExportRelease folder left by an export must not be used.
                $bin = Join-Path $project '.godot/mono/temp/bin/Debug'
                if (-not (Test-Path -LiteralPath $bin)) { Stop-GodotCi "godottest: no Debug build in $bin" }
                $coverlet = Get-DotnetTool 'coverlet.console' 'coverlet'
                New-Item -ItemType Directory -Force (Join-Path $ResultsDir 'coverage') | Out-Null
                # coverlet hands --targetargs to Godot as one string, so quote the path.
                $targetArgs = (($testArgs + '--coverage') | ForEach-Object { if ($_ -match '\s') { """$_""" } else { $_ } }) -join ' '
                $code = Invoke-Logged $coverlet @($bin, '--target', $godot, '--targetargs', $targetArgs,
                    '--format', 'cobertura', '--output', (Join-Path $ResultsDir 'coverage/godottest.cobertura.xml'),
                    '--exclude-by-file', '**/test/**/*.cs', '--exclude-assemblies-without-sources', 'MissingAll') $log
            } else {
                $code = Invoke-Logged $godot $testArgs $log
            }
            Stop-LogGroup
            ConvertFrom-GoDotTestLog $log (Join-Path $ResultsDir 'godottest.junit.xml')
        }
        'gut' {
            if (-not (Test-Path -LiteralPath (Join-Path $project 'addons/gut/gut_cmdln.gd'))) {
                Stop-GodotCi "gut runner: addons/gut is missing"
            }
            $gutArgs = @('--headless', '--path', $project, '-s', 'addons/gut/gut_cmdln.gd', '-gexit', '-gdisable_colors',
                "-gjunit_xml_file=$(Join-Path $ResultsDir 'gut.junit.xml')")
            if (-not (Test-Path -LiteralPath (Join-Path $project '.gutconfig.json'))) {
                # Search every folder that holds a script extending GutTest.
                Get-GutTestFiles $project | ForEach-Object { ConvertTo-ResPath $project $_.DirectoryName } |
                    Sort-Object -Unique | ForEach-Object { $gutArgs += "-gdir=$_" }
            }
            if ($Filter) { $gutArgs += "-gunit_test_name=$Filter" }
            Start-LogGroup 'GUT'
            $code = Invoke-Logged $godot $gutArgs (Join-Path $ResultsDir 'gut.log')
            Stop-LogGroup
            $unloaded = @(Get-GutLoadFailures (Join-Path $ResultsDir 'gut.log') $project)
            if ($unloaded.Count -gt 0) { Write-JUnitCases (Join-Path $ResultsDir 'gut-load.junit.xml') 'gut' $unloaded }
        }
        'validate' {
            $log = Join-Path $ResultsDir 'validate.log'
            $tool = (Join-Path $PSScriptRoot '../tools/validate.gd' | Resolve-Path).Path -replace '\\', '/'
            Start-LogGroup 'Validate scripts, scenes and resources'
            $code = Invoke-Logged $godot @('--headless', '--path', $project, '-s', $tool) $log
            Stop-LogGroup
            $cases = @(ConvertFrom-ValidateLog $log)
            if ($code -ne 0) { $cases += @{ Name = 'validate'; Failure = "Godot exited with $code" } }
            Write-JUnitCases (Join-Path $ResultsDir 'validate.junit.xml') 'validate' $cases
        }
        'flows' {
            $log = Join-Path $ResultsDir 'flows.log'
            $tool = (Join-Path $PSScriptRoot '../tools/flows.gd' | Resolve-Path).Path -replace '\\', '/'
            Start-LogGroup 'UI flows'
            $code = Invoke-Logged $godot @('--headless', '--path', $project, '-s', $tool, '--', $Filter) $log
            Stop-LogGroup
            $cases = @(ConvertFrom-ValidateLog $log 'flow')
            if ($code -ne 0) { $cases += @{ Name = 'flows'; Failure = "Godot exited with $code" } }
            Write-JUnitCases (Join-Path $ResultsDir 'flows.junit.xml') 'flows' $cases
        }
        'juice' {
            $code = Invoke-JuiceRunner $Info $ResultsDir $GameArgs
        }
        'playthrough' {
            $code = Invoke-PlaythroughRunner $Info $ResultsDir $GameArgs
        }
        'architecture' {
            $code = Invoke-ArchitectureRunner $project $ResultsDir
        }
        'l10n' {
            $code = Invoke-LocalizationRunner $project $ResultsDir
        }
        'data' {
            $code = Invoke-DataRunner $project $ResultsDir
        }
        'layout' {
            $code = Invoke-LayoutRunner $Info $ResultsDir
        }
        'textsize' {
            $code = Invoke-TextSizeRunner $Info $ResultsDir
        }
        'smoke' {
            $log = Join-Path $ResultsDir 'smoke.log'
            Start-LogGroup "Smoke run ($Frames frames$(if ($FixedFps -gt 0) { " at a fixed $FixedFps fps" }))"
            $smokeArgs = @('--headless', '--path', $project, '--quit-after', "$Frames") + $(if ($FixedFps -gt 0) { @('--fixed-fps', "$FixedFps") }) + $(if ($GameArgs) { @('--') + $GameArgs })
            $code = Invoke-Logged $godot $smokeArgs $log
            Stop-LogGroup
            $errors = @(Get-GodotLogErrors $log)
            $message = if ($code -ne 0) { "Godot exited with $code" }
                elseif ($errors.Count -gt 0) { $errors -join "`n" }
                else { "Main scene ran $Frames frames without errors" }
            if ($errors.Count -gt 0 -and $code -eq 0) { $code = 1 }
            Write-SingleCaseJUnit (Join-Path $ResultsDir 'smoke.junit.xml') 'smoke' ($code -eq 0) $message
        }
    }

    # dotnet's coverage collector writes into per-run GUID folders; gather it in one place.
    if ($Coverage) {
        $coverageDir = Join-Path $ResultsDir 'coverage'
        New-Item -ItemType Directory -Force $coverageDir | Out-Null
        # Matched below the results folder only, as in Write-TestSummary.
        $base = (Get-Item -LiteralPath $ResultsDir).FullName.TrimEnd('\', '/').Length
        Get-ChildItem -LiteralPath $ResultsDir -Recurse -File -Filter 'coverage.cobertura.xml' |
            Where-Object { $_.FullName.Substring($base) -notmatch '[\\/](coverage|In)[\\/]' } |
            ForEach-Object { Move-Item -LiteralPath $_.FullName (Join-Path $coverageDir "$Runner-$($_.Directory.Name).cobertura.xml") }
    }

    $summary = Write-TestSummary $Runner $ResultsDir $code ([bool]$Filter)
    $findings = Join-Path $ResultsDir 'findings.json'
    $warnings = @(if (Test-Path -LiteralPath $findings) {
        Get-Content -LiteralPath $findings -Raw | ConvertFrom-Json | Where-Object { $_ -and $_.severity -eq 'warning' }
    })
    $summary | Add-Member -NotePropertyName Warnings -NotePropertyValue $warnings
    # The l10n runner's glyph check, per locale and font, for -Json (runnerResults[].glyphs).
    $glyphs = Join-Path $ResultsDir 'glyphs.json'
    if ($Runner -eq 'l10n' -and (Test-Path -LiteralPath $glyphs)) {
        $summary | Add-Member -NotePropertyName Glyphs -NotePropertyValue (Get-Content -LiteralPath $glyphs -Raw | ConvertFrom-Json)
    }
    return $summary
}

# Invoke-TestRunner with test -Retry and quarantine.json. A runner that still fails after its quarantined tests are set
# aside is run again, whole and with the same -Filter, up to $Retry more times, until an attempt passes; each failed
# attempt's results are kept next to the last one as <runner>.attempt<N>. The result is the last attempt's, plus Attempts
# and Flaky: the tests that failed in an earlier attempt but not in the last, which the run reports and records, so a pass
# on a retry is never a silent green. The whole runner is rerun because not every framework's filter can name a list of
# tests, and the run's own -Filter must still apply.
function Invoke-TestRunnerWithRetry {
    param([string]$Runner, $Info, [string]$ResultsDir, [string]$Filter, [bool]$Coverage, [int]$Frames, [string[]]$GameArgs,
        [int]$Retry = 0, [object[]]$Quarantine = @(), [int]$FixedFps = 0)

    $attempts = [System.Collections.Generic.List[object]]::new()
    while ($true) {
        $result = Invoke-TestRunner -Runner $Runner -Info $Info -ResultsDir $ResultsDir -Filter $Filter -Coverage $Coverage -Frames $Frames -GameArgs $GameArgs -FixedFps $FixedFps
        $result = Set-RunQuarantine $result $Quarantine
        $attempts.Add($result)
        if ($result.Ok -or $attempts.Count -gt $Retry) { break }
        $kept = "$ResultsDir.attempt$($attempts.Count)"
        if (Test-Path -LiteralPath $kept) { Remove-Item -LiteralPath $kept -Recurse -Force }
        Move-Item -LiteralPath $ResultsDir -Destination $kept
        Write-CiLog "$Runner failed on attempt $($attempts.Count) of $($Retry + 1); running it again (-Retry $Retry). That attempt's results: $kept"
    }
    $flaky = @(Get-FlakyTests $attempts.ToArray())
    foreach ($f in $flaky) { Write-CiLog "FLAKY ${Runner}: $($f.Name) failed on attempt $($f.FailedAttempt) and passed on attempt $($attempts.Count)$(if ($f.Message) { " ($($f.Message))" })" }
    foreach ($q in $result.Quarantined) { Write-CiLog "QUARANTINED ${Runner}: $($q.Name) failed; not counted until $($q.Until) (owner $($q.Owner))" }
    $result | Add-Member -Force -NotePropertyName Attempts -NotePropertyValue $attempts.Count
    $result | Add-Member -Force -NotePropertyName Flaky -NotePropertyValue $flaky
    return $result
}
