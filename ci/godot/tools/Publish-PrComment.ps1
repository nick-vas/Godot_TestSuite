#Requires -Version 7.2
<#
.SYNOPSIS
    Posts (or updates) one comment per game on a pull request with the test summary, and coverage
    compared with the latest run on the base branch. Used by .github/workflows/godot.yml.
    Needs GITHUB_TOKEN with pull-requests: write; without it, it warns instead of failing the run. Pull requests from
    forks get a notice instead: their token is read-only.
#>
param(
    [Parameter(Mandatory)][string]$ResultsDir,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$ArtifactName,
    [Parameter(Mandatory)][int]$PullRequest,
    [string]$Outcome = 'success'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$api = if ($env:GITHUB_API_URL) { $env:GITHUB_API_URL } else { 'https://api.github.com' }
$repo = $env:GITHUB_REPOSITORY
$headers = @{ Authorization = "Bearer $env:GITHUB_TOKEN"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
$runUrl = "$env:GITHUB_SERVER_URL/$repo/actions/runs/$env:GITHUB_RUN_ID"
$marker = "<!-- godot-test-suite:$Name -->"

# A pull request from a fork runs with a read-only token, whatever the workflow's permissions say: the comment would
# fail with a misleading hint. Say so once and leave the job summary, which forks do get, to carry the results.
function Test-ForkPullRequest {
    if (-not $env:GITHUB_EVENT_PATH -or -not (Test-Path -LiteralPath $env:GITHUB_EVENT_PATH)) { return $false }
    $eventData = Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json -AsHashtable
    if (-not $eventData.Contains('pull_request')) { return $false }
    $head = $eventData['pull_request']['head']['repo']
    return $null -ne $head -and $head['full_name'] -ne $repo
}
if (Test-ForkPullRequest) {
    Write-Host "::notice title=No PR comment::This pull request comes from a fork, whose token cannot comment; the results are in the job summary."
    return
}

# Coverage of the newest run on the base branch, from its summary.json, for the comparison line.
function Get-BaselineCoverage {
    if (-not $env:GITHUB_BASE_REF) { return $null }
    try {
        $artifacts = (Invoke-RestMethod -Headers $headers "$api/repos/$repo/actions/artifacts?name=$([uri]::EscapeDataString($ArtifactName))&per_page=50").artifacts
        $baseline = $null
        foreach ($artifact in $artifacts) {
            if (-not $artifact.expired -and $artifact.workflow_run.head_branch -eq $env:GITHUB_BASE_REF) { $baseline = $artifact; break }
        }
        if (-not $baseline) { return $null }
        $zip = Join-Path ([IO.Path]::GetTempPath()) "baseline-$([guid]::NewGuid()).zip"
        Invoke-WebRequest -Headers $headers -Uri $baseline.archive_download_url -OutFile $zip
        $dir = "$zip.d"
        Expand-Archive -LiteralPath $zip -DestinationPath $dir
        $summary = Get-ChildItem -LiteralPath $dir -Recurse -Filter 'summary.json' | Select-Object -First 1
        if (-not $summary) { return $null }
        return (Get-Content -LiteralPath $summary.FullName -Raw | ConvertFrom-Json).coverage
    } catch {
        Write-Host "No coverage baseline from $env:GITHUB_BASE_REF ($($_.Exception.Message))"
        return $null
    }
}

$summaryJson = Join-Path $ResultsDir 'summary.json'
$summaryMd = Join-Path $ResultsDir 'summary.md'
$ok = $Outcome -eq 'success'
$body = [System.Collections.Generic.List[string]]::new()
$body.Add($marker)
$body.Add("### $([char]::ConvertFromUtf32($(if ($ok) { 0x2705 } else { 0x274C }))) Godot tests: $Name")
$body.Add('')
if (Test-Path -LiteralPath $summaryMd) {
    $body.AddRange([string[]](Get-Content -LiteralPath $summaryMd))
    $coverage = (Get-Content -LiteralPath $summaryJson -Raw | ConvertFrom-Json).coverage
    if ($null -ne $coverage) {
        $baseline = Get-BaselineCoverage
        if ($null -ne $baseline) {
            $delta = [math]::Round($coverage - $baseline, 1)
            $sign = if ($delta -gt 0) { '+' } elseif ($delta -eq 0) { '+/-' } else { '' }
            $body.Add("Coverage vs ``$env:GITHUB_BASE_REF``: $baseline% -> $coverage% ($sign$delta)")
        }
    }
} else {
    $body.Add('The build failed before any tests ran.')
}
$body.Add('')
$body.Add("[Run details]($runUrl)")
$payload = @{ body = ($body -join "`n") } | ConvertTo-Json

try {
    # Every page of comments, not only the first 100: on a busy pull request the summary would otherwise be missed and a
    # new one posted on each run. A page shorter than 100 is the last; the cap stops a server that ignores page=.
    # foreach, not Where-Object: Invoke-RestMethod returns a JSON array as one object (empty or not).
    $existing = $null
    for ($page = 1; -not $existing -and $page -le 100; $page++) {
        $comments = Invoke-RestMethod -Headers $headers "$api/repos/$repo/issues/$PullRequest/comments?per_page=100&page=$page"
        $count = 0
        foreach ($comment in $comments) {
            $count++
            if ($comment.body -and $comment.body.StartsWith($marker)) { $existing = $comment; break }
        }
        if ($count -lt 100) { break }
    }
    if ($existing) {
        Invoke-RestMethod -Method Patch -Headers $headers -Body $payload -ContentType 'application/json' "$api/repos/$repo/issues/comments/$($existing.id)" | Out-Null
        Write-Host "Updated the test summary comment on #$PullRequest"
    } else {
        Invoke-RestMethod -Method Post -Headers $headers -Body $payload -ContentType 'application/json' "$api/repos/$repo/issues/$PullRequest/comments" | Out-Null
        Write-Host "Posted the test summary comment on #$PullRequest"
    }
} catch {
    Write-Host "::warning title=No PR comment::Couldn't comment on the pull request ($($_.Exception.Message)). Give the calling job 'permissions: pull-requests: write' to get the test summary comment."
}
