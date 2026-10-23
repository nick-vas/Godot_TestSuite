extends GutTest
# Hidden check for GAME-FEAT-001: best keeps the highest points across reset().

func test_hidden_best_follows_points():
	var score := Score.new()
	score.hit(10)
	score.hit(10)
	assert_eq(score.best, 20)

func test_hidden_reset_starts_over_and_keeps_best():
	var score := Score.new()
	for i in 5:
		score.hit(10)
	var reached := score.points
	score.reset()
	assert_eq(score.points, 0)
	assert_eq(score.combo, 0)
	assert_eq(score.best, reached)
	score.hit(10)
	assert_eq(score.best, reached)
	assert_eq(score.hit(10), 10)
