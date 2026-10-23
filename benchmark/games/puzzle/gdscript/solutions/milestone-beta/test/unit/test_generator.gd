extends GutTest
## LevelGenerator: the same seed gives the same level, and every seed of a sweep a valid one.


func _fingerprint(rows: Array) -> String:
	return "/".join(PackedStringArray(rows))


func test_the_same_seed_gives_the_same_level():
	var first := LevelGenerator.generate(42)
	var second := LevelGenerator.generate(42)
	assert_eq(_fingerprint(first.rows), _fingerprint(second.rows))
	assert_eq(first.par, second.par)


func test_different_seeds_give_different_levels():
	var seen := {}
	for run_seed in range(1, 21):
		seen[_fingerprint(LevelGenerator.generate(run_seed).rows)] = true
	assert_gt(seen.size(), 15)


func test_every_seed_of_a_sweep_gives_a_valid_level():
	var solver := Solver.new()
	for run_seed in range(1, 101):
		var made := LevelGenerator.generate(run_seed)
		assert_gt(int(made.attempts), 0, "seed %d fell back" % run_seed)
		var board := Board.from_rows(made.rows)
		assert_eq(board.sparks.size(), LevelGenerator.SPARKS, "seed %d sparks" % run_seed)
		assert_eq(solver.min_moves(board), int(made.par), "seed %d par" % run_seed)
		assert_between(int(made.par), LevelGenerator.MIN_PAR, LevelGenerator.MAX_PAR, "seed %d par" % run_seed)
		if is_failing():
			return


## An unintended change to the generator shows up here; when the change is intended, update the rows in the same commit.
func test_seed_7_is_pinned():
	assert_eq(_fingerprint(LevelGenerator.generate(7).rows), "#########/##.E.####/#.##....#/#.......#/#..S.#..#/##*...#.#/#.....#*#/#########")


func test_the_fallback_can_be_solved():
	assert_gt(Solver.new().min_moves(Board.from_rows(LevelGenerator.FALLBACK)), 0)
