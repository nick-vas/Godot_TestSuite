#!/usr/bin/env pwsh
# Every relative link in the documentation and skills points at a file that exists, and every #anchor at a heading in it;
# every ${CLAUDE_PLUGIN_ROOT}/... path a skill quotes exists too. GameCI's documentation fails its build on a broken link;
# here a renamed doc or a moved fixture would otherwise leave skills pointing agents at nothing. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

# GitHub's anchor for a heading: lower case, punctuation other than '-' and '_' removed, spaces to '-'.
function ConvertTo-Anchor([string]$Heading) {
    $text = ($Heading -replace '`', '' -replace '\[([^\]]*)\]\([^)]*\)', '$1').Trim().ToLowerInvariant()
    return ($text -replace '[^\p{L}\p{Nd}\s_-]', '' -replace '\s', '-')
}

$anchors = @{}
function Get-Anchors([string]$File) {
    if (-not $anchors.ContainsKey($File)) {
        $set = [System.Collections.Generic.HashSet[string]]::new()
        $inFence = $false
        foreach ($line in [System.IO.File]::ReadAllLines($File)) {
            if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
            if (-not $inFence -and $line -match '^#{1,6}\s+(.+?)\s*#*\s*$') {
                $base = ConvertTo-Anchor $Matches[1]
                $anchor = $base; $n = 1
                while (-not $set.Add($anchor)) { $anchor = "$base-$n"; $n++ }
            }
        }
        $anchors[$File] = $set
    }
    return $anchors[$File]
}

$docs = @(Get-ChildItem -LiteralPath $root -File -Filter '*.md') + @(Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Recurse -File -Filter '*.md') +
    @(Get-ChildItem -LiteralPath (Join-Path $root '.agents/skills') -Recurse -File -Filter '*.md') + @(Get-ChildItem -LiteralPath (Join-Path $root 'agents') -File -Filter '*.md' -ErrorAction SilentlyContinue)
$checked = 0
foreach ($doc in $docs) {
    $where = [System.IO.Path]::GetRelativePath($root, $doc.FullName) -replace '\\', '/'
    $text = [System.IO.File]::ReadAllText($doc.FullName)
    $prose = [regex]::Replace($text, '(?ms)^\s*```.*?^\s*```', '')   # links in code blocks are examples
    foreach ($m in [regex]::Matches($prose, '\]\(([^)\s]+)\)')) {
        $target = $m.Groups[1].Value
        if ($target -match '^(https?|mailto):' -or $target -match '^<') { continue }
        $checked++
        $path, $anchor = $target -split '#', 2
        $file = if ($path) { [System.IO.Path]::GetFullPath((Join-Path $doc.DirectoryName ([uri]::UnescapeDataString($path)))) } else { $doc.FullName }
        if (-not (Test-Path -LiteralPath $file)) { $failures.Add("${where}: link to $target, which does not exist"); continue }
        if ($anchor -and $file -like '*.md' -and -not (Get-Anchors $file).Contains($anchor.ToLowerInvariant())) {
            $failures.Add("${where}: link to $target, which has no heading #$anchor")
        }
    }
    foreach ($m in [regex]::Matches($text, '\$\{CLAUDE_PLUGIN_ROOT\}/([A-Za-z0-9_./-]+)')) {
        $checked++
        $path = $m.Groups[1].Value.TrimEnd('.', '/')
        if (-not (Test-Path -LiteralPath (Join-Path $root $path))) { $failures.Add("${where}: `${CLAUDE_PLUGIN_ROOT}/$path does not exist") }
    }
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "$checked links and quoted paths in $($docs.Count) documents and skills all lead somewhere"
exit 0
