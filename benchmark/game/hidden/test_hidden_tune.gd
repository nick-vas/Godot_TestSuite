extends GutTest
# Hidden check for GAME-TUNE-001: the default plays as before, and hit_value changes what a hit is worth.

func test_hidden_default_hit_value_keeps_the_score():
	var main = add_child_autofree(load("res://main.tscn").instantiate())
	assert_eq(main.hit_value, 10)
	assert_eq(main.score.points, 230)

func test_hidden_hit_value_is_used():
	var main = load("res://main.tscn").instantiate()
	main.hit_value = 1
	add_child_autofree(main)
	assert_eq(main.score.points, 23)
