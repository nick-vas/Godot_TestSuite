extends GutTest
## LaunchOptions: the flags bot runs and tests pass after "--".


func test_every_flag_is_read():
	var options := LaunchOptions.parse(PackedStringArray(["--autoplay", "--seed=7", "--no-save", "--level=3"]))
	assert_true(options.autoplay)
	assert_eq(options.run_seed, 7)
	assert_true(options.no_save)
	assert_eq(options.level, 3)


func test_no_flags_is_a_normal_game():
	var options := LaunchOptions.parse(PackedStringArray())
	assert_false(options.autoplay)
	assert_false(options.no_save)
	assert_eq(options.level, 1)


func test_a_level_below_one_starts_at_one():
	assert_eq(LaunchOptions.parse(PackedStringArray(["--level=0"])).level, 1)
