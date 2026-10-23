extends GutTest
## PlaytestTracker (playtest/playtest_tracker.gd) with a fake clock: the same cases as the C# example's PlaytestTests.

var _now := 0.0
var _tracker: PlaytestTracker
var _folder := ""


func before_each() -> void:
	_now = 0.0
	# 4-unit cells, 120 s stall, 30 s stay, 8-unit radius, 10 s away.
	_tracker = PlaytestTracker.new(func() -> float: return _now, PackedStringArray(["hub", "cave"]), "1.0.0")
	_tracker.set_consent(PlaytestTracker.Consent.GRANTED)
	_folder = "user://playtests-test-%d" % randi()


func after_each() -> void:
	var folder := ProjectSettings.globalize_path(_folder)
	if DirAccess.dir_exists_absolute(folder):
		for file in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(file))
		DirAccess.remove_absolute(folder)


func _events(event := "") -> Array:
	var found := []
	for e in _tracker.queued():
		if event == "" or e["event"] == event:
			found.append(e["fields"] if event != "" else e["event"])
	return found


# Moves once a second until `until`, at a fixed place.
func _stay_until(until: float, x: float, y: float, z := 0.0) -> void:
	while _now < until:
		_now += 1
		_tracker.move(x, y, z)


func test_nothing_is_recorded_without_consent() -> void:
	var tracker := PlaytestTracker.new(func() -> float: return _now, PackedStringArray(["hub"]))
	tracker.start_level("hub")
	for i in 300:
		_now = i
		tracker.move(1, 1)
	tracker.died(1)
	tracker.end_level("finished")
	assert_eq(tracker.queued().size(), 0)
	assert_eq(tracker.flush(_folder), 0, "nothing written, and no folder made")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_folder)))


func test_a_stall_is_sent_when_it_ends_with_its_whole_length_at_the_place_it_began() -> void:
	_tracker.start_level("hub")
	_tracker.move(1, 1)
	_stay_until(119, 1, 1)
	assert_eq(_events(PlaytestTracker.STUCK).size(), 0, "119 s without progress is not yet a stall")
	_stay_until(120, 2, 3)   # becomes one here, at (2, 3)
	_stay_until(200, 1, 1)
	assert_eq(_events(PlaytestTracker.STUCK).size(), 0, "still stuck: sent when it ends")
	_tracker.progress()
	var stuck: Array = _events(PlaytestTracker.STUCK)
	assert_eq(stuck.size(), 1)
	assert_eq(stuck[0]["seconds"], 200.0)
	assert_eq(stuck[0]["level_seconds"], 120.0)
	assert_eq([stuck[0]["x"], stuck[0]["y"], stuck[0]["z"]], [2.0, 3.0, 0.0])
	assert_eq(stuck[0]["level"], "hub")


func test_pacing_between_known_cells_is_stuck_but_new_ground_is_progress() -> void:
	_tracker.start_level("hub")
	for i in 130:   # back and forth between two cells: the same area, no progress
		_now += 1
		_tracker.move(1 if i % 2 == 0 else 5, 1)
	_tracker.move(41, 1)   # new ground ends the stall
	assert_eq(_events(PlaytestTracker.STUCK).size(), 1)
	for i in range(1, 6):   # reaching new cells, slowly, is exploring
		_stay_until(_now + 100, 41 + 4 * i, 1)
	_tracker.end_level("finished")
	assert_eq(_events(PlaytestTracker.STUCK).size(), 1)


func test_reentering_a_cell_after_time_away_is_a_revisit() -> void:
	_tracker.start_level("cave")
	_tracker.move(1, 1)               # cell (0, 0)
	_now = 1; _tracker.move(5, 1)     # (1, 0)
	_now = 2; _tracker.move(1, 1)     # back after 1 s: walking along an edge
	_now = 3; _tracker.move(5, 1)
	assert_eq(_events(PlaytestTracker.REVISIT).size(), 0)
	_now = 20; _tracker.move(1.5, 2)  # back after 17 s away
	var revisits: Array = _events(PlaytestTracker.REVISIT)
	assert_eq(revisits.size(), 1)
	assert_eq([revisits[0]["visits"], revisits[0]["level_seconds"], revisits[0]["x"]], [2, 20.0, 1.5])
	_now = 40; _tracker.move(5, 1)
	_now = 60; _tracker.move(1, 1)
	assert_eq(_events(PlaytestTracker.REVISIT).map(func(f: Dictionary) -> int: return f["visits"]), [2, 2, 3])


func test_staying_beside_a_solved_puzzle_is_sent_on_leaving() -> void:
	_tracker.start_level("cave")
	_now = 10; _tracker.move(2, 2)
	_tracker.puzzle_solved(7)
	_stay_until(50, 3, 2)              # within 8 units for 40 s
	assert_eq(_events(PlaytestTracker.SOLVED_BUT_STAYED).size(), 0)
	_now = 51; _tracker.move(20, 2)    # gone
	var stayed: Array = _events(PlaytestTracker.SOLVED_BUT_STAYED)
	assert_eq(stayed.size(), 1)
	assert_eq([stayed[0]["puzzle"], stayed[0]["seconds"], stayed[0]["level_seconds"], stayed[0]["x"]], [7, 41.0, 10.0, 2.0])
	# Left within 30 s, through the game's own room exit: nothing to report.
	_tracker.puzzle_solved(8)
	_now += 20; _tracker.move(21, 2)
	_tracker.left_puzzle()
	_now += 60; _tracker.move(21, 2)
	assert_eq(_events(PlaytestTracker.SOLVED_BUT_STAYED).size(), 1)


func test_items_deaths_and_hints_are_sent_where_the_player_is_and_the_level_is_timed() -> void:
	_tracker.start_level("hub")
	_now = 5; _tracker.move(10, -4, 2.5)
	_tracker.item_found(3)
	_now = 9; _tracker.died(2)
	_tracker.hint_requested()
	_now = 12.346; _tracker.end_level("failed")
	assert_eq(_events(), [PlaytestTracker.ITEM_FOUND, PlaytestTracker.DEATH, PlaytestTracker.HINT_REQUESTED, PlaytestTracker.LEVEL_TIME])
	var death: Dictionary = _events(PlaytestTracker.DEATH)[0]
	assert_eq([death["x"], death["y"], death["z"], death["level_seconds"], death["checkpoint"]], [10.0, -4.0, 2.5, 9.0, 2])
	var time: Dictionary = _events(PlaytestTracker.LEVEL_TIME)[0]
	assert_eq(time["seconds"], 12.35, "hundredths of a second")
	assert_eq(time["result"], "failed")
	assert_eq(_tracker.level, "")


func test_the_levels_end_closes_an_open_stall_and_a_new_level_ends_the_old_one() -> void:
	_tracker.start_level("hub")
	_stay_until(150, 1, 1)
	_tracker.start_level("cave")   # hub was never ended: quit, with its stall
	var stuck: Array = _events(PlaytestTracker.STUCK)
	assert_eq(stuck.size(), 1)
	assert_eq(stuck[0]["seconds"], 150.0)
	var time: Dictionary = _events(PlaytestTracker.LEVEL_TIME)[0]
	assert_eq([time["level"], time["result"], time["seconds"]], ["hub", "quit", 150.0])
	assert_eq(_tracker.level, "cave")


func test_a_level_the_game_did_not_list_is_refused() -> void:
	assert_false(_tracker.start_level("secret_room"))
	_tracker.died(0)
	assert_eq(_tracker.level, "")
	assert_eq(_tracker.queued().size(), 0)


# ci/godot/templates/playtest-events.json is what hyperdot.ps1 playtest reads the sessions with: every event the
# tracker writes must have exactly its fields, of its kinds and within its ranges. The template is found while the
# example sits in the kit; a game copied from it, with no kit two folders up, has nothing to compare with.
func test_every_event_fits_the_kits_template() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../../ci/godot/templates/playtest-events.json").simplify_path()
	if not FileAccess.file_exists(path):
		pass_test("no kit above this project: nothing to compare with")
		return
	var template: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(int(template["version"]), PlaytestTracker.VERSION)
	_tracker.start_level("hub")
	_tracker.move(1, 1)
	_stay_until(130, 1, 1)
	_tracker.progress()
	_now = 140; _tracker.move(5, 1)
	_now = 160; _tracker.move(1, 1)
	_tracker.puzzle_solved(1)
	_stay_until(200, 1, 1)
	_tracker.left_puzzle()
	_tracker.item_found(4)
	_tracker.died(0)
	_tracker.hint_requested()
	_tracker.end_level("finished")
	var seen := {}
	for e in _tracker.queued():
		var definition: Dictionary = template["events"][e["event"]]
		seen[e["event"]] = true
		assert_eq(e["v"], int(definition["v"]), "%s version" % e["event"])
		var fields: Dictionary = e["fields"]
		var expected: Array = definition["fields"].keys()
		var got: Array = fields.keys()
		expected.sort()
		got.sort()
		assert_eq(got, expected, "%s fields" % e["event"])
		for name: String in definition["fields"]:
			var kind: Dictionary = definition["fields"][name]
			var value: Variant = fields.get(name)
			var where := "%s.%s = %s" % [e["event"], name, value]
			match kind["kind"]:
				"label":
					assert_eq(typeof(value), TYPE_STRING, where)
					if kind.has("allowed"):
						assert_has(kind["allowed"], value, where)
				"number":
					assert_true(typeof(value) in [TYPE_INT, TYPE_FLOAT] and value >= kind["min"] and value <= kind["max"], where)
				"integer":
					assert_true(typeof(value) == TYPE_INT and value >= kind["min"] and value <= kind["max"], where)
				_:
					fail_test("%s: kind %s has no form here" % [where, kind["kind"]])
	var names: Array = seen.keys()
	var all: Array = template["events"].keys()
	names.sort()
	all.sort()
	assert_eq(names, all, "every event of the template was raised once at least")


# A playtest build flushes to files: one JSON batch a line, in a file named after the session, appended at each flush.
func test_flush_writes_each_batch_as_a_line_of_the_sessions_file_and_withdrawing_deletes_it() -> void:
	_tracker.start_level("hub")
	_tracker.move(1, 1)
	_tracker.died(3)
	assert_eq(_tracker.flush(_folder), 1)
	_now = 42
	_tracker.end_level("finished")
	assert_eq(_tracker.flush(_folder), 1)
	assert_eq(_tracker.flush(_folder), 0, "nothing left: nothing written")
	var file := ProjectSettings.globalize_path(_folder).path_join(_tracker.session_id + ".jsonl")
	var lines := FileAccess.get_file_as_string(file).strip_edges().split("\n")
	assert_eq(lines.size(), 2)
	var batches := Array(lines).map(func(l: String) -> Dictionary: return JSON.parse_string(l))
	for batch: Dictionary in batches:
		assert_eq(batch["session"], _tracker.session_id)
		assert_eq(batch["build"], "1.0.0")
		assert_eq(batch["consent"]["analytics"], "Granted")
	assert_eq(batches.map(func(b: Dictionary) -> String: return b["events"][0]["event"]), [PlaytestTracker.DEATH, PlaytestTracker.LEVEL_TIME])
	assert_eq(batches[1]["events"][0]["fields"]["seconds"], 42.0)
	assert_eq(batches[1]["events"][0]["seq"], 2.0, "seq counts on across flushes")
	_tracker.set_consent(PlaytestTracker.Consent.REFUSED)
	assert_false(FileAccess.file_exists(file), "withdrawing consent deletes the session's file")
