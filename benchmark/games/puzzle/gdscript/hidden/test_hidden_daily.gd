extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the daily drift's generator gives each seed one valid level.


func test_hidden_the_same_seed_gives_the_same_level():
	var first: Dictionary = LevelGenerator.generate(20261023)
	randomize()
	var second: Dictionary = LevelGenerator.generate(20261023)
	assert_eq(str(first.rows), str(second.rows))


func test_hidden_every_seed_gives_a_level_solvable_in_4_to_14_moves():
	var solver := Solver.new()
	for run_seed in range(1, 41):
		var made: Dictionary = LevelGenerator.generate(run_seed)
		var fewest := solver.min_moves(Board.from_rows(made.rows))
		assert_eq(fewest, int(made.par), "seed %d" % run_seed)
		assert_between(fewest, 4, 14, "seed %d" % run_seed)
