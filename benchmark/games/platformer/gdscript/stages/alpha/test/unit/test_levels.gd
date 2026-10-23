extends GutTest
## Levels: the tables as the game reads them, and the level scenes they name.

var levels: Levels


func before_each():
	levels = Levels.from_files()


func test_the_game_has_at_least_three_levels_in_order():
	assert_true(levels.count() >= 3)
	for number in range(1, levels.count() + 1):
		assert_eq(int(levels.level(number).number), number)


func test_every_level_scene_has_a_start_a_beacon_and_glowmoss():
	for number in range(1, levels.count() + 1):
		var level: Level = load(str(levels.level(number).scene)).instantiate()
		add_child_autofree(level)
		assert_not_null(level.get_node_or_null("Start"), "level %d has a Start" % number)
		assert_not_null(level.get_node_or_null("Beacon"), "level %d has a Beacon" % number)
		assert_gt(level.moss.get_child_count(), 0, "level %d has glowmoss" % number)


func test_every_beetle_is_a_known_kind():
	for number in range(1, levels.count() + 1):
		var level: Level = load(str(levels.level(number).scene)).instantiate()
		add_child_autofree(level)
		for beetle: Beetle in level.beetles.get_children():
			assert_false(levels.beetle(beetle.kind).is_empty(), "level %d: %s" % [number, beetle.kind])

