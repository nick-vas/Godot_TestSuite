extends GutTest
## The game scene: the climber starts at the level's start, gathers glowmoss, stomps beetles, comes back after a fall,
## and the camera stays inside the level.

var game: Node3D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func test_level_one_starts_at_its_start_with_three_hearts():
	assert_eq(game.level, 1)
	assert_almost_eq(game.player.position.x, game.current.start_position().x, 0.01)
	assert_eq(game.rules.hearts, 3)


func test_touching_glowmoss_gathers_it_and_the_hud_shows_it():
	var tuft: Node3D = game.current.moss.get_child(0)
	var count: int = game.current.moss.get_child_count()
	game.player.place(tuft.position - Vector3(0, 0.5, 0))
	await wait_physics_frames(2)
	assert_eq(game.current.moss.get_child_count(), count - 1)
	assert_eq(game.rules.moss, 1)
	assert_string_contains(game.get_node("HUD/MossLabel").text, "1")


func test_falling_onto_a_beetle_stomps_it():
	var beetle: Beetle = game.current.beetles.get_child(0)
	beetle.set_physics_process(false)
	var points := beetle.points
	game.player.place(beetle.position + Vector3(0, 0.8, 0))
	# A quarter of a second, whatever the tick rate.
	await wait_physics_frames(Engine.physics_ticks_per_second / 4)
	assert_eq(game.current.beetles.get_child_count(), 0)
	assert_eq(game.rules.hearts, 3)
	assert_eq(game.rules.score, points)


func test_a_fall_out_of_the_level_costs_a_heart_and_returns_to_the_start():
	game.player.place(Vector3(15, -20, 0))
	await wait_physics_frames(2)
	assert_eq(game.rules.hearts, 2)
	assert_almost_eq(game.player.position.x, game.current.start_position().x, 0.01)


func test_the_camera_never_shows_past_the_level_start():
	var bounds: AABB = game.current.bounds()
	var half: Vector2 = game.camera.half_extents()
	assert_true(game.camera.position.x - half.x >= bounds.position.x - 0.01, "left edge of the view inside the level")
	assert_true(game.camera.position.y - half.y >= bounds.position.y - 0.01, "bottom of the view inside the level")
