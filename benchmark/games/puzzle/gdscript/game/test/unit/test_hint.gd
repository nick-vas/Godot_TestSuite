extends GutTest
## Solver.hint: the first move of a shortest solution from where the mote is, and none once the exit is out of reach.

const TWO_SPARKS := ["#######", "#S..*.#", "#.#####", "#*...E#", "#######"]


func test_the_hint_is_the_first_move_of_a_shortest_solution():
	var board := Board.from_rows(TWO_SPARKS)
	var solver := Solver.new()
	var before := solver.min_moves(board)
	board.move(solver.hint(board))
	assert_eq(solver.min_moves(board), before - 1)


func test_no_hint_once_stuck():
	var board := Board.from_rows(["#######", "#S...##", "#####E#", "#######"])
	assert_eq(Solver.new().hint(board), Vector2i.ZERO)
