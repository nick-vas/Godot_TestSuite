extends GutTest
## Hidden check for the alpha's fix-architecture: the HUD's glowmoss count still follows what was gathered, also on a
## stretch with no beetles.

var game: Node3D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func _gather_one() -> void:
	var tuft: Node3D = game.current.moss.get_child(0)
	game.player.place(tuft.position - Vector3(0, 0.5, 0))
	await wait_physics_frames(3)


func test_hidden_moss_label_follows_the_count():
	await _gather_one()
	assert_eq(game.rules.moss, 1)
	assert_string_contains(game.get_node("HUD/MossLabel").text, "1")


func test_hidden_moss_label_updates_with_no_beetles_left():
	for beetle: Node3D in game.current.beetles.get_children():
		game.current.beetles.remove_child(beetle)
		beetle.free()
	await _gather_one()
	assert_eq(game.rules.moss, 1)
	assert_string_contains(game.get_node("HUD/MossLabel").text, "1")
