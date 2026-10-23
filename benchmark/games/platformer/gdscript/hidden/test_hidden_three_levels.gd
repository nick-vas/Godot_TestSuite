extends GutTest
## Hidden acceptance for the prototype-to-alpha milestone: three levels in order from data/levels.json, each a level
## scene, and a save of the furthest level reached.

const PATH := "user://hidden_milestone_save.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_hidden_three_levels_load():
	var levels := Levels.from_files()
	assert_true(levels.count() >= 3, "at least three levels")
	for number in range(1, 4):
		var row := levels.level(number)
		assert_false(row.is_empty(), "level %d is listed" % number)
		var level: Level = load(str(row.get("scene", ""))).instantiate()
		add_child_autofree(level)
		assert_not_null(level.get_node_or_null("Start"), "level %d has a Start" % number)
		assert_not_null(level.get_node_or_null("Beacon"), "level %d has a Beacon" % number)
		for beetle: Beetle in level.beetles.get_children():
			assert_false(levels.beetle(beetle.kind).is_empty(), "level %d names a known beetle" % number)


func test_hidden_the_furthest_level_is_saved():
	var store := SaveStore.new(PATH)
	var data := store.read()
	data.unlocked = 3
	assert_true(store.write(data))
	assert_eq(int(SaveStore.new(PATH).read().unlocked), 3)
