extends GutTest
## Rules: what a collision does to the ship and to an enemy, and when the game is over.


func test_a_hit_costs_a_life():
	var rules := Rules.new()
	assert_true(rules.ship_hit())
	assert_eq(rules.lives, 2)


func test_hits_within_two_seconds_cost_one_life():
	var rules := Rules.new()
	rules.ship_hit()
	rules.tick(1.0)
	assert_false(rules.ship_hit())
	assert_eq(rules.lives, 2)
	rules.tick(1.1)
	assert_true(rules.ship_hit())
	assert_eq(rules.lives, 1)


func test_the_game_is_over_at_zero_lives_not_one():
	var rules := Rules.new(2)
	rules.ship_hit()
	assert_eq(rules.lives, 1)
	assert_false(rules.is_game_over())
	rules.tick(Rules.INVULNERABLE_SECONDS + 0.1)
	rules.ship_hit()
	assert_true(rules.is_game_over())


func test_a_destroyed_enemy_scores_its_own_points():
	var rules := Rules.new()
	assert_eq(rules.hit_enemy({"hp": 1, "points": 150}), 150)
	assert_eq(rules.hit_enemy({"hp": 1, "points": 300}), 300)


func test_an_enemy_with_hp_left_scores_nothing_until_destroyed():
	var rules := Rules.new()
	var enemy := {"hp": 2, "points": 150}
	assert_eq(rules.hit_enemy(enemy), 0)
	assert_eq(enemy.hp, 1)
	assert_eq(rules.hit_enemy(enemy), 150)
