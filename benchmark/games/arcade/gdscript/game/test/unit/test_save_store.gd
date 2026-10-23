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
	assert_eq(int(data.best), 0)
	assert_eq(str(data.settings.locale), "en")


func test_what_is_written_reads_back():
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	data.best = 1234
	data.settings.locale = "fr"
	assert_true(store.write(data))
	var back := store.read()
	assert_eq(int(back.best), 1234)
	assert_eq(str(back.settings.locale), "fr")


func test_a_version_1_save_keeps_its_best_score():
	_write_raw('{"version": 1, "best_score": 4200}')
	assert_eq(int(SaveStore.new(PATH).read().best), 4200)


func test_a_version_2_save_keeps_its_settings():
	_write_raw('{"version": 2, "best": 50, "settings": {"volume": 0.5, "locale": "de"}}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.best), 50)
	assert_almost_eq(float(data.settings.volume), 0.5, 0.001)
	assert_eq(str(data.settings.locale), "de")


func test_a_disabled_store_writes_nothing():
	var store := SaveStore.new(PATH)
	store.enabled = false
	assert_false(store.write(SaveStore.defaults()))
	assert_false(FileAccess.file_exists(PATH))


func test_a_damaged_file_gives_the_defaults():
	_write_raw("not json {")
	assert_eq(int(SaveStore.new(PATH).read().best), 0)
