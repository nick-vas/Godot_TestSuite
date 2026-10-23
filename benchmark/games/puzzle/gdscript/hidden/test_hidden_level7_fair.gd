extends GutTest
## Hidden check for the beta's fix-playthrough: level 7 can be solved again, and is still a late level, not a trivial one.


func test_hidden_level_7_is_solvable_in_its_par():
	var levels := Levels.from_file()
	assert_eq(Solver.new().min_moves(levels.board(7)), levels.par(7))


func test_hidden_level_7_is_not_trivial():
	var levels := Levels.from_file()
	var board := levels.board(7)
	assert_between(Solver.new().min_moves(board), 9, 16)
	assert_eq(board.sparks.size(), 3)
