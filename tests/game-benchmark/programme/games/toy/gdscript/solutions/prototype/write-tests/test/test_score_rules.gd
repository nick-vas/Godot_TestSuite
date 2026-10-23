extends GutTest

func test_the_fifth_hit_is_the_first_double():
	var score := Score.new()
	for i in 4:
		assert_eq(score.hit(10), 10)
	assert_eq(score.hit(10), 20)

func test_a_miss_restarts_the_combo():
	var score := Score.new()
	for i in 5:
		score.hit(10)
	score.miss()
	assert_eq(score.hit(10), 10)
