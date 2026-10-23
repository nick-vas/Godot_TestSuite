extends GutTest
## Hidden check for the alpha's add-content: level 4, Runner Bridge, with runner beetles, glowmoss, a checkpoint and the
## beacon.


func _level_four() -> Level:
	var row := Levels.from_files().level(4)
	assert_false(row.is_empty(), "data/levels.json has a level 4")
	if row.is_empty():
		return null
	var level: Level = load(str(row.scene)).instantiate()
	add_child_autofree(level)
	return level


func test_hidden_level_four_follows_level_three():
	var levels := Levels.from_files()
	assert_true(levels.count() >= 4, "at least four levels")
	assert_false(levels.level(3).is_empty())
	assert_ne(str(levels.level(4).get("scene", "")), str(levels.level(3).scene))


func test_hidden_level_four_has_what_was_asked():
	var level := _level_four()
	if level == null:
		return
	assert_true(level.moss.get_child_count() >= 6, "at least six tufts of glowmoss")
	assert_true(level.checkpoints.get_child_count() >= 1, "a checkpoint")
	assert_not_null(level.get_node_or_null("Beacon"), "a beacon")
	var runners := 0
	for beetle: Beetle in level.beetles.get_children():
		if beetle.kind == "runner":
			runners += 1
	assert_true(runners >= 2, "two runners, found %d" % runners)


func test_hidden_the_runner_is_as_asked():
	var runner := Levels.from_files().beetle("runner")
	assert_false(runner.is_empty(), "data/beetles.json has the runner")
	assert_almost_eq(float(runner.get("speed", 0)), 3.5, 0.001)
	assert_eq(int(runner.get("points", 0)), 80)


func test_hidden_level_four_plays():
	var game: Node3D = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.start_level(4)
	await wait_physics_frames(10)
	assert_eq(game.level, 4)
	assert_eq(game.state, "playing")
	assert_eq(game.rules.hearts, 3, "nothing hurts the climber at the start")
