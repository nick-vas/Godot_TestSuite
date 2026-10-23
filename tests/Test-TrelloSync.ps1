#!/usr/bin/env pwsh
# Self-test of `plan -Do sync` (Trello). By default it runs against a small in-memory Trello served on localhost, so it
# needs no account and no network. -Live runs the same steps against the real Trello API with TRELLO_KEY and TRELLO_TOKEN:
# it creates a private board, syncs a plan to it, moves and archives cards the way a person would, and deletes the board
# at the end (-KeepBoard leaves it for a look). Checks: cards are created in the right lists (a list named "Done" plus an emoji
# matches done), a second sync changes nothing, a card moved on the board moves its task, an archived card is reported,
# a short link works as -Board, a missing list, missing credentials and a rejected token fail with their codes, and the
# token never appears in the kit's output or (mock) in a URL.
param([switch]$Live, [switch]$KeepBoard)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/godot-ci.ps1'
$dir = Join-Path ([IO.Path]::GetTempPath()) "trello-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# The mock keeps just enough of Trello for the sync: boards (by id or short link), lists, cards, and the OAuth header.
$mockServer = {
    param($Listener, $State)
    function New-TrelloId { [guid]::NewGuid().ToString('N').Substring(0, 24) }
    function Find-Board([string]$Key) { $State.boards.Values | Where-Object { $_.id -eq $Key -or $_.shortLink -eq $Key } | Select-Object -First 1 }
    while ($Listener.IsListening) {
        try { $context = $Listener.GetContext() } catch { break }
        $request = $context.Request
        $status = 200; $result = $null
        try {
            if ($request.RawUrl -match 'oauth_token|oauth_consumer_key|[?&](key|token)=') { $State.leaks++ }
            $auth = [string]$request.Headers['Authorization']
            $body = $null
            if ($request.HasEntityBody) {
                $reader = [IO.StreamReader]::new($request.InputStream, [Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd() | ConvertFrom-Json -AsHashtable
            }
            $path = $request.Url.AbsolutePath -replace '^/1/', ''
            $parts = @($path -split '/')
            if ($auth -notmatch 'oauth_consumer_key="[^"]+", oauth_token="(?<token>[^"]+)"' -or $Matches.token -ne $State.token) {
                $status = 401; $result = 'invalid token'
            } elseif ($request.HttpMethod -eq 'POST' -and $path -eq 'boards') {
                $board = @{ id = New-TrelloId; shortLink = [guid]::NewGuid().ToString('N').Substring(0, 8); name = $body.name }
                $State.boards[$board.id] = $board; $result = $board
            } elseif ($request.HttpMethod -eq 'DELETE' -and $parts[0] -eq 'boards') {
                $State.boards.Remove((Find-Board $parts[1]).id); $result = @{}
            } elseif ($request.HttpMethod -eq 'POST' -and $path -eq 'lists') {
                $list = @{ id = New-TrelloId; name = $body.name; idBoard = $body.idBoard; pos = [double]$body.pos; closed = $false }
                $State.lists[$list.id] = $list; $result = $list
            } elseif ($request.HttpMethod -eq 'PUT' -and $parts[0] -eq 'lists') {
                $list = $State.lists[$parts[1]]; foreach ($k in $body.Keys) { $list[$k] = $body[$k] }; $result = $list
            } elseif ($request.HttpMethod -eq 'GET' -and $parts[0] -eq 'boards' -and $parts[2] -eq 'lists') {
                $board = Find-Board $parts[1]
                if (-not $board) { $status = 404; $result = 'board not found' }
                else { $result = @($State.lists.Values | Where-Object { $_.idBoard -eq $board.id -and -not $_.closed } | Sort-Object { $_.pos } | ForEach-Object { @{ id = $_.id; name = $_.name } }) }
            } elseif ($request.HttpMethod -eq 'GET' -and $parts[0] -eq 'boards' -and $parts[2] -eq 'cards') {
                $board = Find-Board $parts[1]
                $result = @($State.cards.Values | Where-Object { $_.idBoard -eq $board.id -and -not $_.closed } | ForEach-Object { @{ id = $_.id; name = $_.name; idList = $_.idList } })
            } elseif ($request.HttpMethod -eq 'POST' -and $path -eq 'cards') {
                $list = $State.lists[$body.idList]
                if (-not $list) { $status = 400; $result = 'invalid value for idList' }
                else {
                    $card = @{ id = New-TrelloId; name = $body.name; desc = [string]$body.desc; idList = $list.id; idBoard = $list.idBoard; closed = $false }
                    $State.cards[$card.id] = $card; $result = $card
                }
            } elseif ($parts[0] -eq 'cards' -and $State.cards.ContainsKey($parts[1])) {
                $card = $State.cards[$parts[1]]
                if ($request.HttpMethod -eq 'PUT') { foreach ($k in $body.Keys) { $card[$k] = $body[$k] } }
                $result = $card
            } else { $status = 404; $result = "no route $($request.HttpMethod) $path" }
        } catch { $status = 500; $result = "$_" }
        $text = ($result -is [string]) ? $result : (ConvertTo-Json -InputObject $result -Depth 5 -Compress)
        $bytes = [Text.Encoding]::UTF8.GetBytes($text)
        $context.Response.StatusCode = $status
        $context.Response.ContentType = ($result -is [string]) ? 'text/plain' : 'application/json'
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()
    }
}

# "Done" and a party popper, written as code so the file stays ASCII for Windows PowerShell's readers.
$done = 'Done ' + [char]::ConvertFromUtf32(0x1F389)
$saved = @{ key = $env:TRELLO_KEY; token = $env:TRELLO_TOKEN; url = $env:TRELLO_API_URL }
$listener = $null; $job = $null; $board = $null
if ($Live) {
    if (-not $env:TRELLO_KEY -or -not $env:TRELLO_TOKEN) { throw 'Set TRELLO_KEY and TRELLO_TOKEN to run the live Trello test' }
    $base = 'https://api.trello.com/1'
    $env:TRELLO_API_URL = $null
} else {
    # localhost, not 127.0.0.1: on Windows HttpListener can listen on localhost without administrator rights.
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
    $listener = [Net.HttpListener]::new(); $listener.Prefixes.Add("http://localhost:$port/"); $listener.Start()
    $state = [hashtable]::Synchronized(@{ boards = @{}; lists = @{}; cards = @{}; leaks = 0; token = 'mock-token-0123456789abcdef' })
    $job = Start-ThreadJob -ScriptBlock $mockServer -ArgumentList $listener, $state
    $base = "http://localhost:$port/1"
    $env:TRELLO_API_URL = $base; $env:TRELLO_KEY = 'mock-key'; $env:TRELLO_TOKEN = $state.token
}
$token = $env:TRELLO_TOKEN

# The test's own calls stand in for a person working on the board.
function Invoke-Board([string]$Method, [string]$Resource, [hashtable]$Body) {
    $headers = @{ Authorization = "OAuth oauth_consumer_key=""$env:TRELLO_KEY"", oauth_token=""$env:TRELLO_TOKEN""" }
    $arguments = @{ Method = $Method; Uri = "$base/$Resource"; Headers = $headers }
    if ($Body) { $arguments.Body = ($Body | ConvertTo-Json -Compress); $arguments.ContentType = 'application/json; charset=utf-8' }
    return Invoke-RestMethod @arguments
}
$outputs = [System.Collections.Generic.List[string]]::new()
function Invoke-PlanJson([string[]]$Arguments) {
    $errFile = Join-Path $dir 'stderr.txt'
    $out = pwsh -NoProfile -File $ci plan -Json -Project $dir @Arguments 2>$errFile
    $outputs.Add(($out -join "`n") + (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue))
    return ($out -join "`n") | ConvertFrom-Json
}
function Get-PlanTask([string]$Id) {
    $plan = Get-Content -LiteralPath (Join-Path $dir 'plan/plan.json') -Raw | ConvertFrom-Json
    return @($plan.tasks) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

try {
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Sync Fixture""`n"
    pwsh -NoProfile -File $ci plan -Do init -Project $dir 2>$null | Out-Null

    $board = Invoke-Board POST 'boards' @{ name = "hypedot sync test $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm'))"; defaultLists = $false; prefs_permissionLevel = 'private' }
    Write-Host "Board $($board.id) ($($board.shortLink))"
    $lists = @{}
    $pos = 1
    foreach ($name in 'Backlog', 'Design', 'To Do', 'Doing', 'Testing', $done) {
        $lists[$name] = (Invoke-Board POST 'lists' @{ name = $name; idBoard = $board.id; pos = $pos++ }).id
    }

    $missing = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $missing.ok -and $missing.error.code -eq 'invalid-arguments') 'sync without -Board or a saved board fails with invalid-arguments'

    foreach ($task in @(@('Paddle movement', 'backlog'), @('Combo multiplier', 'todo'), @('Pause menu', 'doing'), @('Title screen', 'done'))) {
        Invoke-PlanJson @('-Do', 'add', '-Title', $task[0], '-Column', $task[1]) | Out-Null
    }

    $d = Invoke-PlanJson @('-Do', 'sync', '-Board', $board.shortLink)
    Assert-True ($d.ok -and $d.sync.created -eq 4 -and $d.sync.moved -eq 0) "first sync (by short link) creates 4 cards: $(if ($d.ok) { $d.sync | ConvertTo-Json -Compress } else { $d.error.message })"
    $plan = Get-Content -LiteralPath (Join-Path $dir 'plan/plan.json') -Raw | ConvertFrom-Json
    Assert-True ($plan.trello.board -eq $board.shortLink) 'sync saves the board to plan.json'
    Assert-True (@($plan.tasks | Where-Object { $_.cardId -match '^[0-9a-f]{24}$' }).Count -eq 4) 'every task gets a 24-hex card id'
    $expected = @{ t1 = 'Backlog'; t2 = 'To Do'; t3 = 'Doing'; t4 = $done }
    foreach ($id in 't1', 't2', 't3', 't4') {
        $card = Invoke-Board GET "cards/$((Get-PlanTask $id).cardId)?fields=name,desc,idList"
        Assert-True ($card.idList -eq $lists[$expected[$id]]) "$id's card is in '$($expected[$id])'"
        Assert-True ($card.desc -eq "plan task $id, phase concept") "$id's card says 'plan task $id, phase concept': '$($card.desc)'"
    }

    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.created -eq 0 -and $d.sync.moved -eq 0 -and $d.sync.board -eq $board.shortLink) 'a second sync uses the saved board and changes nothing'

    Invoke-Board PUT "cards/$((Get-PlanTask 't2').cardId)" @{ idList = $lists['Testing'] } | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.moved -eq 1 -and $d.sync.created -eq 0) 'a card moved on the board counts as moved'
    Assert-True ((Get-PlanTask 't2').column -eq 'verify') 'the moved card moves its task to verify'

    Invoke-PlanJson @('-Do', 'add', '-Title', 'Level select') | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.created -eq 1) 'a task added to the plan becomes one new card'
    $card = Invoke-Board GET "cards/$((Get-PlanTask 't5').cardId)?fields=name,idList"
    Assert-True ($card.name -eq 'Level select' -and $card.idList -eq $lists['Backlog']) 'the new card is "Level select" in Backlog'

    Invoke-Board PUT "cards/$((Get-PlanTask 't1').cardId)" @{ closed = $true } | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and @($d.sync.warnings | Where-Object { $_ -match '\bt1\b' }).Count -eq 1) "an archived card is reported, not recreated: $($d.sync.warnings -join ' | ')"
    Assert-True ($d.sync.created -eq 0 -and (Get-PlanTask 't1').column -eq 'backlog') 'the archived card leaves its task as it was'

    Invoke-Board PUT "lists/$($lists['Design'])" @{ name = 'Ideas' } | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $d.ok -and $d.error.code -eq 'trello-list-missing' -and $d.error.message -match "'design'") "a board without a Design list fails with trello-list-missing: $($d.error.message)"
    Invoke-Board PUT "lists/$($lists['Design'])" @{ name = 'Design' } | Out-Null

    $env:TRELLO_TOKEN = $null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $d.ok -and $d.error.code -eq 'trello-credentials') 'sync without TRELLO_TOKEN fails with trello-credentials'
    $env:TRELLO_TOKEN = 'f' * 64
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $d.ok -and $d.error.code -eq 'trello-error' -and $d.error.message -match '\(401\)') "a rejected token fails with trello-error (401): $($d.error.message)"
    $env:TRELLO_TOKEN = $token

    Assert-True (@($outputs | Where-Object { $_.Contains($token) -or $_.Contains('f' * 64) }).Count -eq 0) 'no output of the kit contains a token'
    if (-not $Live) { Assert-True ($state.leaks -eq 0) 'the kit never puts credentials in a URL' }
} finally {
    $env:TRELLO_TOKEN = $token
    if ($board -and -not $KeepBoard) {
        try { Invoke-Board DELETE "boards/$($board.id)" | Out-Null } catch { Write-Host "WARNING: could not delete board $($board.id): $_" -ForegroundColor Yellow }
    }
    if ($listener) { $listener.Stop(); $listener.Close() }
    if ($job) { $job | Wait-Job -Timeout 5 | Out-Null; $job | Remove-Job -Force }
    $env:TRELLO_KEY = $saved.key; $env:TRELLO_TOKEN = $saved.token; $env:TRELLO_API_URL = $saved.url
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) Trello sync check(s) failed" }
Write-Host "Trello sync self-test passed ($(if ($Live) { 'live Trello' } else { 'mock' }))"
# Some kit runs failed on purpose; GitHub's pwsh wrapper would exit with the last one's code.
exit 0
