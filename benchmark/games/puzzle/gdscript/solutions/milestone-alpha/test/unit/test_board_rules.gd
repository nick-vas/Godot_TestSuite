extends GutTest
## Board's rules one by one: where a slide stops, snow, sparks, the exit, moves that go nowhere and undo.

const SPARKS := ["########", "#S.*.*.#", "#......#", "#E.....#", "########"]


func test_a_slide_stops_on_the_tile_before_a_wall():
	var board := Board.from_rows(["#######", "#S...##", "#######"])
	assert_true(board.move(Vector2i.RIGHT))
	assert_eq(board.position, Vector2i(4, 1))


func test_the_edge_of_the_level_stops_a_slide_like_a_wall():
	var board := Board.from_rows(["S...", "...E"])
	board.move(Vector2i.RIGHT)
	assert_eq(board.position, Vector2i(3, 0))


func test_snow_stops_the_mote_on_the_snow():
	var board := Board.from_rows(["#######", "#S.:..#", "#######"])
	board.move(Vector2i.RIGHT)
	assert_eq(board.position, Vector2i(3, 1))


func test_every_spark_passed_is_collected():
	var board := Board.from_rows(SPARKS)
	board.move(Vector2i.RIGHT)
	assert_eq(board.position, Vector2i(6, 1))
	assert_eq(board.sparks.size(), 0)
	assert_eq(board.last_collected, [Vector2i(3, 1), Vector2i(5, 1)] as Array[Vector2i])


func test_the_exit_is_ice_while_a_spark_is_left():
	var board := Board.from_rows(["#######", "#S....#", "#.#####", "#E....#", "#*....#", "#######"])
	board.move(Vector2i.DOWN)
	assert_false(board.solved)
	assert_eq(board.position, Vector2i(1, 4), "it slides over the closed exit and on")


func test_the_exit_opens_and_stops_the_mote_once_every_spark_is_collected():
	var board := Board.from_rows(["#######", "#S..*.#", "#.#####", "#E....#", "#.....#", "#######"])
	board.move(Vector2i.RIGHT)
	board.move(Vector2i.LEFT)
	board.move(Vector2i.DOWN)
	assert_true(board.solved)
	assert_eq(board.position, Vector2i(1, 3))


func test_a_solved_board_takes_no_more_moves():
	var board := Board.from_rows(["#####", "#S.E#", "#####"])
	board.move(Vector2i.RIGHT)
	assert_true(board.solved)
	assert_false(board.move(Vector2i.LEFT))
	assert_eq(board.moves, 1)


func test_a_move_that_goes_nowhere_is_not_counted():
	var board := Board.from_rows(["#####", "#S.E#", "#####"])
	assert_false(board.move(Vector2i.LEFT))
	assert_false(board.move(Vector2i.UP))
	assert_eq(board.moves, 0)
	assert_false(board.can_undo())


func test_undo_puts_back_the_position_the_sparks_and_the_count():
	var board := Board.from_rows(SPARKS)
	board.move(Vector2i.DOWN)
	board.move(Vector2i.UP)
	board.move(Vector2i.RIGHT)
	assert_true(board.undo())
	assert_eq(board.position, Vector2i(1, 1))
	assert_eq(board.sparks, [Vector2i(3, 1), Vector2i(5, 1)] as Array[Vector2i])
	assert_eq(board.moves, 2)


func test_undo_takes_back_one_move_at_a_time():
	var board := Board.from_rows(["#######", "#S.*..#", "#.....#", "#.*...#", "#E....#", "#######"])
	board.move(Vector2i.RIGHT)
	board.move(Vector2i.DOWN)
	board.move(Vector2i.LEFT)
	assert_eq(board.sparks.size(), 1)
	board.undo()
	assert_eq(board.sparks.size(), 1)
	board.undo()
	board.undo()
	assert_eq(board.sparks.size(), 2)
	assert_false(board.undo())
