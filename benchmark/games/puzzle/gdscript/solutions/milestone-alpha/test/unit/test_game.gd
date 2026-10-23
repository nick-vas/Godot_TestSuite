extends GutTest
## The game scene: a move slides the mote and is counted, solving shows the solved panel, a dead end shows the stuck line.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func _slide(direction: Vector2i) -> void:
	assert_true(game.try_move(direction), "the move %s" % direction)
	await wait_physics_frames(30)


func test_level_one_starts_at_its_start():
	assert_eq(game.level, 1)
	assert_eq(game.board.position, game.board.start)
	assert_string_contains(game.get_node("HUD/LevelLabel").text, "1")
	assert_string_contains(game.get_node("HUD/MovesLabel").text, "0")


func test_a_move_is_counted_and_shown():
	await _slide(Vector2i.RIGHT)
	assert_eq(game.board.moves, 1)
	assert_eq(game.state, "playing")
	assert_string_contains(game.get_node("HUD/MovesLabel").text, "1")


func test_solving_level_one_shows_the_solved_panel():
	await _slide(Vector2i.RIGHT)
	await _slide(Vector2i.DOWN)
	await _slide(Vector2i.LEFT)
	assert_eq(game.state, "solved")
	assert_true(game.get_node("SolvedMenu").visible)


func test_the_undo_button_takes_a_move_back():
	await _slide(Vector2i.RIGHT)
	game.get_node("HUD/UndoButton").pressed.emit()
	assert_eq(game.board.moves, 0)
	assert_eq(game.board.position, game.board.start)


func test_a_dead_end_shows_the_stuck_line():
	game.start_level(6)
	await _slide(Vector2i.UP)
	assert_true(game.stuck)
	assert_true(game.get_node("HUD/StuckLabel").visible)
	game.undo()
	assert_false(game.stuck)
	assert_false(game.get_node("HUD/StuckLabel").visible)
