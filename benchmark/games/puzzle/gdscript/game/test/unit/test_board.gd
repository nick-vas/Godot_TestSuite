extends GutTest
## Board: the slide, the move count, undo and restart, on small boards written out here.


func test_a_slide_stops_before_the_wall():
	var board := Board.from_rows(["######", "#S...#", "######"])
	board.move(Vector2i.RIGHT)
	assert_eq(board.position.x, 4)


func test_a_move_into_a_wall_is_not_a_move():
	var board := Board.from_rows(["#####", "#S.E#", "#####"])
	assert_false(board.move(Vector2i.UP))
	assert_eq(board.moves, 0)
	assert_false(board.can_undo())


func test_undo_brings_back_a_collected_spark():
	var board := Board.from_rows(["#######", "#S.*..#", "#.....#", "#E....#", "#######"])
	board.move(Vector2i.RIGHT)
	assert_eq(board.sparks.size(), 0)
	assert_true(board.undo())
	assert_eq(board.sparks, [Vector2i(3, 1)] as Array[Vector2i])
	assert_eq(board.position, Vector2i(1, 1))
	assert_eq(board.moves, 0)


func test_restart_puts_everything_back():
	var board := Board.from_rows(["#######", "#S.*..#", "#.....#", "#E....#", "#######"])
	board.move(Vector2i.RIGHT)
	board.move(Vector2i.DOWN)
	board.restart()
	assert_eq(board.position, board.start)
	assert_eq(board.sparks.size(), 1)
	assert_eq(board.moves, 0)
