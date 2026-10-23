extends GutTest
## Hidden check for the alpha's add-content: level 7 loads, fits the screen, has three sparks and snow, and its par is the
## fewest moves that solve it, at least 9.


func test_hidden_level_7_is_there_after_level_6():
	var levels := Levels.from_file()
	assert_eq(levels.level_count(), 7)
	assert_true(levels.has_level(7))


func test_hidden_level_7_fits_and_has_three_sparks_and_snow():
	var levels := Levels.from_file()
	var board := levels.board(7)
	assert_between(board.width, 3, 11)
	assert_between(board.height, 3, 9)
	assert_eq(board.sparks.size(), 3)
	assert_ne(board.exit, Vector2i(-1, -1), "an exit")
	var snow := 0
	var starts := 0
	for row: String in board.rows():
		snow += row.count(Board.SNOW)
		starts += row.count(Board.START)
	assert_gt(snow, 0, "snow")
	assert_eq(starts, 1, "one start")


func test_hidden_level_7_par_is_its_fewest_moves_and_at_least_9():
	var levels := Levels.from_file()
	var fewest := Solver.new().min_moves(levels.board(7))
	assert_eq(fewest, levels.par(7))
	assert_gte(fewest, 9)
