#!/usr/bin/env pwsh
# Self-test of doctor's add-on checks (lib/Addons.ps1), on a project made in a temporary folder: which GDExtension
# library each export preset's builds get, by Godot's own rule (measured on 4.7.2: every tag of a key must be a feature,
# the most tags wins), relative paths and multi-line dependencies, editor-only and excluded extensions, Godot version
# limits; and add-on mistakes: the Godot Jolt extension on 4.4+, an add-on's autoload the game uses but project.godot
# lacks, test add-ons shipped, and Debug Draw 3D forced on. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Detect', 'Doctor', 'Addons') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function New-Preset([string]$Name, [string]$Platform, [string]$Custom = '', [string]$Exclude = '', [hashtable]$Options = @{}) {
    [pscustomobject]@{ Name = $Name; Platform = $Platform; CustomFeatures = $Custom; ExcludeFilter = $Exclude; Options = $Options }
}
function Get-Messages($Problems) { @($Problems | ForEach-Object { "$($_.Status) $($_.Message)" }) -join "`n" }

# Feature sets as Godot 4.7.2 printed them.
$web = @(Get-ExportFeatureSets (New-Preset 'Web' 'Web'))
Assert-True ($web.Count -eq 2 -and $web[0].Features.Contains('nothreads') -and $web[0].Features.Contains('web_noextensions') -and $web[0].Features.Contains('template_release')) 'Web defaults to nothreads, without extensions'
$android = @(Get-ExportFeatureSets (New-Preset 'Android' 'Android' -Options @{ 'architectures/armeabi-v7a' = 'true'; 'architectures/arm64-v8a' = 'true' }))
Assert-True ($android.Count -eq 4 -and (@($android | ForEach-Object Arch | Sort-Object -Unique) -join ',') -eq 'arm32,arm64') 'Android gets one set per enabled architecture and build'
Assert-True (@(Get-ExportFeatureSets (New-Preset 'Android' 'Android')).Count -eq 2) 'Android defaults to arm64 only'
$mac = @(Get-ExportFeatureSets (New-Preset 'Mac' 'macOS'))
Assert-True ($mac.Count -eq 4 -and $mac[0].Features.Contains('universal')) 'a macOS universal export looks up x86_64 and arm64'

$dir = Join-Path ([System.IO.Path]::GetTempPath()) "addons-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    foreach ($d in 'addons/native/libs/web', 'addons/native/libs/linux', 'addons/vcs', 'addons/dm', 'addons/gut', 'addons/debug_draw_3d', 'addons/old', 'addons/new', 'scripts') {
        New-Item -ItemType Directory -Force (Join-Path $dir $d) | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Addons`"`n"
    foreach ($f in 'libs/linux/native.release.so', 'libs/linux/native.debug.so', 'libs/linux/native.tagged.so', 'libs/web/native.release.wasm', 'libs/linux/dep_a.so') {
        Set-Content -LiteralPath (Join-Path $dir "addons/native/$f") 'fake'
    }
    # Relative paths, a key that only a custom feature picks, release-only Web keys, a multi-line dependency with one file missing.
    Set-Content -LiteralPath (Join-Path $dir 'addons/native/native.gdextension') @'
[configuration]

entry_symbol = "native_init"
compatibility_minimum = 4.5

[libraries]

linux.debug.x86_64 = "libs/linux/native.debug.so"
linux.release.x86_64 = "libs/linux/native.release.so"
linux.template_release.x86_64.demo = "libs/linux/native.tagged.so"
linux.release.arm64 = "libs/linux/native.arm64.so"
web.release.wasm32.nothreads = "libs/web/native.release.wasm"
android.release.arm64 = "res://addons/native/libs/android/native.arm64.so"

[dependencies]

linux.release.x86_64 = {
"libs/linux/dep_a.so": "",
"libs/linux/dep_b.so": ""
}
'@
    $linux = New-Preset 'Linux' 'Linux'
    $problems = @(Get-GdextensionProblems $dir @($linux) '4.7.2')
    $text = Get-Messages $problems
    Assert-True ($text -notmatch 'native\.release\.so|native\.debug\.so|dep_a') "relative paths that exist are found: $text"
    Assert-True ($text -match 'FAIL .*\[dependencies\] linux\.release\.x86_64 names libs/linux/dep_b\.so') 'a missing file in a multi-line dependency fails'
    $tagged = @(Get-GdextensionProblems $dir @(New-Preset 'Demo' 'Linux' -Custom 'demo') '4.7.2')
    Assert-True (@($tagged | Where-Object Message -match 'native\.tagged|has no library').Count -eq 0) "a custom feature picks the key with more tags: $(Get-Messages $tagged)"
    $arm = @(Get-GdextensionProblems $dir @(New-Preset 'LinuxArm' 'Linux' -Options @{ 'binary_format/architecture' = 'arm64' }) '4.7.2')
    Assert-True ((Get-Messages $arm) -match "FAIL .*linux\.release\.arm64 = libs/linux/native\.arm64\.so, which does not exist" -and (Get-Messages $arm) -match "WARN .*no library for export preset 'LinuxArm' \(debug\)") "arm64: a missing release file fails, no debug key warns: $(Get-Messages $arm)"
    $webProblems = @(Get-GdextensionProblems $dir @(New-Preset 'Web' 'Web') '4.7.2')
    Assert-True ($webProblems.Count -eq 1 -and $webProblems[0].Status -eq 'WARN' -and $webProblems[0].Message -match '\(debug\)') "release-only Web keys: the debug build warns, release passes: $(Get-Messages $webProblems)"
    $threads = @(Get-GdextensionProblems $dir @(New-Preset 'WebThreads' 'Web' -Options @{ 'variant/thread_support' = 'true' }) '4.7.2')
    Assert-True (@($threads | Where-Object { $_.Status -eq 'FAIL' -and $_.Message -match '\(release\)' }).Count -eq 1) 'a threads Web export does not fit a nothreads key and fails'
    $two = @(Get-GdextensionProblems $dir @(New-Preset 'Android' 'Android' -Options @{ 'architectures/armeabi-v7a' = 'true' }) '4.7.2')
    Assert-True ((Get-Messages $two) -match "FAIL .*no library for export preset 'Android' \(release, arm32\)" -and (Get-Messages $two) -match "FAIL .*android\.release\.arm64 = res://") "Android names the architecture with no key: $(Get-Messages $two)"
    $excluded = @(Get-GdextensionProblems $dir @(New-Preset 'Excl' 'Web' -Exclude 'addons/native/*') '4.7.2')
    Assert-True ($excluded.Count -eq 0) 'a preset that excludes the add-on is not checked'
    Assert-True (@(Get-GdextensionProblems $dir @($linux) '4.4').Where({ $_.Message -match 'needs Godot 4\.5 or later' }).Count -eq 1) 'an unquoted compatibility_minimum above the engine fails'

    # Editor-only, and version limits.
    Set-Content -LiteralPath (Join-Path $dir 'addons/vcs/vcs.gdextension') "[configuration]`n`nentry_symbol = `"vcs_init`"`ncompatibility_minimum = `"4.3`"`n`n[libraries]`n`nlinux.editor.x86_64 = `"lib/vcs.so`"`n"
    Set-Content -LiteralPath (Join-Path $dir 'addons/old/old.gdextension') "[configuration]`n`nentry_symbol = `"old_init`"`ncompatibility_minimum = `"4.3`"`ncompatibility_maximum = `"4.6`"`n"
    Set-Content -LiteralPath (Join-Path $dir 'addons/new/new.gdextension') "[configuration]`n`nentry_symbol = `"new_init`"`ncompatibility_maximum = `"4.7`"`n"
    $moreProblems = @(Get-GdextensionProblems $dir @($linux) '4.7.2')
    $more = Get-Messages $moreProblems
    $editorOnly = @($moreProblems | Where-Object Message -match 'vcs\.gdextension is an editor-only extension')
    Assert-True ($editorOnly.Count -eq 1 -and $editorOnly[0].Status -eq 'WARN' -and $editorOnly[0].Fix -match 'addons/vcs/\*') 'an editor-only extension in an export warns, naming the folder to exclude'
    Assert-True ($more -match 'FAIL res://addons/old/old\.gdextension supports Godot up to 4\.6') 'a maximum below the engine fails'
    Assert-True ($more -notmatch 'new\.gdextension supports' -and $more -match 'FAIL res://addons/new/new\.gdextension has no compatibility_minimum') 'a maximum of 4.7 includes 4.7.2; a missing minimum fails'
    $vcsExcluded = Get-Messages @(Get-GdextensionProblems $dir @(New-Preset 'L' 'Linux' -Exclude 'addons/vcs/*') '4.7.2')
    Assert-True ($vcsExcluded -notmatch 'editor-only') 'an excluded editor-only extension is fine'

    # Add-on problems.
    Set-Content -LiteralPath (Join-Path $dir 'addons/dm/plugin.gd') "@tool`nextends EditorPlugin`nconst SINGLETON_NAME := `"DialogueManager`"`nfunc _enable_plugin():`n`tadd_autoload_singleton(SINGLETON_NAME, `"res://addons/dm/dialogue_manager.gd`")`n`tadd_autoload_singleton(`"DialogueUnused`", `"res://addons/dm/x.gd`")`n"
    Set-Content -LiteralPath (Join-Path $dir 'scripts/npc.gd') "extends Node`nfunc talk():`n`tDialogueManager.show_dialogue_balloon(load(`"res://intro.dialogue`"))`n"
    $godot = "config_version=5`n`n[physics]`n`n3d/physics_engine=`"Jolt Physics (Extension)`"`n"
    $addon = Get-Messages @(Get-AddonProblems $dir $godot @(New-Preset 'Release' 'Linux' -Custom 'forced_dd3d'; New-Preset 'Clean' 'Linux' -Exclude 'test/*, addons/gut/*') '4.7.2')
    Assert-True ($addon -match 'WARN The project uses the Godot Jolt extension') 'the Godot Jolt extension on 4.7 warns'
    Assert-True ($addon -match 'WARN The game uses DialogueManager, an autoload that res://addons/dm/plugin\.gd registers') 'an add-on autoload the game uses but project.godot lacks warns (through a constant)'
    Assert-True ($addon -notmatch 'DialogueUnused') 'an autoload the game does not use is not reported'
    Assert-True ($addon -match "WARN Export preset 'Release' ships addons/gut" -and $addon -notmatch "'Clean' ships") 'GUT in an export warns unless excluded'
    Assert-True ($addon -match "WARN Export preset 'Release' sets forced_dd3d" -and $addon -notmatch "'Clean' sets forced_dd3d") 'forced_dd3d in a preset warns'
    $clean = Get-Messages @(Get-AddonProblems $dir "config_version=5`n`n[autoload]`n`nDialogueManager=`"*res://addons/dm/dialogue_manager.gd`"`n`n[physics]`n`n3d/physics_engine=`"Jolt Physics`"`n" @() '4.7.2')
    Assert-True ($clean -notmatch 'Jolt|DialogueManager') "the built-in Jolt and a registered autoload pass: $clean"
    Assert-True ((Get-Messages @(Get-AddonProblems $dir $godot @() '4.3')) -notmatch 'Jolt') 'the Jolt extension on 4.3 is fine'

    # End to end: doctor reports them and fails on the release library.
    Set-Content -LiteralPath (Join-Path $dir 'export_presets.cfg') "[preset.0]`n`nname=`"Web`"`nplatform=`"Web`"`nrunnable=true`ncustom_features=`"`"`nexport_filter=`"all_resources`"`ninclude_filter=`"`"`nexclude_filter=`"addons/gut/*`"`nexport_path=`"build/web/index.html`"`n`n[preset.0.options]`n`nvariant/thread_support=true`n"
    & git -C $dir init -q
    $json = & pwsh -NoProfile -File (Join-Path $root 'ci/godot/hyperdot.ps1') doctor -Project $dir -Json 2>$null | Out-String | ConvertFrom-Json
    $messages = @($json.checks | ForEach-Object { "$($_.status) $($_.message)" }) -join "`n"
    Assert-True ($json.ok -eq $false -and $messages -match "FAIL res://addons/native/native\.gdextension has no library for export preset 'Web' \(release\)") "doctor fails on a release build with no library: $(($messages -split "`n" | Select-String 'gdextension|addons') -join ' | ')"
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

# Add-ons with a known status (ci/godot/addons-status.json), in a project of their own: found by folder in any letter
# case, or renamed by their .gdextension's file name and entry_symbol; a Godot range only warns outside it.
$known = Join-Path ([System.IO.Path]::GetTempPath()) "addons-known-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    foreach ($d in 'addons/perfbullets', 'addons/godot-steam-audio', 'addons/py', 'addons/other') { New-Item -ItemType Directory -Force (Join-Path $known $d) | Out-Null }
    Set-Content -LiteralPath (Join-Path $known 'addons/py/python.gdextension') "[configuration]`n`nentry_symbol = `"initialize_pythonscript`"`ncompatibility_minimum = `"4.7.0`"`n"
    # The same file name with another entry_symbol is someone else's extension.
    Set-Content -LiteralPath (Join-Path $known 'addons/other/python.gdextension') "[configuration]`n`nentry_symbol = `"other_init`"`ncompatibility_minimum = `"4.5`"`n"
    $statusList = Get-Content -LiteralPath (Join-Path $root 'ci/godot/addons-status.json') -Raw | ConvertFrom-Json
    Assert-True (@($statusList.addons | Where-Object { -not ($_.id -and $_.repo -and $_.folders -and $_.gdextension -and $_.entrySymbol -and $_.entrySymbolSource -and $_.why -and $_.fix -and $_.head -match '^[0-9a-f]{40}$' -and $_.confirmed) }).Count -eq 0) 'every status entry names its repository, folders, file, entry_symbol, source, reason, fix, commit and how it was confirmed'
    $knownProblems = @(Get-AddonProblems $known "config_version=5`n" @() '4.7.2')
    $knownText = Get-Messages $knownProblems
    Assert-True ($knownText -match 'WARN res://addons/perfbullets is Godot-PerfBullets \(Moonzel/Godot-PerfBullets\), not made for this Godot: .*works with Godot 4\.1 and 4\.2.* It supports Godot up to 4\.2, and the project uses 4\.7\.2') "PerfBullets is found by its folder in another case, outside its Godot range: $knownText"
    Assert-True ($knownText -match 'WARN res://addons/godot-steam-audio is godot-steam-audio \(stechyo/godot-steam-audio\), archived') 'godot-steam-audio warns as archived'
    Assert-True ($knownText -match 'WARN res://addons/py/python\.gdextension is py4godot' -and @($knownProblems | Where-Object Message -match 'addons/other').Count -eq 0) 'a renamed py4godot is found by file name and entry_symbol, another extension with its file name is not'
    Assert-True ((Get-Messages @(Get-AddonProblems $known "config_version=5`n" @() '4.2.2')) -notmatch 'PerfBullets') 'PerfBullets on Godot 4.2 is within its range'
    # Godot Jolt: the folder alone warns; with the extension's physics engine set, the setting's warning (which names the
    # folder) is the only Jolt line.
    New-Item -ItemType Directory -Force (Join-Path $known 'addons/godot-jolt') | Out-Null
    $joltFolder = Get-Messages @(Get-AddonProblems $known "config_version=5`n" @() '4.7.2')
    Assert-True ($joltFolder -match 'WARN res://addons/godot-jolt is Godot Jolt \(godot-jolt/godot-jolt\), superseded by the engine') "addons/godot-jolt on 4.7 warns from the list: $joltFolder"
    $joltBoth = @(Get-AddonProblems $known "config_version=5`n`n[physics]`n`n3d/physics_engine=`"Jolt Physics (Extension)`"`n" @() '4.7.2')
    Assert-True (@($joltBoth | Where-Object Message -match 'Jolt').Count -eq 1) "with the extension's physics engine set, one Jolt line: $(Get-Messages $joltBoth)"
    Assert-True ((Get-Messages @(Get-AddonProblems $known "config_version=5`n" @() '4.6.1')) -notmatch 'Godot Jolt') 'Godot Jolt on 4.6 is within its range'

    # The canary's refresh (Update-AddonStatus.ps1) on a copy of the list, with made-up repositories (-Source).
    $copyRoot = Join-Path $known 'kit'
    New-Item -ItemType Directory -Force (Join-Path $copyRoot 'ci/godot') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'ci/godot/addons-status.json') -Destination (Join-Path $copyRoot 'ci/godot/addons-status.json')
    $source = @{}
    foreach ($a in $statusList.addons) { $source[$a.repo] = @{ head = $a.head; archived = $a.archived; files = @{ $a.entrySymbolSource = "entry_symbol = `"$($a.entrySymbol)`"" } } }
    $source['godot-jolt/godot-jolt'].archived = $true
    $source['stechyo/godot-steam-audio'].archived = $false
    $source['Moonzel/Godot-PerfBullets'].head = 'c' * 40
    $source['niklas2902/py4godot'].files = @{}
    $sourceFile = Join-Path $known 'source.json'
    $source | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sourceFile
    $tool = Join-Path $root 'ci/godot/tools/Update-AddonStatus.ps1'
    $r = & pwsh -NoProfile -File $tool -Root $copyRoot -Source $sourceFile -Apply -Json | Out-String | ConvertFrom-Json
    $updates = @($r.updates | ForEach-Object { "$($_.id).$($_.field)" } | Sort-Object)
    Assert-True (($updates -join ',') -eq 'godot-jolt.archived,godot-perfbullets.head,godot-steam-audio.archived') "head and archived changes are found: $($updates -join ',')"
    $reviewIds = @($r.review | ForEach-Object id | Sort-Object)
    Assert-True (($reviewIds -join ',') -eq 'godot-perfbullets,godot-steam-audio,py4godot') "a new commit on a warned add-on, an unarchived one and a missing entry_symbol file need a person: $($reviewIds -join ',')"
    $written = Get-Content -LiteralPath (Join-Path $copyRoot 'ci/godot/addons-status.json') -Raw | ConvertFrom-Json
    $perf = @($written.addons | Where-Object id -eq 'godot-perfbullets')[0]
    $jolt = @($written.addons | Where-Object id -eq 'godot-jolt')[0]
    Assert-True ($perf.head -eq ('c' * 40) -and $jolt.archived -eq $true -and $perf.status -eq 'unsupported' -and @($r.changed) -contains 'ci/godot/addons-status.json') '-Apply writes head and archived, and leaves the status to a person'
    $again = & pwsh -NoProfile -File $tool -Root $copyRoot -Source $sourceFile -Apply -Json | Out-String | ConvertFrom-Json
    Assert-True (@($again.updates).Count -eq 0 -and @($again.changed).Count -eq 0 -and (@($again.review | ForEach-Object id) -join ',') -eq 'py4godot') "a second run changes nothing; only the missing file is still reported: $(@($again.review | ForEach-Object id) -join ',')"
} finally {
    Remove-Item -LiteralPath $known -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) add-on check(s) failed" }
Write-Host 'add-on self-test passed'
# The doctor run above failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
