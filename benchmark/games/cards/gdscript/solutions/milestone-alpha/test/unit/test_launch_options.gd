extends GutTest
## LaunchOptions: the flags runs and tests pass after "--".


func test_every_flag_is_read():
	var options := LaunchOptions.parse(PackedStringArray(["--seed=7", "--no-save", "--rival=3"]))
	assert_eq(options.run_seed, 7)
	assert_true(options.no_save)
	assert_eq(options.rival, 3)


func test_no_flags_is_a_normal_game():
	var options := LaunchOptions.parse(PackedStringArray())
	assert_false(options.no_save)
	assert_eq(options.run_seed, 0)
	assert_eq(options.rival, 1)
