extends GutTest
## The levels of data/levels.json: each loads, and the solver solves it in exactly its par, so no level ships unsolvable
## and no par promises fewer moves than are possible.


func test_every_level_can_be_solved_in_its_par():
	var levels := Levels.from_file()
	var solver := Solver.new()
	assert_gt(levels.level_count(), 0, "no levels loaded")
	for id in range(1, levels.level_count() + 1):
		var board := levels.board(id)
		assert_ne(board.exit, Vector2i(-1, -1), "level %d has no exit" % id)
		assert_eq(solver.min_moves(board), levels.par(id), "level %d: fewest moves against its par" % id)


func test_levels_are_numbered_from_one_without_gaps():
	var levels := Levels.from_file()
	for id in range(1, levels.level_count() + 1):
		assert_true(levels.has_level(id), "level %d is missing" % id)
