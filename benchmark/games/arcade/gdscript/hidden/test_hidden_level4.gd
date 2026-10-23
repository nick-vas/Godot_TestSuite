extends GutTest
## Hidden check for the alpha's add-content: level 4 has three waves and brings in the zigzag.


func test_hidden_level_four_has_three_waves_with_the_zigzag():
	var waves := Waves.from_files()
	assert_true(waves.level_count() >= 4, "at least four levels")
	var rows := waves.waves(4)
	assert_eq(rows.size(), 3)
	var ids := []
	for row: Dictionary in rows:
		ids.append(str(row.enemy))
	assert_has(ids, "zigzag")


func test_hidden_zigzag_is_as_asked():
	var zigzag := Waves.from_files().enemy("zigzag")
	assert_false(zigzag.is_empty(), "the enemies table has a zigzag")
	assert_eq(int(zigzag.get("hp", 0)), 2)
	assert_eq(int(zigzag.get("points", 0)), 150)
	assert_true(float(zigzag.get("drift", 0)) > 0.0, "it drifts sideways")


func test_hidden_level_four_plays():
	var game: Node2D = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.start_level(4)
	await wait_physics_frames(2)
	assert_eq(game.level, 4)
	assert_true(game.enemies.get_child_count() > 0, "level 4 spawns its first wave")
