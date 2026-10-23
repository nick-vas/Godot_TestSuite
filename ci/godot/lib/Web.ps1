# Web exports: their download size, and `export -Run` in real browsers (tools/web-smoke.mjs through Playwright).
# Godot 4.7.2's engine alone is about 38 MB of WebAssembly, 9.7 MB gzipped; what a game adds is mostly its .pck.

$script:PlaywrightVersion = '1.56.1'

# Raw and gzip sizes of a web export folder (gzip is what GitHub Pages and most hosts send; itch.io sends files as they are).
function Get-WebBuildSize([string]$Dir) {
    $raw = 0L; $gzip = 0L; $files = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $Dir -File)) {
        $files++
        $raw += $file.Length
        $source = [System.IO.File]::OpenRead($file.FullName)
        $counter = [System.IO.MemoryStream]::new()
        try {
            $zip = [System.IO.Compression.GZipStream]::new($counter, [System.IO.Compression.CompressionLevel]::Optimal, $true)
            $source.CopyTo($zip)
            $zip.Dispose()
            $gzip += $counter.Length
        } finally { $source.Dispose(); $counter.Dispose() }
    }
    return [ordered]@{ files = $files; rawMb = [math]::Round($raw / 1MB, 2); gzipMb = [math]::Round($gzip / 1MB, 2) }
}

# The folder that holds the playwright package: HYPEDOT_PLAYWRIGHT, the global npm folder, or the kit's own copy
# (installed on first use, without browsers; `npx playwright install <browser>` adds those).
function Find-Playwright {
    if ($env:HYPEDOT_PLAYWRIGHT) {
        if (Test-Path -LiteralPath (Join-Path $env:HYPEDOT_PLAYWRIGHT 'playwright')) { return $env:HYPEDOT_PLAYWRIGHT }
        Stop-GodotCi "HYPEDOT_PLAYWRIGHT is set, but $env:HYPEDOT_PLAYWRIGHT has no playwright folder" 'no-browser'
    }
    if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Stop-GodotCi 'export -Run of a Web preset needs Node.js (node and npm on the PATH)' 'no-browser'
    }
    $global = (& npm root -g 2>$null | Select-Object -First 1) -as [string]
    if ($global -and (Test-Path -LiteralPath (Join-Path $global 'playwright'))) { return $global }
    $own = Join-Path (Get-ToolsDir) 'node'
    $modules = Join-Path $own 'node_modules'
    if (-not (Test-Path -LiteralPath (Join-Path $modules 'playwright'))) {
        Write-CiLog "Installing playwright $script:PlaywrightVersion into $own (no browsers)"
        New-Item -ItemType Directory -Force $own | Out-Null
        $env:PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = '1'
        $log = [System.IO.Path]::GetTempFileName()
        $code = Invoke-Logged npm @('install', '--prefix', $own, '--no-audit', '--no-fund', "playwright@$script:PlaywrightVersion") $log
        if ($code -ne 0) { Stop-GodotCi "npm could not install playwright (exit $code); see $log" 'no-browser' }
    }
    return $modules
}

# Opens a web export in each browser. Returns one result per browser (see tools/web-smoke.mjs).
function Invoke-WebSmoke([string]$Dir, [string[]]$Browsers, [bool]$CrossOriginIsolation, [string]$ScreenshotPrefix) {
    $modules = Find-Playwright
    $tool = (Join-Path $PSScriptRoot '../tools/web-smoke.mjs' | Resolve-Path).Path
    $previous = $env:NODE_PATH
    $env:NODE_PATH = $modules
    try {
        return , @(foreach ($browser in $Browsers) {
            $log = [System.IO.Path]::GetTempFileName()
            $smokeArgs = @($tool, $Dir, "--browser=$browser", "--screenshot=$ScreenshotPrefix-$browser.png") + $(if ($CrossOriginIsolation) { @('--coi') })
            $code = Invoke-Logged node $smokeArgs $log
            $line = @(Get-Content -LiteralPath $log | Where-Object { $_ -like '@@web *' } | Select-Object -Last 1)
            $result = if ($line.Count) { $line[0].Substring(6) | ConvertFrom-Json -AsHashtable }
                else { [ordered]@{ browser = $browser; ok = $false; errors = @("web-smoke.mjs exited with $code and printed no result") } }
            if ($code -eq 2 -and "$($result.errors)" -match 'Executable doesn''t exist|could not start') {
                $result.errors += "Install the browser: npx playwright install --with-deps $browser"
            }
            $result
        })
    } finally { $env:NODE_PATH = $previous }
}
