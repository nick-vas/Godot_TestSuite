extends GutTest
## Rules: hearts, the invulnerability after a hurt, and what glowmoss scores.


func test_a_level_starts_with_three_hearts():
	var rules := Rules.new()
	rules.start_level(Vector3.ZERO)
	assert_eq(rules.hearts, 3)


func test_a_hurt_costs_a_heart_then_protects():
	var rules := Rules.new()
	assert_true(rules.hurt())
	assert_eq(rules.hearts, 2)
	assert_true(rules.is_invulnerable())
	assert_false(rules.hurt(), "a second hurt at once costs nothing")


func test_each_moss_is_worth_ten_points():
	var rules := Rules.new()
	for i in 3:
		rules.collect_moss()
	assert_eq(rules.score, 30)
	assert_eq(rules.moss, 3)
