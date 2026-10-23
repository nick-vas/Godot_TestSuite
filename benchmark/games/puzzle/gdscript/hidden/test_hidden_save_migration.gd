extends GutTest
## Hidden check for the alpha's migrate-save: a version 1 save keeps its cleared levels; version 2 still loads.

const PATH := "user://test_hidden_save_migration.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_hidden_version_1_cleared_levels_stay_solved():
	_write_raw('{"version": 1, "cleared": [1, 2, 3]}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.version), 2)
	for id in [1, 2, 3]:
		assert_true(Progress.is_solved(data, id), "level %d solved" % id)
	assert_true(Progress.is_unlocked(data, 4))
	assert_false(Progress.is_unlocked(data, 5))


func test_hidden_a_migrated_level_takes_its_first_recorded_moves():
	_write_raw('{"version": 1, "cleared": [1]}')
	var data := SaveStore.new(PATH).read()
	assert_true(Progress.record(data, 1, 5))
	assert_eq(Progress.best(data, 1), 5)


func test_hidden_version_2_still_loads():
	_write_raw('{"version": 2, "solved": {"1": 4, "2": 9}, "settings": {"volume": 0.25, "locale": "en"}}')
	var data := SaveStore.new(PATH).read()
	assert_eq(Progress.best(data, 2), 9)
	assert_almost_eq(float(data.settings.volume), 0.25, 0.001)
