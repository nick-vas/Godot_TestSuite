#!/usr/bin/env pwsh
# Self-test of Publish-PrComment.ps1 against a stand-in for the GitHub API on 127.0.0.1 (GITHUB_API_URL points at it): on a
# pull request with 250 comments, the summary comment on the third page is found and updated, not posted again; with no
# summary yet, every page is read and one comment is posted. A comment by someone else that starts with the marker is
# never taken for the summary, and the coverage baseline comes only from a push run of this repository's base branch, not
# from a fork's branch of the same name or a pull request run. No network, no Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tool = Join-Path $root 'ci/godot/tools/Publish-PrComment.ps1'
$results = Join-Path ([System.IO.Path]::GetTempPath()) "pr-comment-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $results | Out-Null
$failures = @()

# A free port, then a listener on it in a thread job that answers like GitHub: pages of 100 comments, PATCH and POST.
function Get-FreePort {
    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
    return $port
}
# ForgedAt: a comment by a user that starts with the marker. Zips: artifact id -> zip of a summary.json, served with the
# artifact list and runs below.
function Start-FakeGitHub([int]$Port, [int]$Total, [int]$SummaryAt, [int]$ForgedAt = 0, [hashtable]$Zips = @{}) {
    Start-ThreadJob -ArgumentList $Port, $Total, $SummaryAt, $ForgedAt, $Zips -ScriptBlock {
        param($Port, $Total, $SummaryAt, $ForgedAt, $Zips)
        # Newest first, as GitHub lists them: a fork's main (repository 2), a pull request run inside the repository from
        # a branch named main, then the real push to main.
        $artifacts = @(
            @{ id = 1; expired = $false; archive_download_url = "http://127.0.0.1:$Port/zip/1"; workflow_run = @{ id = 11; repository_id = 1; head_repository_id = 2; head_branch = 'main' } }
            @{ id = 3; expired = $false; archive_download_url = "http://127.0.0.1:$Port/zip/3"; workflow_run = @{ id = 13; repository_id = 1; head_repository_id = 1; head_branch = 'main' } }
            @{ id = 2; expired = $false; archive_download_url = "http://127.0.0.1:$Port/zip/2"; workflow_run = @{ id = 12; repository_id = 1; head_repository_id = 1; head_branch = 'main' } }
        )
        $runs = @{
            '11' = @{ id = 11; event = 'pull_request'; head_repository = @{ full_name = 'fork/r' } }
            '13' = @{ id = 13; event = 'pull_request'; head_repository = @{ full_name = 'o/r' } }
            '12' = @{ id = 12; event = 'push'; head_repository = @{ full_name = 'o/r' } }
        }
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://127.0.0.1:$Port/")
        $listener.Start()
        try {
            while ($true) {
                $context = $listener.GetContext()
                $request = $context.Request
                $path = $request.Url.AbsolutePath
                "$($request.HttpMethod) $($request.Url.PathAndQuery)"
                if ($request.HttpMethod -in 'POST', 'PATCH') {
                    $reader = [System.IO.StreamReader]::new($request.InputStream)
                    "BODY $($reader.ReadToEnd())"
                    $reader.Dispose()
                }
                $body = '{}'
                $bytes = $null
                if ($request.HttpMethod -eq 'GET' -and $path -eq '/repos/o/r/actions/artifacts') {
                    $body = @{ total_count = $artifacts.Count; artifacts = $artifacts } | ConvertTo-Json -Depth 5 -Compress
                } elseif ($request.HttpMethod -eq 'GET' -and $path -match '^/repos/o/r/actions/runs/(\d+)$') {
                    $body = $runs[$Matches[1]] | ConvertTo-Json -Depth 5 -Compress
                } elseif ($request.HttpMethod -eq 'GET' -and $path -match '^/zip/(\d+)$') {
                    $bytes = [System.IO.File]::ReadAllBytes($Zips[$Matches[1]])
                    $context.Response.ContentType = 'application/zip'
                } elseif ($request.HttpMethod -eq 'GET' -and $path -eq '/repos/o/r/issues/7/comments') {
                    $page = [int]$request.QueryString['page']; if ($page -lt 1) { $page = 1 }
                    $size = [int]$request.QueryString['per_page']; if ($size -lt 1) { $size = 30 }
                    $first = ($page - 1) * $size + 1
                    $last = [Math]::Min($Total, $page * $size)
                    $items = @(for ($i = $first; $i -le $last; $i++) {
                        if ($i -eq $SummaryAt) { @{ id = $i; body = "<!-- hyperdot:game -->`nold summary"; user = @{ login = 'github-actions[bot]'; type = 'Bot' } } }
                        elseif ($i -eq $ForgedAt) { @{ id = $i; body = "<!-- hyperdot:game -->`nlooks like a summary"; user = @{ login = 'mallory'; type = 'User' } } }
                        else { @{ id = $i; body = "comment $i"; user = @{ login = 'someone'; type = 'User' } } }
                    })
                    $body = ConvertTo-Json -InputObject $items -Depth 3 -Compress
                    if (-not $items.Count) { $body = '[]' }
                } elseif ($path -eq '/stop') {
                    $context.Response.Close()
                    break
                }
                if ($null -eq $bytes) {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $context.Response.ContentType = 'application/json'
                }
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.Close()
            }
        } finally { $listener.Stop() }
    }
}
function Invoke-Publish([int]$Port, [string]$ResultsDir = $results, [string]$BaseRef = $null) {
    # Name and value pairs, not a hashtable: environment names are case-sensitive on Linux (NO_PROXY and no_proxy).
    $variables = @(
        @('GITHUB_API_URL', "http://127.0.0.1:$Port"), @('GITHUB_REPOSITORY', 'o/r'), @('GITHUB_TOKEN', 'test'),
        @('GITHUB_SERVER_URL', 'https://github.com'), @('GITHUB_RUN_ID', '1'), @('GITHUB_EVENT_PATH', $null), @('GITHUB_BASE_REF', $BaseRef),
        @('NO_PROXY', '127.0.0.1,localhost'), @('no_proxy', '127.0.0.1,localhost'))
    $saved = @(foreach ($pair in $variables) { , @($pair[0], [Environment]::GetEnvironmentVariable($pair[0])) })
    foreach ($pair in $variables) { [Environment]::SetEnvironmentVariable($pair[0], $pair[1]) }
    try { return @(& pwsh -NoProfile -File $tool -ResultsDir $ResultsDir -Name game -ArtifactName results -PullRequest 7 2>&1) -join ' ' }
    finally { foreach ($pair in $saved) { [Environment]::SetEnvironmentVariable($pair[0], $pair[1]) } }
}
function Stop-FakeGitHub($Job, [int]$Port) {
    try { Invoke-RestMethod "http://127.0.0.1:$Port/stop" -NoProxy -TimeoutSec 5 | Out-Null } catch { Write-Host "stop: $($_.Exception.Message)" }
    $requests = @(Receive-Job $Job -Wait -AutoRemoveJob)
    return $requests
}

try {
    # The summary is comment 230 of 250: on page 3.
    $port = Get-FreePort
    $job = Start-FakeGitHub $port 250 230
    Start-Sleep -Milliseconds 500
    $output = Invoke-Publish $port
    $requests = @(Stop-FakeGitHub $job $port)
    $gets = @($requests | Where-Object { $_ -like 'GET /repos/o/r/issues/7/comments*' })
    if ($output -notmatch 'Updated the test summary comment on #7') { $failures += "the summary on page 3 should be updated: $output" }
    if (-not ($requests -contains 'PATCH /repos/o/r/issues/comments/230')) { $failures += "comment 230 should be patched: $($requests -join ' | ')" }
    if (@($requests | Where-Object { $_ -like 'POST *' }).Count) { $failures += "no new comment should be posted: $($requests -join ' | ')" }
    if ($gets.Count -ne 3 -or $gets[2] -notmatch 'page=3') { $failures += "pages 1 to 3 should be read: $($gets -join ' | ')" }

    # No summary yet: every page is read (the last one is short), then one comment is posted.
    $port = Get-FreePort
    $job = Start-FakeGitHub $port 250 0
    Start-Sleep -Milliseconds 500
    $output = Invoke-Publish $port
    $requests = @(Stop-FakeGitHub $job $port)
    $gets = @($requests | Where-Object { $_ -like 'GET /repos/o/r/issues/7/comments*' })
    if ($output -notmatch 'Posted the test summary comment on #7') { $failures += "a summary should be posted: $output" }
    if (-not ($requests -contains 'POST /repos/o/r/issues/7/comments')) { $failures += "one comment should be posted: $($requests -join ' | ')" }
    if ($gets.Count -ne 3) { $failures += "all three pages should be read: $($gets -join ' | ')" }

    # Someone else's comment that starts with the marker (comment 40) comes before the real summary (230): the summary is
    # the one updated, and the other is left alone.
    $port = Get-FreePort
    $job = Start-FakeGitHub $port 250 230 -ForgedAt 40
    Start-Sleep -Milliseconds 500
    $output = Invoke-Publish $port
    $requests = @(Stop-FakeGitHub $job $port)
    if (-not ($requests -contains 'PATCH /repos/o/r/issues/comments/230') -or ($requests -match '/comments/40$')) { $failures += "only the bot's summary (230) should be updated, not comment 40: $($requests -join ' | ')" }

    # Only the forged comment: a summary of our own is posted.
    $port = Get-FreePort
    $job = Start-FakeGitHub $port 50 0 -ForgedAt 10
    Start-Sleep -Milliseconds 500
    $output = Invoke-Publish $port
    $requests = @(Stop-FakeGitHub $job $port)
    if (-not ($requests -contains 'POST /repos/o/r/issues/7/comments') -or @($requests | Where-Object { $_ -like 'PATCH *' }).Count) { $failures += "a summary should be posted beside the forged one: $($requests -join ' | ')" }

    # Coverage against main: the fork's artifact (99%) and the pull request run's (70%) come first, the push run's (50%)
    # is the baseline.
    $withCoverage = Join-Path $results 'coverage'
    New-Item -ItemType Directory -Force $withCoverage | Out-Null
    '{"coverage": 60}' | Set-Content -LiteralPath (Join-Path $withCoverage 'summary.json')
    '| Runner | Passed |', '|---|---|', '| gut | 3 |' | Set-Content -LiteralPath (Join-Path $withCoverage 'summary.md')
    $zips = @{}
    foreach ($pair in @(@('1', 99), @('3', 70), @('2', 50))) {
        $dir = Join-Path $results "artifact-$($pair[0])"
        New-Item -ItemType Directory -Force $dir | Out-Null
        "{""coverage"": $($pair[1])}" | Set-Content -LiteralPath (Join-Path $dir 'summary.json')
        $zip = Join-Path $results "artifact-$($pair[0]).zip"
        Compress-Archive -Path (Join-Path $dir 'summary.json') -DestinationPath $zip -Force
        $zips[$pair[0]] = $zip
    }
    $port = Get-FreePort
    $job = Start-FakeGitHub $port 5 0 -Zips $zips
    Start-Sleep -Milliseconds 500
    $output = Invoke-Publish $port -ResultsDir $withCoverage -BaseRef main
    $requests = @(Stop-FakeGitHub $job $port)
    $posted = @($requests | Where-Object { $_ -like 'BODY *' })
    $comment = if ($posted) { ($posted[0].Substring(5) | ConvertFrom-Json).body } else { '' }
    if ($comment -notmatch 'Coverage vs `main`: 50% -> 60% \(\+10\)') { $failures += "the baseline should be the push run's 50%: $comment | $output" }
    if ($requests -contains 'GET /zip/1' -or $requests -contains 'GET /zip/3') { $failures += "a fork's or pull request run's artifact was downloaded: $($requests -join ' | ')" }
} finally {
    Remove-Item -Recurse -Force $results -ErrorAction SilentlyContinue
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'Publish-PrComment reads every page of comments: it updates its own summary past the first 100, posts one only when there is none, and compares coverage with a push to the base branch'
exit 0
