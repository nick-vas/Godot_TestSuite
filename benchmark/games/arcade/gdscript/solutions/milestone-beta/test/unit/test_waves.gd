extends GutTest
## Waves: the level and enemy tables as the game reads them.

var waves: Waves


func before_each():
	waves = Waves.from_files()


func test_the_game_has_five_levels():
	assert_eq(waves.level_count(), 5)


func test_level_one_is_one_line_of_six_grunts():
	var rows := waves.waves(1)
	assert_eq(rows.size(), 1)
	assert_eq(str(rows[0].enemy), "grunt")
	assert_eq(int(rows[0].count), 6)
	assert_eq(str(rows[0].formation), "line")


func test_level_four_introduces_the_zigzag():
	var ids := []
	for row: Dictionary in waves.waves(4):
		ids.append(str(row.enemy))
	assert_eq(ids.size(), 3)
	assert_has(ids, "zigzag")
	assert_eq(int(waves.enemy("zigzag").hp), 2)
	assert_eq(int(waves.enemy("zigzag").points), 150)


func test_only_the_last_level_has_a_boss():
	for level in range(1, 5):
		assert_true(waves.boss(level).is_empty(), "level %d has no boss" % level)
	assert_false(waves.boss(5).is_empty())


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
