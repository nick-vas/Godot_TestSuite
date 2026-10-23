#Requires -Version 7.2
<#
.SYNOPSIS
Calibrates the judge (benchmark/PLAN.md, grading layer 4): how often it agrees with a person's blind verdicts on the same
pairs, and how often it agrees with itself when A and B are swapped.

.DESCRIPTION
The person judges the pairs that Invoke-SideBySide.ps1 -ReviewOut wrote, on the review page; the judge judges the same
pairs with Invoke-SideBySide.ps1. A pair's verdict is the plugin's work, the other work, or even. The judge's verdict
is the plugin's or the other's only when it chose the same work in both orders, and even otherwise; it agrees with
itself when it chose the same work both times or "even" both times.

The plan's bar for a judge: at least 80% agreement with the person and 90% with itself. Below either, the script exits 1
and the judge's results stay out of the label.

.EXAMPLE
pwsh benchmark/Get-JudgeAgreement.ps1 -Key review/review-key.json -Verdicts verdicts.json -Preferences side-by-side/preferences.json
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    # review-key.json from Invoke-SideBySide.ps1 -ReviewOut: which side of each review pair had the plugin.
    [Parameter(Mandatory)][string]$Key,
    # The person's verdicts: a JSON array of { "id": "p01", "choice": "A" | "B" | "even" }, as the review page keeps them.
    [Parameter(Mandatory)][string]$Verdicts,
    # preferences.json from Invoke-SideBySide.ps1 over the same results.
    [Parameter(Mandatory)][string]$Preferences,
    [ValidateRange(0, 1)][double]$MinAgreement = 0.8,
    [ValidateRange(0, 1)][double]$MinConsistency = 0.9,
    [switch]$Json
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$keyDoc = Get-Content -LiteralPath $Key -Raw | ConvertFrom-Json -AsHashtable
$votes = @(Get-Content -LiteralPath $Verdicts -Raw | ConvertFrom-Json -AsHashtable)
$prefs = Get-Content -LiteralPath $Preferences -Raw | ConvertFrom-Json -AsHashtable
$judged = @{}
foreach ($p in @($prefs.pairs)) { if ($p.Contains('pair')) { $judged[$p.pair] = $p } }

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($vote in $votes) {
    $id = [string]$vote.id
    if (-not $keyDoc.pairs.Contains($id)) { throw "Verdict for $id, which review-key.json does not have" }
    $entry = $keyDoc.pairs[$id]
    $choice = ([string]$vote.choice).ToLowerInvariant()
    if ($choice -notin 'a', 'b', 'even') { throw "Verdict for $id is '$($vote.choice)': A, B or even" }
    $person = if ($choice -eq 'even') { 'even' } elseif ($choice -eq $entry.pluginIs.ToLowerInvariant()) { 'plugin' } else { 'other' }
    if (-not $judged.ContainsKey($entry.pair)) { continue }
    $j = $judged[$entry.pair]
    $judge = switch ([double]$j.pluginOutcome) { 1 { 'plugin' } 0 { 'other' } default { 'even' } }
    $choices = @($j.choices)
    $consistent = $judge -ne 'even' -or ($choices.Count -eq 2 -and $choices[0] -eq 'even' -and $choices[1] -eq 'even')
    $rows.Add([ordered]@{ id = $id; pair = $entry.pair; person = $person; judge = $judge; agree = ($person -eq $judge); consistent = $consistent })
}

$compared = $rows.Count
$agreement = if ($compared) { [Math]::Round(@($rows | Where-Object { $_.agree }).Count / $compared, 4) } else { $null }
$pairsJudged = @($prefs.pairs).Count
$consistency = if ($pairsJudged) {
    $same = @($prefs.pairs | Where-Object { [double]$_.pluginOutcome -ne 0.5 -or (@($_.choices) -join ',') -eq 'even,even' }).Count
    [Math]::Round($same / $pairsJudged, 4)
} else { $null }
$passes = $compared -gt 0 -and $agreement -ge $MinAgreement -and $consistency -ge $MinConsistency
$document = [ordered]@{
    schema = 'hyperdot-judge-agreement/1'; judgeModel = $prefs.judgeModel; compared = $compared; agreement = $agreement
    consistency = $consistency; minAgreement = $MinAgreement; minConsistency = $MinConsistency; passes = $passes
    disagreements = @($rows | Where-Object { -not $_.agree } | ForEach-Object { [ordered]@{ id = $_.id; pair = $_.pair; person = $_.person; judge = $_.judge } })
}
if ($Json) { $document | ConvertTo-Json -Depth 5 } else {
    if (-not $compared) { Write-Host 'No pair has both a verdict and a judgement' }
    else {
        Write-Host ("{0}: agrees with the person on {1:P0} of {2} pair(s) (needs {3:P0}), with itself on {4:P0} of {5} (needs {6:P0}): {7}" -f
            $prefs.judgeModel, $agreement, $compared, $MinAgreement, $consistency, $pairsJudged, $MinConsistency, $(if ($passes) { 'calibrated' } else { 'not calibrated' }))
        foreach ($d in $document.disagreements) { Write-Host "  $($d.id) $($d.pair): the person chose $($d.person), the judge $($d.judge)" }
    }
}
exit $(if ($passes) { 0 } else { 1 })
