class_name PlaytestTracker
extends RefCounted
## Raises the godot-playtest skill's events from what the game already knows (where the player is, and when they make
## progress) and writes them for `hyperdot.ps1 playtest -Sessions`: one JSON batch a line in
## user://playtests/<session>.jsonl. The GDScript port of the C# example's PlaytestTracker, its TelemetryClient's consent
## rule and PlaytestFileSink; the events and their fields are ci/godot/templates/playtest-events.json, and
## test/test_playtest_tracker.gd keeps the two equal.
##
## Analytics: nothing is recorded until the player agrees (set_consent(Consent.GRANTED)); refusing or withdrawing drops
## what is queued and deletes the session files this tracker wrote. Numbers and the game's level ids only.
##
## Wiring, in a playtest build (the export preset's custom feature `playtest`):
##   var _play_seconds := 0.0   # game time: add delta in _process while the game is not paused
##   var tracker := PlaytestTracker.new(func() -> float: return _play_seconds, ["hub", "cave"], "1.0.0")
##   tracker.set_consent(PlaytestTracker.Consent.GRANTED)   # from the game's consent screen (godot-telemetry)
##   tracker.start_level("hub"); tracker.move(player.position.x, player.position.y)   # every frame; z = 0 in 2D
##   tracker.flush()   # on a 30 s Timer and on quit (NOTIFICATION_WM_CLOSE_REQUEST)
## Not thread-safe: call it from the game loop.

enum Consent { NOT_ASKED, GRANTED, REFUSED }

const STUCK := "stuck"
const REVISIT := "revisit"
const SOLVED_BUT_STAYED := "solved_but_stayed"
const ITEM_FOUND := "item_found"
const DEATH := "death"
const HINT_REQUESTED := "hint_requested"
const LEVEL_TIME := "level_time"
const VERSION := 1
const MAX_COORDINATE := 1000000.0
const MAX_SECONDS := 86400.0
const MAX_ID := 100000
const RESULTS: Array[String] = ["finished", "quit", "failed"]
## Events per line written by flush(); a longer queue becomes several lines.
const MAX_BATCH := 100
## The oldest events are dropped past this, so a tester who never flushes cannot fill the memory.
const MAX_QUEUE := 1000

## The grid that "new ground" and revisits are measured on, in world units: 4 m suits a 3D game, about 128 px a 2D one.
var cell_size := 4.0
## No progress and no new ground for this long is a stall (stuck).
var stuck_seconds := 120.0
## Still near a solved puzzle this long after solving it is solved_but_stayed.
var solved_stay_seconds := 30.0
## Moving this far from where a puzzle was solved counts as leaving it, for games that do not call left_puzzle().
var stay_radius := 8.0
## Re-entering a cell counts as a revisit only after this long away, so walking along a cell's edge is not one.
var revisit_away_seconds := 10.0

## A random id for this run of the game: 32 hexadecimal digits, nothing that identifies the player.
var session_id: String
var build: String
## The level being played, or "" between levels.
var level := ""
var consent := Consent.NOT_ASKED

var _clock: Callable
var _levels: PackedStringArray
var _queue: Array[Dictionary] = []
var _seq := 0
var _written: Array[String] = []
var _visited := {}   # Vector3i cell -> [visits, left_at]
var _cell: Variant = null
var _level_start := 0.0
var _last_progress := 0.0
var _at := Vector3.ZERO
var _stall: Variant = null    # [at, position] of an open stall
var _solved: Variant = null   # [puzzle, at, position] of a solved puzzle not left yet


## clock returns the game's time in seconds (paused time does not count). levels lists the game's level ids, the only
## values start_level() takes; empty takes any short id (letters, digits, '_', '.', '-').
func _init(clock: Callable, levels: PackedStringArray = PackedStringArray(), build_version := "dev") -> void:
	_clock = clock
	_levels = levels
	build = build_version
	session_id = Crypto.new().generate_random_bytes(16).hex_encode()


## The player's answer for analytics. Anything but GRANTED drops the queue and deletes the files this session wrote.
func set_consent(answer: Consent) -> void:
	consent = answer
	if answer == Consent.GRANTED:
		return
	_queue.clear()
	for file in _written:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	_written.clear()


## Events waiting for flush().
func queued() -> Array[Dictionary]:
	return _queue.duplicate(true)


## Starts timing a level; a level still open is ended first, as quit. Returns false, and starts nothing, for an id the
## game did not list: a typo would otherwise split one level's numbers in two. Assert on it in the game.
func start_level(id: String) -> bool:
	if not _is_level(id):
		return false
	if level != "":
		end_level("quit")
	level = id
	_level_start = _clock.call()
	_last_progress = _level_start
	_visited.clear()
	_cell = null
	_at = Vector3.ZERO
	_stall = null
	_solved = null
	return true


## The player's position, every frame (or a few times a second), even while standing still. In 2D pass z = 0.
func move(x: float, y: float, z := 0.0) -> void:
	if level == "":
		return
	var now: float = _clock.call()
	_at = Vector3(x, y, z)
	var cell := Vector3i(floori(x / cell_size), floori(y / cell_size), floori(z / cell_size))
	if _cell != cell:
		if _cell != null and _visited.has(_cell):
			_visited[_cell][1] = now
		if _visited.has(cell):
			var known: Array = _visited[cell]
			if now - known[1] >= revisit_away_seconds:
				known[0] += 1
				_send(REVISIT, now, _at, {"visits": mini(known[0], MAX_ID)})
		else:
			_visited[cell] = [1, 0.0]
			if _cell != null:
				_made_progress(now)   # new ground; the level's first cell is where it starts
		_cell = cell
	if _solved != null and _at.distance_to(_solved[2]) > stay_radius:
		_close_solved(now)
	if _stall == null and now - _last_progress >= stuck_seconds:
		_stall = [now, _at]


## Anything the game counts as getting on: a checkpoint, a door opened, an objective done.
func progress() -> void:
	if level != "":
		_made_progress(_clock.call())


func item_found(item: int) -> void:
	if level == "":
		return
	var now: float = _clock.call()
	_send(ITEM_FOUND, now, _at, {"item": item})
	_made_progress(now)


func died(checkpoint: int) -> void:
	if level != "":
		_send(DEATH, _clock.call(), _at, {"checkpoint": checkpoint})


func hint_requested() -> void:
	if level != "":
		_send(HINT_REQUESTED, _clock.call(), _at, {})


## A puzzle was solved where the player is now; also progress.
func puzzle_solved(puzzle: int) -> void:
	if level == "":
		return
	var now: float = _clock.call()
	_close_solved(now)
	_made_progress(now)
	_solved = [puzzle, now, _at]


## The player left the solved puzzle's room (for games that know their rooms).
func left_puzzle() -> void:
	if level != "":
		_close_solved(_clock.call())


## Ends the level ("finished", "quit" or "failed"): closes an open stall or stay, then sends level_time.
func end_level(result: String) -> void:
	if level == "":
		return
	assert(result in RESULTS, "end_level takes finished, quit or failed")
	var now: float = _clock.call()
	_close_stall(now)
	_close_solved(now)
	_track(LEVEL_TIME, {"level": level, "seconds": _seconds(now - _level_start), "result": result})
	level = ""


## Appends the queue to <directory>/<session>.jsonl, one batch of up to MAX_BATCH events a line, and returns how many
## events it wrote (0 without consent or with nothing queued; no file is created then).
func flush(directory := "user://playtests") -> int:
	if consent != Consent.GRANTED or _queue.is_empty():
		return 0
	var folder := ProjectSettings.globalize_path(directory)
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(session_id + ".jsonl")
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		return 0
	file.seek_end()
	var sent := 0
	while not _queue.is_empty():
		var events := _queue.slice(0, MAX_BATCH)
		var batch := {
			"schema": 1, "session": session_id, "build": build,
			"consent": {"policy": 1, "diagnostics": "NotAsked", "analytics": "Granted"},
			"events": events,
		}
		file.store_line(JSON.stringify(batch, "", false))
		_queue = _queue.slice(events.size())
		sent += events.size()
	file.close()
	if path not in _written:
		_written.append(path)
	return sent


func _is_level(id: String) -> bool:
	if _levels.is_empty():
		return RegEx.create_from_string("^[A-Za-z0-9_.-]{1,64}$").search(id) != null
	return id in _levels


func _made_progress(now: float) -> void:
	_close_stall(now)
	_last_progress = now


func _close_stall(now: float) -> void:
	if _stall == null:
		return
	var stall: Array = _stall
	_stall = null
	_send(STUCK, stall[0], stall[1], {"seconds": _seconds(now - _last_progress)})


func _close_solved(now: float) -> void:
	if _solved == null:
		return
	var solved: Array = _solved
	_solved = null
	if now - solved[1] >= solved_stay_seconds:
		_send(SOLVED_BUT_STAYED, solved[1], solved[2], {"puzzle": solved[0], "seconds": _seconds(now - solved[1])})


func _send(event: String, at: float, where: Vector3, extra: Dictionary) -> void:
	var fields := {
		"level": level,
		"x": _coordinate(where.x), "y": _coordinate(where.y), "z": _coordinate(where.z),
		"level_seconds": _seconds(at - _level_start),
	}
	fields.merge(extra)
	_track(event, fields)


func _track(event: String, fields: Dictionary) -> void:
	if consent != Consent.GRANTED:
		return
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_seq += 1
	_queue.append({
		"event": event, "v": VERSION, "seq": _seq,
		"t": Time.get_datetime_string_from_system(true) + "Z",
		"fields": fields,
	})


# Coarsened at the source: hundredths of a unit and of a second are plenty.
static func _coordinate(v: float) -> float:
	return snappedf(clampf(v, -MAX_COORDINATE, MAX_COORDINATE), 0.01)


static func _seconds(v: float) -> float:
	return snappedf(clampf(v, 0.0, MAX_SECONDS), 0.01)
