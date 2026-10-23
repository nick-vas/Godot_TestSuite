extends GutTest
## Hidden check for the alpha's migrate-save: version 1 saves (a list of rivals beaten) load as beaten rivals, a save
## without a version is version 1, recording over a migrated save works, and version 2 saves load as they were.

const PATH := "user://test_hidden_save_migration.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_hidden_a_version_1_save_keeps_its_beaten_rivals():
	_write_raw('{"version": 1, "beaten": [1, 2]}')
	var data := SaveStore.new(PATH).read()
	assert_eq(Ladder.wins(data, 1), 1)
	assert_eq(Ladder.wins(data, 2), 1)
	assert_eq(Ladder.losses(data, 1), 0)
	assert_true(Ladder.is_unlocked(data, 3))
	assert_false(Ladder.is_unlocked(data, 4))
	assert_null(data.duel)
	assert_eq(str(data.settings.locale), "en")


func test_hidden_a_save_without_a_version_is_version_1():
	_write_raw('{"beaten": [1]}')
	assert_true(Ladder.is_beaten(SaveStore.new(PATH).read(), 1))


func test_hidden_a_migrated_save_records_and_writes_as_version_2():
	_write_raw('{"version": 1, "beaten": [1]}')
	var store := SaveStore.new(PATH)
	var data := store.read()
	Ladder.record(data, 1, false)
	Ladder.record(data, 2, true)
	assert_true(store.write(data))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(raw.version), 2)
	var back := store.read()
	assert_eq(Ladder.wins(back, 1), 1)
	assert_eq(Ladder.losses(back, 1), 1)
	assert_eq(Ladder.wins(back, 2), 1)


func test_hidden_a_version_2_save_loads_as_it_was():
	_write_raw('{"version": 2, "record": {"3": {"wins": 2, "losses": 1}}, "duel": {"turn": 5}, "settings": {"volume": 0.5, "locale": "en"}}')
	var data := SaveStore.new(PATH).read()
	assert_eq(Ladder.wins(data, 3), 2)
	assert_eq(Ladder.losses(data, 3), 1)
	assert_eq(int(data.duel.turn), 5)
	assert_almost_eq(float(data.settings.volume), 0.5, 0.001)
