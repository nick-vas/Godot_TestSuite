#Requires -Version 7.2
<#
.SYNOPSIS
    Re-reads each add-on in ci/godot/addons-status.json from its repository, and with -Apply writes what moved: its newest
    commit (head) and whether GitHub has archived it. Prints one JSON document (schema hyperdot-addons-status-check/1).

.DESCRIPTION
    head comes from git ls-remote (no API, no token). archived comes from the GitHub API (GITHUB_TOKEN is used when set);
    when the API cannot be read, archived is left as it is and a note says why. The entry_symbol doctor matches is looked up
    again in the file the entry names (entrySymbolSource), at the repository's newest commit, through raw.githubusercontent.com.
    What a person must judge is listed under review, never applied: a new commit on an add-on doctor warns about because of
    its Godot range or as a prototype (it may now be fit for use), an archived one that is no longer archived, and an
    entry_symbol or file that is gone (doctor would stop recognising a renamed folder). The weekly canary runs this after
    the version updates: changes go into its pull request, review items into issues.
    -Source replaces every lookup with a JSON file, for tests: { "<owner/repo>": { "head": "<sha>", "archived": true|false|null,
    "files": { "<path>": "<text>" | null } } }.
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '../../..'),
    [switch]$Apply,
    [string]$Source,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$Root = (Resolve-Path -LiteralPath $Root).Path
$relative = 'ci/godot/addons-status.json'
$path = Join-Path $Root $relative
# Objects, not hashtables: they keep the file's order, so a rewrite changes only the values that moved.
$doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$fromFile = if ($Source) { Get-Content -LiteralPath $Source -Raw | ConvertFrom-Json -AsHashtable } else { $null }
$notes = [System.Collections.Generic.List[string]]::new()
$updates = [System.Collections.Generic.List[object]]::new()
$review = [System.Collections.Generic.List[object]]::new()

function Get-RepoHead([string]$Repo) {
    if ($fromFile) { return $fromFile[$Repo]['head'] }
    $line = @(& git ls-remote "https://github.com/$Repo" HEAD 2>$null) | Select-Object -First 1
    if ($LASTEXITCODE -or "$line" -notmatch '^(?<c>[0-9a-f]{40})\s') { throw "git ls-remote of $Repo failed ($LASTEXITCODE)" }
    return $Matches.c
}
function Get-RepoArchived([string]$Repo) {
    if ($fromFile) { return $fromFile[$Repo]['archived'] }
    $headers = @{ 'User-Agent' = 'hyperdot' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    return [bool](Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo" -Headers $headers).archived
}
# The file's text at the repository's newest commit, or $null when it is gone.
function Get-RepoFile([string]$Repo, [string]$Commit, [string]$File) {
    if ($fromFile) { $files = $fromFile[$Repo]['files']; return $(if ($files -and $files.Contains($File)) { $files[$File] } else { $null }) }
    try { return (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$Repo/$Commit/$File" -Headers @{ 'User-Agent' = 'hyperdot' }).Content }
    catch {
        $status = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        if ($status -eq 404) { return $null }
        throw
    }
}
function Add-Update([string]$Id, [string]$Field, $Old, $New) { $updates.Add([ordered]@{ id = $Id; field = $Field; old = $Old; new = $New }) }

foreach ($entry in @($doc.addons)) {
    $id = $entry.id; $repo = $entry.repo
    try {
        $head = Get-RepoHead $repo
    } catch { $notes.Add("${id}: could not read $repo with git ($($_.Exception.Message)); left as it was"); continue }
    if ($head -and $head -ne $entry.head) {
        Add-Update $id 'head' $entry.head $head
        if ($entry.status -ne 'archived') {
            $review.Add([ordered]@{ id = $id; message = "$($entry.name) ($repo) has new commits since $("$($entry.head)".Substring(0, [math]::Min(7, "$($entry.head)".Length))): check whether it is still $($entry.status) (why: $($entry.why)), and update or remove its entry in $relative" })
        }
        $entry.head = $head
    }
    try {
        $archived = Get-RepoArchived $repo
        if ($null -ne $archived -and $archived -ne $entry.archived) {
            Add-Update $id 'archived' $entry.archived $archived
            if (-not $archived -and $entry.status -eq 'archived') {
                $review.Add([ordered]@{ id = $id; message = "$($entry.name) ($repo) is no longer archived: check its state and its entry in $relative" })
            }
            $entry.archived = $archived
        }
    } catch { $notes.Add("${id}: GitHub's API could not be read for archived ($($_.Exception.Message)); left as it was") }
    try {
        $text = Get-RepoFile $repo $entry.head $entry.entrySymbolSource
        if ($null -eq $text) {
            $review.Add([ordered]@{ id = $id; message = "$($entry.entrySymbolSource) is gone from $repo at $($entry.head): find where its .gdextension's entry_symbol is now, and update entrySymbol and entrySymbolSource in $relative" })
        } elseif (-not $text.Contains($entry.entrySymbol)) {
            $review.Add([ordered]@{ id = $id; message = "$($entry.entrySymbolSource) in $repo no longer names entry_symbol $($entry.entrySymbol): doctor finds a renamed copy of $($entry.name) by it; update entrySymbol in $relative" })
        }
    } catch { $notes.Add("${id}: could not read $($entry.entrySymbolSource) from $repo ($($_.Exception.Message))") }
}

$changed = @()
if ($Apply -and $updates.Count -gt 0) {
    Set-Content -LiteralPath $path -Value ($doc | ConvertTo-Json -Depth 6) -Encoding utf8
    $changed = @($relative)
}
$result = [ordered]@{ schema = 'hyperdot-addons-status-check/1'; updates = @($updates); review = @($review); notes = @($notes); changed = $changed }
if ($Json) { [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 5)) }
else {
    if ($updates.Count -eq 0) { Write-Host 'No add-on in the status list moved.' }
    foreach ($u in $updates) { Write-Host "$($u.id) $($u.field): $($u.old) -> $($u.new)" }
    foreach ($r in $review) { Write-Host "Review: $($r.message)" -ForegroundColor Yellow }
    foreach ($n in $notes) { Write-Host "Note: $n" -ForegroundColor Yellow }
}
