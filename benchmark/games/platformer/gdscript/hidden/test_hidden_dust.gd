extends GutTest
## Hidden check for the beta's fix-performance: dust puffs go away after their short life, so a long run does not pile
## up nodes, and running still kicks them up.

var game: Node3D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func after_each():
	Input.action_release("move_right")


func test_hidden_dust_does_not_pile_up():
	for i in 300:
		game.spawn_dust(game.player.position)
		await wait_physics_frames(1)
	assert_lt(game.effects.get_child_count(), 40, "puffs alive after 5 seconds of one a tick")


func test_hidden_running_still_kicks_up_dust():
	Input.action_press("move_right")
	await wait_physics_frames(30)
	assert_gt(game.effects.get_child_count(), 0)
