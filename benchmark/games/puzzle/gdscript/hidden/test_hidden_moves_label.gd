extends GutTest
## Hidden check for the alpha's fix-architecture: the HUD's moves line still follows the moves, undo and a new level.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func test_hidden_the_moves_line_follows_a_move_and_an_undo():
	assert_true(game.try_move(Vector2i.RIGHT))
	await wait_physics_frames(20)
	assert_string_contains(game.get_node("HUD/MovesLabel").text, "1")
	game.undo()
	await wait_physics_frames(2)
	assert_string_contains(game.get_node("HUD/MovesLabel").text, "0")


func test_hidden_the_moves_line_shows_a_new_level_s_par():
	game.start_level(2)
	await wait_physics_frames(2)
	assert_string_contains(game.get_node("HUD/MovesLabel").text, "6")
