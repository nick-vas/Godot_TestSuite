extends GutTest
## SaveStore: reading, writing and the move from version 1.

const PATH := "user://test_save_store.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_no_file_gives_the_defaults():
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.version), SaveStore.VERSION)
	assert_eq(data.record.size(), 0)
	assert_null(data.duel)
	assert_eq(str(data.settings.locale), "en")


func test_what_is_written_reads_back():
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	Ladder.record(data, 1, true)
	Ladder.record(data, 2, false)
	data.settings.locale = "fr"
	assert_true(store.write(data))
	var back := store.read()
	assert_eq(Ladder.wins(back, 1), 1)
	assert_eq(Ladder.losses(back, 2), 1)
	assert_eq(str(back.settings.locale), "fr")


func test_a_version_1_save_keeps_its_beaten_rivals():
	_write_raw('{"version": 1, "beaten": [1, 2]}')
	var data := SaveStore.new(PATH).read()
	assert_true(Ladder.is_beaten(data, 1))
	assert_true(Ladder.is_beaten(data, 2))
	assert_true(Ladder.is_unlocked(data, 3))
	assert_false(Ladder.is_unlocked(data, 4))


func test_a_disabled_store_writes_nothing():
	var store := SaveStore.new(PATH)
	store.enabled = false
	assert_false(store.write(SaveStore.defaults()))
	assert_false(FileAccess.file_exists(PATH))


func test_a_damaged_file_gives_the_defaults():
	_write_raw("not json {")
	assert_eq(SaveStore.new(PATH).read().record.size(), 0)
