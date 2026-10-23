extends GutTest
## Hidden check for the alpha's migrate-save: a version 1 save keeps its best score, a version 2 save still loads.

const PATH := "user://hidden_save_migration.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_hidden_version_1_keeps_best_score():
	_write_raw('{"version": 1, "best_score": 4200}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.best), 4200)


func test_hidden_version_1_without_a_version_field():
	_write_raw('{"best_score": 900}')
	assert_eq(int(SaveStore.new(PATH).read().best), 900)


func test_hidden_version_2_still_loads():
	_write_raw('{"version": 2, "best": 777, "settings": {"volume": 0.25, "locale": "en"}}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.best), 777)
	assert_almost_eq(float(data.settings.volume), 0.25, 0.001)


func test_hidden_migrated_save_is_written_as_version_2():
	_write_raw('{"version": 1, "best_score": 1500}')
	var store := SaveStore.new(PATH)
	store.write(store.read())
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(raw.version), 2)
	assert_eq(int(raw.best), 1500)
