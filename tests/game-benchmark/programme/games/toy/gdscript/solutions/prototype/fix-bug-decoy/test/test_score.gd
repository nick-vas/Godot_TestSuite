extends GutTest

func test_every_fifth_hit_raises_the_multiplier():
	var score := Score.new()
	for i in 4:
		score.hit(10)
	assert_eq(score.hit(10), 10)

func test_miss_resets_combo():
	var score := Score.new()
	score.hit(10)
	score.miss()
	assert_eq(score.combo, 0)

func test_main_scene_scores_on_ready():
	var main = add_child_autofree(load("res://main.tscn").instantiate())
	# Twelve hits of 10: four at x1, five at x2, three at x3.
	assert_eq(main.score.points, 230)
