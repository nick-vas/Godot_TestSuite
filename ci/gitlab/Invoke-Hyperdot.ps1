#Requires -Version 7.2
<#
.SYNOPSIS
    The run step of hyperdot.gitlab-ci.yml: reads the job's HYPERDOT_* variables, the GitLab counterparts of the GitHub
    action's inputs, and runs ci/godot/hyperdot.ps1 with them, results in test-results/ and exports in build/ under the
    checkout (GitLab keeps artifacts and caches only from inside it).

.DESCRIPTION
    Variables (empty means the kit's default, as in .github/actions/godot):
      HYPERDOT_PROJECT        project
      HYPERDOT_GODOT_VERSION  godot-version
      HYPERDOT_RUNNERS        runners
      HYPERDOT_FILTER         filter
      HYPERDOT_RETRY          retry (test only)
      HYPERDOT_COVERAGE       coverage (true or false)
      HYPERDOT_MIN_COVERAGE   min-coverage
      HYPERDOT_PRESET         preset
      HYPERDOT_RUN_EXPORTS    run-exports (true or false)
      HYPERDOT_GAME_VERSION   game-version (export only; auto needs GIT_DEPTH 0)
    -PrintOnly prints the parameters as JSON instead of running (for tests).
#>
[CmdletBinding()]
param(
    [ValidateSet('test', 'build', 'export', 'setup')]
    [string]$Command = 'test',
    [switch]$PrintOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$kit = Join-Path $PSScriptRoot '../godot/hyperdot.ps1'
$checkout = if ($env:CI_PROJECT_DIR) { $env:CI_PROJECT_DIR } else { $PWD.Path }

$params = [ordered]@{ Results = (Join-Path $checkout 'test-results'); Output = (Join-Path $checkout 'build') }
if ($env:HYPERDOT_PROJECT) { $params.Project = Join-Path $checkout $env:HYPERDOT_PROJECT }
if ($env:HYPERDOT_GODOT_VERSION) { $params.GodotVersion = $env:HYPERDOT_GODOT_VERSION }
if ($env:HYPERDOT_RUNNERS) { $params.Runners = $env:HYPERDOT_RUNNERS }
if ($env:HYPERDOT_FILTER) { $params.Filter = $env:HYPERDOT_FILTER }
if ($Command -eq 'test' -and $env:HYPERDOT_RETRY -and [int]$env:HYPERDOT_RETRY -gt 0) { $params.Retry = [int]$env:HYPERDOT_RETRY }
if ($env:HYPERDOT_COVERAGE -eq 'true') { $params.Coverage = $true }
if ($env:HYPERDOT_MIN_COVERAGE -and [double]::Parse($env:HYPERDOT_MIN_COVERAGE, [cultureinfo]::InvariantCulture) -gt 0) {
    $params.MinCoverage = [double]::Parse($env:HYPERDOT_MIN_COVERAGE, [cultureinfo]::InvariantCulture)
}
if ($env:HYPERDOT_PRESET) { $params.Preset = $env:HYPERDOT_PRESET }
if ($Command -eq 'export' -and $env:HYPERDOT_RUN_EXPORTS -eq 'true') { $params.Run = $true }
if ($Command -eq 'export' -and $env:HYPERDOT_GAME_VERSION) { $params.GameVersion = $env:HYPERDOT_GAME_VERSION }

if ($PrintOnly) {
    [Console]::Out.WriteLine((@{ command = $Command; parameters = $params } | ConvertTo-Json -Depth 3))
    exit 0
}
& $kit $Command @params
exit $LASTEXITCODE
