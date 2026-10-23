extends GutTest
## Solver: the shortest solution, and a board that cannot be solved.

const TWO_SPARKS := ["#######", "#S..*.#", "#.#####", "#*...E#", "#######"]


func test_it_finds_the_shortest_solution():
	var board := Board.from_rows(["#######", "#S....#", "#####.#", "#E....#", "#######"])
	var path := Solver.new().solve(board)
	assert_eq(path, [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT] as Array[Vector2i])


func test_its_solution_solves_the_board():
	var board := Board.from_rows(TWO_SPARKS)
	for direction in Solver.new().solve(board):
		board.move(direction)
	assert_true(board.solved)
	assert_eq(board.sparks.size(), 0)


func test_a_walled_in_exit_cannot_be_solved():
	var board := Board.from_rows(["#######", "#S...##", "#####E#", "#######"])
	assert_eq(Solver.new().min_moves(board), -1)
