extends GutTest
## Score: the best score survives a new game.


func test_best_is_kept_across_reset():
	var score := Score.new()
	for i in 3:
		score.hit(100)
	score.reset()
	assert_eq(score.best, 300)
	assert_eq(score.points, 0)
	assert_eq(score.combo, 0)


func test_best_is_the_highest_game_not_the_last():
	var score := Score.new()
	score.hit(500)
	score.reset()
	score.hit(100)
	assert_eq(score.best, 500)


func test_best_follows_a_better_game():
	var score := Score.new()
	score.hit(100)
	score.reset()
	score.hit(100)
	score.hit(100)
	assert_eq(score.best, 200)
