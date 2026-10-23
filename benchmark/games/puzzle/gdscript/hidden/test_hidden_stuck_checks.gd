extends GutTest
## Hidden check for the beta's fix-performance: the dead-end check runs once per move, not every frame, and still works.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func test_hidden_no_search_while_the_player_thinks():
	game.start_level(8)
	var before: int = game.stuck_checks
	await wait_physics_frames(120)
	assert_lte(game.stuck_checks - before, 1)


func test_hidden_one_search_per_move():
	game.start_level(8)
	var before: int = game.stuck_checks
	assert_true(game.try_move(Vector2i.UP))
	await wait_physics_frames(60)
	assert_between(game.stuck_checks - before, 1, 2)


func test_hidden_a_dead_end_is_still_reported():
	game.start_level(6)
	assert_true(game.try_move(Vector2i.UP))
	await wait_physics_frames(40)
	assert_true(game.stuck)
	assert_true(game.get_node("HUD/StuckLabel").visible)
