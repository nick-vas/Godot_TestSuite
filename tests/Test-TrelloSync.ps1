#!/usr/bin/env pwsh
# Self-test of `plan -Do sync` (Trello). By default it runs against a small in-memory Trello served on localhost, so it
# needs no account and no network. -Live runs the same steps against the real Trello API with TRELLO_KEY and TRELLO_TOKEN:
# it creates a private board, syncs a plan to it, moves and archives cards the way a person would, and deletes the board
# at the end (-KeepBoard leaves it for a look). Checks: cards are created in the right lists (a list named "Done" plus an emoji
# matches done), a second sync changes nothing, a card moved on the board moves its task, a task moved in the plan moves
# its card, an archived card is reported, a short link works as -Board, a custom trello.lists mapping survives sync and
# link, a failed call keeps the ids of the cards made before it (mock), a task in an unknown column is refused before any
# call, a missing list (also on a board with none), missing credentials, a rejected token and an unreachable API fail
# with their codes, and the token never appears in the kit's output or (mock) in a URL. Board list names ("To Do",
# "testing") work as columns in move, add and link; a card a person adds becomes a task; a removed task's card is
# archived by the next sync and its id is not given again; a card the kit made for a task no one links is reported;
# the Trello connector's card and board ARIs (and a board URL) are stored as plain ids, also when an older plan has one.
param([switch]$Live, [switch]$KeepBoard)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
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
                $result = @($State.cards.Values | Where-Object { $_.idBoard -eq $board.id -and -not $_.closed } | ForEach-Object { @{ id = $_.id; name = $_.name; idList = $_.idList; desc = $_.desc } })
            } elseif ($request.HttpMethod -eq 'POST' -and $path -eq 'cards') {
                $list = $State.lists[$body.idList]
                if (-not $list) { $status = 400; $result = 'invalid value for idList' }
                elseif ("$($body.name)".StartsWith('Rate limited')) { $status = 429; $result = 'API_TOO_MANY_CARDS_REQUESTS' }
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
$listener = $null; $job = $null; $board = $null; $emptyBoard = $null
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

    $board = Invoke-Board POST 'boards' @{ name = "hyperdot sync test $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm'))"; defaultLists = $false; prefs_permissionLevel = 'private' }
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
    Assert-True ((Get-PlanTask 't2').column -eq 'verify' -and (Get-PlanTask 't2').boardColumn -eq 'verify') 'the moved card moves its task to verify, and its boardColumn with it'

    Invoke-PlanJson @('-Do', 'add', '-Title', 'Level select') | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.created -eq 1) 'a task added to the plan becomes one new card'
    $card = Invoke-Board GET "cards/$((Get-PlanTask 't5').cardId)?fields=name,idList"
    Assert-True ($card.name -eq 'Level select' -and $card.idList -eq $lists['Backlog']) 'the new card is "Level select" in Backlog'

    # A task moved in the plan since the last sync moves its card; the board's earlier move above is not undone.
    Invoke-PlanJson @('-Do', 'move', '-Id', 't5', '-Column', 'todo') | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.moved -eq 0 -and $d.sync.PSObject.Properties['cardsMoved'] -and $d.sync.cardsMoved -eq 1) "a task moved with plan -Do move moves its card: $(if ($d.ok) { $d.sync | ConvertTo-Json -Compress } else { $d.error.message })"
    Assert-True ((Get-PlanTask 't5').column -eq 'todo' -and (Get-PlanTask 't2').column -eq 'verify') 'the sync keeps the plan move (t5 in todo) and the board move (t2 in verify)'
    $card = Invoke-Board GET "cards/$((Get-PlanTask 't5').cardId)?fields=name,idList"
    Assert-True ($card.idList -eq $lists['To Do']) "t5's card follows it to 'To Do'"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.moved -eq 0 -and $d.sync.PSObject.Properties['cardsMoved'] -and $d.sync.cardsMoved -eq 0 -and $d.sync.created -eq 0) 'the sync after that changes nothing'

    Invoke-Board PUT "cards/$((Get-PlanTask 't1').cardId)" @{ closed = $true } | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and @($d.sync.warnings | Where-Object { $_ -match '\bt1\b' }).Count -eq 1) "an archived card is reported, not recreated: $($d.sync.warnings -join ' | ')"
    Assert-True ($d.sync.created -eq 0 -and (Get-PlanTask 't1').column -eq 'backlog') 'the archived card leaves its task as it was'

    Invoke-Board PUT "lists/$($lists['Design'])" @{ name = 'Ideas' } | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $d.ok -and $d.error.code -eq 'trello-list-missing' -and $d.error.message -match "'design'") "a board without a Design list fails with trello-list-missing: $($d.error.message)"
    # The same board with the list named in trello.lists: the mapping works and survives sync and link -Board.
    $planPath = Join-Path $dir 'plan/plan.json'
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    $plan.trello | Add-Member -NotePropertyName lists -NotePropertyValue ([pscustomobject]@{ design = 'Ideas' }) -Force
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok) "trello.lists maps design to the list 'Ideas': $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok) "a second sync still uses the mapping: $(if (-not $d.ok) { $d.error.message })"
    Invoke-PlanJson @('-Do', 'link', '-Board', $board.shortLink) | Out-Null
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    Assert-True ($plan.trello.board -eq $board.shortLink -and $plan.trello.lists.design -eq 'Ideas') 'sync and link -Board keep trello.lists'
    $plan.trello.PSObject.Properties.Remove('lists')
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
    Invoke-Board PUT "lists/$($lists['Design'])" @{ name = 'Design' } | Out-Null

    $emptyBoard = Invoke-Board POST 'boards' @{ name = "hyperdot sync test (no lists)"; defaultLists = $false; prefs_permissionLevel = 'private' }
    $d = Invoke-PlanJson @('-Do', 'sync', '-Board', $emptyBoard.id)
    Assert-True (-not $d.ok -and $d.error.code -eq 'trello-list-missing' -and $d.error.message -match 'no open lists') "a board with no lists fails with trello-list-missing: $($d.error.code) $($d.error.message)"
    Assert-True ((Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json).trello.board -eq $board.shortLink) 'a failed sync with -Board keeps the saved board'

    # A column no list maps to is refused before any call, so nothing is half done.
    Invoke-PlanJson @('-Do', 'add', '-Title', 'Combo meter') | Out-Null
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    (@($plan.tasks) | Where-Object { $_.id -eq 't6' }).column = 'review'
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-plan' -and $d.error.message -match 't6') "a task in an unknown column fails with invalid-plan: $($d.error.code) $($d.error.message)"
    Assert-True (-not (Get-PlanTask 't6').PSObject.Properties['cardId']) 'and gets no card'
    Invoke-PlanJson @('-Do', 'move', '-Id', 't6', '-Column', 'backlog') | Out-Null

    if (-not $Live) {
        # A call that fails halfway (429 here) must not lose the ids of the cards made before it.
        Invoke-PlanJson @('-Do', 'add', '-Title', 'Rate limited once') | Out-Null
        $d = Invoke-PlanJson @('-Do', 'sync')
        Assert-True (-not $d.ok -and $d.error.code -eq 'trello-error' -and $d.error.message -match '\(429\)') "a 429 fails with trello-error (429): $($d.error.code) $($d.error.message)"
        Assert-True ([bool](Get-PlanTask 't6').PSObject.Properties['cardId']) 'the card made before the failure keeps its id in plan.json'
        $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
        (@($plan.tasks) | Where-Object { $_.id -eq 't7' }).title = 'Credits screen'
        $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
        $d = Invoke-PlanJson @('-Do', 'sync')
        Assert-True ($d.ok -and $d.sync.created -eq 1) "the next sync creates only the missing card: $(if ($d.ok) { $d.sync | ConvertTo-Json -Compress } else { $d.error.message })"
        Assert-True (@($state.cards.Values | Where-Object { $_.name -eq 'Combo meter' }).Count -eq 1) 'no card is duplicated'
    }

    # Board list names stand for columns, case-insensitive and by prefix as sync matches lists; anything else is refused.
    $d = Invoke-PlanJson @('-Do', 'add', '-Title', 'Sound pass', '-Column', 'testing')
    $sound = $d.ok ? $d.task.id : $null
    Assert-True ($d.ok -and $d.task.column -eq 'verify') "plan -Do add takes the list name 'testing' for verify: $(if ($d.ok) { $d.task | ConvertTo-Json -Compress } else { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'move', '-Id', $sound, '-Column', 'To Do')
    Assert-True ($d.ok -and $d.task.column -eq 'todo' -and (Get-PlanTask $sound).column -eq 'todo') "plan -Do move takes 'To Do' for todo: $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'move', '-Id', $sound, '-Column', $done)
    Assert-True ($d.ok -and $d.task.column -eq 'done') "plan -Do move takes the board's '$done' for done: $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'link', '-Id', $sound, '-Column', 'to do')
    Assert-True ($d.ok -and (Get-PlanTask $sound).boardColumn -eq 'todo') "plan -Do link -Column takes 'to do' for todo: $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'move', '-Id', $sound, '-Column', 'Review')
    Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-arguments' -and $d.error.message -match 'To Do') "a column that is neither an id nor a list name fails with invalid-arguments: $($d.error.message)"
    $d = Invoke-PlanJson @('-Do', 'add', '-Title', 'Nowhere', '-Column', 'Review')
    Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-arguments') 'plan -Do add refuses it too'
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.cardsMoved -eq 0 -and $d.sync.moved -eq 0 -and (Get-PlanTask $sound).column -eq 'done') "the sync after a recorded list moves the card, not the task: $(if ($d.ok) { $d.sync | ConvertTo-Json -Compress } else { $d.error.message })"

    # A card a person adds on the board becomes a task in its list's column; the next sync does not add it again.
    $userCard = Invoke-Board POST 'cards' @{ idList = $lists['To Do']; name = 'Boss rush mode' }
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.imported -eq 1 -and $d.sync.created -eq 0) "a card added on the board is imported: $(if ($d.ok) { $d.sync | ConvertTo-Json -Compress } else { $d.error.message })"
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    $boss = @($plan.tasks) | Where-Object { $_.PSObject.Properties['cardId'] -and $_.cardId -eq $userCard.id } | Select-Object -First 1
    Assert-True ($boss -and $boss.title -eq 'Boss rush mode' -and $boss.column -eq 'todo' -and $boss.boardColumn -eq 'todo' -and $boss.phase -eq 'concept') "it becomes task $(if ($boss) { $boss.id }) 'Boss rush mode' in todo, linked to its card"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.imported -eq 0 -and $d.sync.created -eq 0) 'the next sync imports nothing'

    # plan -Do remove deletes the task; the next sync archives its card, which is then not imported back.
    $d = Invoke-PlanJson @('-Do', 'remove', '-Id', $boss.id)
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    Assert-True ($d.ok -and $d.task.cardId -eq $userCard.id -and -not (Get-PlanTask $boss.id) -and @($plan.trello.toArchive) -contains $userCard.id) "plan -Do remove deletes $($boss.id) and queues its card for archiving: $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.archived -eq 1 -and $d.sync.imported -eq 0) "the next sync archives the card: $(if ($d.ok) { $d.sync | ConvertTo-Json -Compress } else { $d.error.message })"
    Assert-True ((Invoke-Board GET "cards/$($userCard.id)?fields=closed").closed -eq $true) 'the card is archived on the board'
    Assert-True (-not (Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json).trello.PSObject.Properties['toArchive']) 'and nothing is left to archive'
    $d = Invoke-PlanJson @('-Do', 'add', '-Title', 'After the removal')
    Assert-True ($d.ok -and [int]($d.task.id -replace '\D', '') -gt [int]($boss.id -replace '\D', '')) "a removed task's id is not given again: $($boss.id) removed, $($d.task.id) added"
    $d = Invoke-PlanJson @('-Do', 'remove', '-Id', 't999')
    Assert-True (-not $d.ok -and $d.error.code -eq 'unknown-task') 'removing a task that does not exist fails with unknown-task'

    # A card the kit made for a task that no task links (its description says "plan task") is reported, not imported.
    $stray = Invoke-Board POST 'cards' @{ idList = $lists['Backlog']; name = 'Old task'; desc = 'plan task t99, phase concept' }
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.imported -eq 0 -and @($d.sync.warnings | Where-Object { $_ -match 't99' -and $_.Contains($stray.id) }).Count -eq 1) "a kit card no task links is reported: $(if ($d.ok) { $d.sync.warnings -join ' | ' } else { $d.error.message })"
    Invoke-Board PUT "cards/$($stray.id)" @{ closed = $true } | Out-Null

    # The Trello connector's ARIs: a card linked by ARI is stored as its plain id, and one an older plan stored is fixed.
    $workspace = 'a' * 24
    $d = Invoke-PlanJson @('-Do', 'add', '-Title', 'Linked by the connector')
    $byAri = $d.task.id
    $ariCard = Invoke-Board POST 'cards' @{ idList = $lists['Backlog']; name = 'Linked by the connector'; desc = "plan task $byAri, phase concept" }
    $d = Invoke-PlanJson @('-Do', 'link', '-Id', $byAri, '-Card', "ari:cloud:trello::card/workspace/$workspace/$($ariCard.id)", '-Column', 'Backlog')
    Assert-True ($d.ok -and (Get-PlanTask $byAri).cardId -eq $ariCard.id -and $d.task.boardColumn -eq 'backlog') "plan -Do link -Card <ARI> stores the plain card id: $(if ($d.ok) { (Get-PlanTask $byAri).cardId } else { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.created -eq 0 -and $d.sync.imported -eq 0 -and @($d.sync.warnings | Where-Object { $_ -match "\b$byAri\b" }).Count -eq 0) "the card linked by ARI is the task's card: $(if ($d.ok) { $d.sync | ConvertTo-Json -Compress } else { $d.error.message })"
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    (@($plan.tasks) | Where-Object { $_.id -eq $byAri }).cardId = "ari:cloud:trello::card/workspace/$workspace/$($ariCard.id)"
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.created -eq 0 -and @($d.sync.warnings | Where-Object { $_ -match "\b$byAri\b" }).Count -eq 0 -and (Get-PlanTask $byAri).cardId -eq $ariCard.id) "sync turns an ARI an older plan stored into the plain id: $(if ($d.ok) { (Get-PlanTask $byAri).cardId } else { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'link', '-Id', $byAri, '-Card', "https://trello.com/c/AbCd1234/1-linked")
    Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-arguments' -and (Get-PlanTask $byAri).cardId -eq $ariCard.id) "a card URL is refused with invalid-arguments: $($d.error.message)"
    $d = Invoke-PlanJson @('-Do', 'sync', '-Board', "ari:cloud:trello::board/workspace/$workspace/$($board.id)")
    Assert-True ($d.ok -and $d.sync.board -eq $board.id -and $d.trelloBoard -eq $board.id) "sync -Board <ARI> uses and saves the plain board id: $(if ($d.ok) { $d.trelloBoard } else { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'link', '-Board', "https://trello.com/b/$($board.shortLink)/hyperdot-sync-test")
    Assert-True ($d.ok -and $d.trelloBoard -eq $board.shortLink) "link -Board <board URL> saves its short link: $(if ($d.ok) { $d.trelloBoard } else { $d.error.message })"

    $env:TRELLO_TOKEN = $null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $d.ok -and $d.error.code -eq 'trello-credentials') 'sync without TRELLO_TOKEN fails with trello-credentials'
    $env:TRELLO_TOKEN = 'f' * 64
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $d.ok -and $d.error.code -eq 'trello-error' -and $d.error.message -match '\(401\)') "a rejected token fails with trello-error (401): $($d.error.message)"
    $env:TRELLO_TOKEN = $token

    # Nothing listening: the error has no response, which must still give trello-error, not unexpected-error.
    $closed = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $closed.Start(); $closedPort = $closed.LocalEndpoint.Port; $closed.Stop()
    $env:TRELLO_API_URL = "http://localhost:$closedPort/1"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $d.ok -and $d.error.code -eq 'trello-error' -and $d.error.message -match 'no response') "an unreachable API fails with trello-error: $($d.error.code) $($d.error.message)"
    $env:TRELLO_API_URL = $Live ? $null : $base

    Assert-True (@($outputs | Where-Object { $_.Contains($token) -or $_.Contains('f' * 64) }).Count -eq 0) 'no output of the kit contains a token'
    if (-not $Live) { Assert-True ($state.leaks -eq 0) 'the kit never puts credentials in a URL' }
} finally {
    $env:TRELLO_TOKEN = $token
    if ($emptyBoard) {
        try { Invoke-Board DELETE "boards/$($emptyBoard.id)" | Out-Null } catch { Write-Host "WARNING: could not delete board $($emptyBoard.id): $_" -ForegroundColor Yellow }
    }
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
