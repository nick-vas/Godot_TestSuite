extends GutTest
## Hidden check for the prototype's add-feature: Solver.hint gives the first move of a shortest solution.


func test_hidden_following_the_hints_solves_each_level_in_its_par():
	var levels := Levels.from_file()
	var solver := Solver.new()
	for id in range(1, levels.level_count() + 1):
		var board := levels.board(id)
		for i in levels.par(id):
			var direction: Vector2i = solver.hint(board)
			assert_ne(direction, Vector2i.ZERO, "level %d move %d" % [id, i + 1])
			board.move(direction)
		assert_true(board.solved, "level %d" % id)


func test_hidden_a_hint_from_the_middle_of_a_level():
	var board := Board.from_rows(["#######", "#S..*.#", "#.#####", "#*...E#", "#######"])
	var solver := Solver.new()
	board.move(Vector2i.DOWN)
	assert_eq(solver.hint(board), Vector2i.UP)


func test_hidden_no_hint_when_solved_or_stuck():
	var solver := Solver.new()
	var solved := Board.from_rows(["#####", "#S.E#", "#####"])
	solved.move(Vector2i.RIGHT)
	assert_eq(solver.hint(solved), Vector2i.ZERO)
	var stuck := Board.from_rows(["#######", "#S...##", "#####E#", "#######"])
	assert_eq(solver.hint(stuck), Vector2i.ZERO)
