extends GutTest
## Rules: lives and the invulnerability after a hit.


func test_a_new_game_has_three_lives():
	var rules := Rules.new()
	assert_eq(rules.lives, 3)


func test_one_hit_costs_one_life():
	var rules := Rules.new(3)
	rules.ship_hit()
	assert_eq(rules.lives, 2)


func test_the_ship_is_invulnerable_right_after_a_hit():
	var rules := Rules.new()
	assert_true(rules.ship_hit())
	assert_true(rules.is_invulnerable())
	assert_false(rules.ship_hit(), "a second hit at once costs nothing")
