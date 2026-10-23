extends GutTest
## Hidden acceptance for the prototype-to-alpha milestone: three levels from data/levels.json, a save of the best score.

const PATH := "user://hidden_milestone_save.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_hidden_three_levels_load():
	var waves := Waves.from_files()
	assert_true(waves.level_count() >= 3, "at least three levels")
	for level in range(1, 4):
		assert_true(waves.waves(level).size() >= 1, "level %d has waves" % level)
		for row: Dictionary in waves.waves(level):
			assert_false(waves.enemy(str(row.enemy)).is_empty(), "level %d names a known enemy" % level)


func test_hidden_best_score_is_saved():
	var store := SaveStore.new(PATH)
	var data := store.read()
	data.best = 3210
	assert_true(store.write(data))
	assert_eq(int(SaveStore.new(PATH).read().best), 3210)
