extends GutTest
## Waves: the level and enemy tables as the game reads them.

var waves: Waves


func before_each():
	waves = Waves.from_files()


func test_the_game_has_at_least_three_levels():
	assert_true(waves.level_count() >= 3)


func test_level_one_is_one_line_of_six_grunts():
	var rows := waves.waves(1)
	assert_eq(rows.size(), 1)
	assert_eq(str(rows[0].enemy), "grunt")
	assert_eq(int(rows[0].count), 6)
	assert_eq(str(rows[0].formation), "line")


func test_the_first_three_levels_have_no_boss():
	for level in range(1, 4):
		assert_true(waves.boss(level).is_empty(), "level %d has no boss" % level)


func test_every_wave_names_a_known_enemy_and_formation():
	for level in range(1, waves.level_count() + 1):
		for row: Dictionary in waves.waves(level):
			assert_false(waves.enemy(str(row.enemy)).is_empty(), "%s names %s" % [row.id, row.enemy])
			assert_has(["line", "v", "grid"], str(row.formation))


func test_tables_can_come_from_rows():
	var custom := Waves.new()
	custom.load_tables([{"id": "a", "hp": 1, "points": 10}], [{"id": "1-1", "level": 1, "enemy": "a", "count": 2, "formation": "line", "speed": 10}])
	assert_eq(custom.level_count(), 1)
	assert_eq(custom.waves(2), [])
	assert_eq(int(custom.enemy("a").points), 10)
