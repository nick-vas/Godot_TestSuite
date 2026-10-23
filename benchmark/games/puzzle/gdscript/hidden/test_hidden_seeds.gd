extends GutTest
## Hidden check for the beta's fix-bug: a daily seed always gives the same level, whatever the global generator did
## before, and generating one leaves the global generator alone.


func _fingerprint(made: Dictionary) -> String:
	return "/".join(PackedStringArray(made.rows))


func test_hidden_the_same_seed_gives_the_same_level_in_any_order():
	var first := _fingerprint(LevelGenerator.generate(20261023))
	randomize()
	LevelGenerator.generate(5)
	randomize()
	assert_eq(_fingerprint(LevelGenerator.generate(20261023)), first)


func test_hidden_seeds_still_differ_and_stay_valid():
	var seen := {}
	var solver := Solver.new()
	for run_seed in range(100, 130):
		var made := LevelGenerator.generate(run_seed)
		seen[_fingerprint(made)] = true
		assert_eq(solver.min_moves(Board.from_rows(made.rows)), int(made.par), "seed %d" % run_seed)
	assert_gt(seen.size(), 25)


func test_hidden_generating_leaves_the_global_generator_alone():
	seed(99)
	var expected := randi()
	seed(99)
	LevelGenerator.generate(7)
	assert_eq(randi(), expected)
