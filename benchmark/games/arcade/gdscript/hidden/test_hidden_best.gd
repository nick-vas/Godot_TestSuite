extends GutTest
## Hidden check for the prototype's add-feature: the best score survives reset().


func test_hidden_best_survives_reset():
	var score := Score.new()
	score.hit(100)
	score.hit(100)
	score.reset()
	assert_eq(score.points, 0)
	assert_eq(score.combo, 0)
	assert_eq(score.best, 200)


func test_hidden_best_keeps_the_highest_game():
	var score := Score.new()
	score.hit(300)
	score.reset()
	score.hit(100)
	assert_eq(score.best, 300)
	score.hit(100)
	score.hit(100)
	assert_eq(score.best, 300)
	score.hit(100)
	assert_eq(score.best, 400)
