extends GutTest
## Hidden check for the prototype's fix-bug: undo brings back exactly the sparks of the move it takes back.

const ROWS := ["#######", "#S.*..#", "#.....#", "#....*#", "#E....#", "#######"]


func test_hidden_undo_brings_back_only_the_spark_of_the_last_move():
	var board := Board.from_rows(ROWS)
	board.move(Vector2i.RIGHT)
	board.move(Vector2i.DOWN)
	assert_eq(board.sparks.size(), 0)
	assert_true(board.undo())
	assert_eq(board.sparks, [Vector2i(5, 3)] as Array[Vector2i])
	assert_eq(board.position, Vector2i(5, 1))
	assert_eq(board.moves, 1)


func test_hidden_undoing_everything_brings_back_every_spark():
	var board := Board.from_rows(ROWS)
	board.move(Vector2i.RIGHT)
	board.move(Vector2i.DOWN)
	board.undo()
	board.undo()
	assert_eq(board.sparks, [Vector2i(3, 1), Vector2i(5, 3)] as Array[Vector2i])
	assert_eq(board.position, board.start)


func test_hidden_the_level_can_still_be_solved_after_an_undo():
	var board := Board.from_rows(ROWS)
	board.move(Vector2i.RIGHT)
	board.move(Vector2i.DOWN)
	board.undo()
	board.move(Vector2i.DOWN)
	board.move(Vector2i.LEFT)
	assert_true(board.solved)
