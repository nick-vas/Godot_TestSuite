#!/usr/bin/env pwsh
# Self-test of Publish-PrComment.ps1 against a stand-in for the GitHub API on 127.0.0.1 (GITHUB_API_URL points at it): on a
# pull request with 250 comments, the summary comment on the third page is found and updated, not posted again; with no
# summary yet, every page is read and one comment is posted. No network, no Godot.
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
function Start-FakeGitHub([int]$Port, [int]$Total, [int]$SummaryAt) {
    Start-ThreadJob -ArgumentList $Port, $Total, $SummaryAt -ScriptBlock {
        param($Port, $Total, $SummaryAt)
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://127.0.0.1:$Port/")
        $listener.Start()
        try {
            while ($true) {
                $context = $listener.GetContext()
                $request = $context.Request
                $path = $request.Url.AbsolutePath
                "$($request.HttpMethod) $($request.Url.PathAndQuery)"
                $body = '{}'
                if ($request.HttpMethod -eq 'GET' -and $path -eq '/repos/o/r/issues/7/comments') {
                    $page = [int]$request.QueryString['page']; if ($page -lt 1) { $page = 1 }
                    $size = [int]$request.QueryString['per_page']; if ($size -lt 1) { $size = 30 }
                    $first = ($page - 1) * $size + 1
                    $last = [Math]::Min($Total, $page * $size)
                    $items = @(for ($i = $first; $i -le $last; $i++) {
                        @{ id = $i; body = $(if ($i -eq $SummaryAt) { "<!-- hyperdot:game -->`nold summary" } else { "comment $i" }) }
                    })
                    $body = ConvertTo-Json -InputObject $items -Depth 3 -Compress
                    if (-not $items.Count) { $body = '[]' }
                } elseif ($path -eq '/stop') {
                    $context.Response.Close()
                    break
                }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $context.Response.ContentType = 'application/json'
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.Close()
            }
        } finally { $listener.Stop() }
    }
}
function Invoke-Publish([int]$Port) {
    # Name and value pairs, not a hashtable: environment names are case-sensitive on Linux (NO_PROXY and no_proxy).
    $variables = @(
        @('GITHUB_API_URL', "http://127.0.0.1:$Port"), @('GITHUB_REPOSITORY', 'o/r'), @('GITHUB_TOKEN', 'test'),
        @('GITHUB_SERVER_URL', 'https://github.com'), @('GITHUB_RUN_ID', '1'), @('GITHUB_EVENT_PATH', $null), @('GITHUB_BASE_REF', $null),
        @('NO_PROXY', '127.0.0.1,localhost'), @('no_proxy', '127.0.0.1,localhost'))
    $saved = @(foreach ($pair in $variables) { , @($pair[0], [Environment]::GetEnvironmentVariable($pair[0])) })
    foreach ($pair in $variables) { [Environment]::SetEnvironmentVariable($pair[0], $pair[1]) }
    try { return @(& pwsh -NoProfile -File $tool -ResultsDir $results -Name game -ArtifactName results -PullRequest 7 2>&1) -join ' ' }
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
} finally {
    Remove-Item -Recurse -Force $results -ErrorAction SilentlyContinue
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'Publish-PrComment reads every page of comments: it updates a summary past the first 100 and posts one only when there is none'
exit 0
