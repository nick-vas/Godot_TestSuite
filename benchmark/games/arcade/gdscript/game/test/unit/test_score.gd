extends GutTest
## Score: the combo multiplier and what a miss does.


func test_fifth_hit_in_a_row_doubles_the_points():
	var score := Score.new()
	for i in 4:
		score.hit(10)
	assert_eq(score.hit(10), 20)


func test_miss_resets_the_combo():
	var score := Score.new()
	score.hit(10)
	score.hit(10)
	score.miss()
	assert_eq(score.combo, 0)


func test_points_add_up_over_a_long_combo():
	var score := Score.new()
	for i in 12:
		score.hit(10)
	# Four hits at x1, five at x2, three at x3.
	assert_eq(score.points, 230)
