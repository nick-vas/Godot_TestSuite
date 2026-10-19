#Requires -Version 7.2
<#
.SYNOPSIS
    Checks the agent skills in .agents/skills the way a reviewer would: structure, size, discoverability and,
    unlike a pure-text linter, that every command, flag, error code and package version a skill mentions is real.

.DESCRIPTION
    Errors fail the run (exit 1); warnings do not. -IncludeFixtures also checks tests/skill-fixtures, which are
    deliberately broken: CI runs it and requires failure, so a rule that stops firing is noticed.
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '../../..'),
    [switch]$IncludeFixtures,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$Root = (Resolve-Path -LiteralPath $Root).Path
$skillDirs = @(Get-ChildItem -LiteralPath (Join-Path $Root '.agents/skills') -Directory)
if ($IncludeFixtures) { $skillDirs += @(Get-ChildItem -LiteralPath (Join-Path $Root 'tests/skill-fixtures') -Directory) }
$skillNames = @($skillDirs | ForEach-Object Name)
$maxBytes = 16KB; $warnBytes = 15.5KB

# --- Ground truth the skills are checked against ---------------------------------------------------------
$entry = Join-Path $Root 'ci/godot/godot-ci.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($entry, [ref]$null, [ref]$null)
$params = @{}
foreach ($p in $ast.ParamBlock.Parameters) {
    $set = $p.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' } | Select-Object -First 1
    $params[$p.Name.VariablePath.UserPath] = $set ? @($set.PositionalArguments | ForEach-Object { $_.Value }) : $null
}
$commands = $params['Command']
$jsonDoc = Get-Content -LiteralPath (Join-Path $Root 'docs/json.md') -Raw
$knownCodes = @([regex]::Matches($jsonDoc, '`([a-z]+(?:-[a-z]+)+)`') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$csproj = Get-Content -LiteralPath (Join-Path $Root 'examples/breakout/game/Breakout.csproj') -Raw
$packages = @{}
foreach ($m in [regex]::Matches($csproj, '<PackageReference Include="(?<n>[^"]+)" Version="(?<v>[^"]+)"')) { $packages[$m.Groups['n'].Value] = $m.Groups['v'].Value }
$sdk = [regex]::Match($csproj, 'Godot\.NET\.Sdk/(?<v>[\d.]+)').Groups['v'].Value

$findings = [System.Collections.Generic.List[object]]::new()
function Add-Finding([string]$Level, [string]$Skill, [string]$Rule, [string]$Message) {
    $findings.Add([pscustomobject]@{ Level = $Level; Skill = $Skill; Rule = $Rule; Message = $Message })
}

foreach ($dir in $skillDirs) {
    $name = $dir.Name
    $file = Join-Path $dir.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $file)) { Add-Finding error $name missing-skill-file 'no SKILL.md'; continue }
    $text = Get-Content -LiteralPath $file -Raw
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)

    # Front matter
    $fm = [regex]::Match($text, '(?s)\A---\r?\n(?<fm>.*?)\r?\n---\r?\n')
    if (-not $fm.Success) { Add-Finding error $name frontmatter 'missing YAML front matter'; continue }
    $fields = @{}
    foreach ($line in $fm.Groups['fm'].Value -split "`r?`n") { if ($line -match '^(?<k>[\w-]+):\s*(?<v>.*)$') { $fields[$Matches.k] = $Matches.v.Trim() } }
    if (-not $fields['name']) { Add-Finding error $name frontmatter 'no name' }
    elseif ($fields['name'] -cne $name) { Add-Finding error $name name-mismatch "name '$($fields['name'])' does not match its folder '$name'" }
    elseif ($name -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { Add-Finding error $name name-format 'use lowercase letters, digits and hyphens' }

    # Description: when to use, nothing about how. A description that summarises the workflow gets followed
    # instead of the skill body.
    $description = $fields['description']
    if (-not $description) { Add-Finding error $name frontmatter 'no description' }
    else {
        if ($description.Length -gt 1024) { Add-Finding error $name description-length "description is $($description.Length) characters (max 1024)" }
        elseif ($description.Length -gt 500) { Add-Finding warning $name description-length "description is $($description.Length) characters; aim for 500 or fewer" }
        if ($description -notmatch '^Use when\b') { Add-Finding error $name description-trigger 'description must start with "Use when" and state a trigger' }
        if ($description -match '(?i)\b(I|my|you can)\b') { Add-Finding error $name description-person 'write the description in the third person' }
        $summary = [regex]::Match($description, '(?i)\b(then|followed by|drives|runs the|walks (you )?through|explains|teaches|by running|and reads|->)\b')
        if ($summary.Success) { Add-Finding error $name description-summarizes-workflow "description describes the process ('$($summary.Value)'); say only when to use it" }
        if (($description -split '(?<=[.!?])\s+').Count -gt 1) { Add-Finding warning $name description-sentences 'description has several sentences; one trigger sentence is easier to match' }
    }

    # Size budget
    if ($bytes -ge $maxBytes) { Add-Finding error $name size "SKILL.md is $bytes bytes (limit $maxBytes); move detail to a reference file" }
    elseif ($bytes -ge $warnBytes) { Add-Finding warning $name size "SKILL.md is $bytes bytes, close to the $maxBytes limit" }

    # Cross-references to other skills
    foreach ($m in [regex]::Matches($text, '`(godot-[a-z0-9-]+)`')) {
        $ref = $m.Groups[1].Value
        if ($ref -ne $name -and $ref -notin $skillNames -and -not $ref.StartsWith('godot-ci')) { Add-Finding error $name cross-reference "refers to skill '$ref', which does not exist" }
    }

    # Every godot-ci.ps1 invocation must use a real command, real parameters and real values.
    $code = (@([regex]::Matches($text, '(?s)```.*?```') | ForEach-Object Value) + @([regex]::Matches($text, '`[^`\r\n]+`') | ForEach-Object Value)) -join "`n"
    foreach ($m in [regex]::Matches($code, '(?m)godot-ci\.ps1\s+(?<args>[^\r\n#`]*)')) {
        $argv = $m.Groups['args'].Value
        $first = [regex]::Match($argv, '^(?<c>[a-z]+)\b').Groups['c'].Value
        if ($first -and $first -notin $commands) { Add-Finding error $name unknown-command "godot-ci.ps1 has no command '$first' (has: $($commands -join ', '))" }
        foreach ($p in [regex]::Matches($argv, '(?<![\w-])-(?<p>[A-Za-z]+)\b')) {
            if (-not $params.ContainsKey($p.Groups['p'].Value)) { Add-Finding error $name unknown-parameter "godot-ci.ps1 has no parameter -$($p.Groups['p'].Value)" }
        }
        foreach ($set in 'Do', 'Runners', 'Column') {
            $v = [regex]::Match($argv, "-$set\s+(?<v>[A-Za-z0-9,|]+)").Groups['v'].Value
            if ($v -and $params[$set] -and $v -notmatch '[|<]') {
                foreach ($one in $v -split ',') { if ($one -notin $params[$set] -and $one -ne 'none') { Add-Finding error $name invalid-value "-$set $one is not one of: $($params[$set] -join ', ')" } }
            }
        }
    }

    # Error codes named in a table's first column must be documented in docs/json.md.
    foreach ($m in [regex]::Matches($text, '(?m)^\|\s*((?:`[a-z]+(?:-[a-z]+)+`(?:\s*/\s*)?)+)\s*\|')) {
        foreach ($c in [regex]::Matches($m.Groups[1].Value, '`([a-z-]+)`')) {
            $code = $c.Groups[1].Value
            if ($code -notin $knownCodes -and $code -notin $skillNames) { Add-Finding error $name unknown-error-code "error code '$code' is not in docs/json.md" }
        }
    }

    # Versions quoted in a skill must match the example project that CI actually runs.
    foreach ($m in [regex]::Matches($text, '<PackageReference Include="(?<n>[^"]+)" Version="(?<v>[^"]+)"')) {
        $n = $m.Groups['n'].Value
        if ($packages.ContainsKey($n) -and $packages[$n] -ne $m.Groups['v'].Value) {
            Add-Finding error $name version-drift "$n is $($m.Groups['v'].Value) here but $($packages[$n]) in examples/breakout"
        }
    }
    $sdkMention = [regex]::Match($text, 'Godot\.NET\.Sdk/(?<v>[\d.]+)')
    if ($sdkMention.Success -and $sdk -and $sdkMention.Groups['v'].Value -ne $sdk) {
        Add-Finding error $name version-drift "Godot.NET.Sdk/$($sdkMention.Groups['v'].Value) here but $sdk in examples/breakout"
    }
}

$errors = @($findings | Where-Object Level -eq 'error')
$warnings = @($findings | Where-Object Level -eq 'warning')
if ($Json) {
    [Console]::Out.WriteLine(([ordered]@{ schema = 'godot-skills/1'; ok = ($errors.Count -eq 0); skills = $skillNames.Count
        errors = $errors.Count; warnings = $warnings.Count; findings = @($findings | ForEach-Object { [ordered]@{ level = $_.Level; skill = $_.Skill; rule = $_.Rule; message = $_.Message } }) } | ConvertTo-Json -Depth 5))
} else {
    foreach ($f in $findings) {
        Write-Host ('{0,-7} {1,-24} {2,-26} {3}' -f $f.Level, $f.Skill, $f.Rule, $f.Message) -ForegroundColor ($f.Level -eq 'error' ? 'Red' : 'Yellow')
    }
    Write-Host "$($skillNames.Count) skill(s): $($errors.Count) error(s), $($warnings.Count) warning(s)"
}
exit ($errors.Count -gt 0 ? 1 : 0)
