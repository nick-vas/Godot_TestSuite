extends GutTest
## Rules: checkpoints, and where a fall brings the climber back.


func test_before_any_checkpoint_a_fall_returns_to_the_start():
	var rules := Rules.new()
	rules.start_level(Vector3(1, 0, 0))
	rules.fell()
	assert_eq(rules.respawn_point(), Vector3(1, 0, 0))
	assert_eq(rules.hearts, 2)


func test_the_furthest_checkpoint_is_kept():
	var rules := Rules.new()
	rules.start_level(Vector3(1, 0, 0))
	assert_true(rules.reach_checkpoint(Vector3(20, 1, 0)))
	assert_false(rules.reach_checkpoint(Vector3(10, 1, 0)), "going back does not move the checkpoint")
	assert_eq(rules.respawn_point(), Vector3(20, 1, 0))


func test_a_new_level_forgets_the_checkpoint():
	var rules := Rules.new()
	rules.start_level(Vector3(1, 0, 0))
	rules.reach_checkpoint(Vector3(20, 1, 0))
	rules.start_level(Vector3(2, 0, 0))
	assert_eq(rules.respawn_point(), Vector3(2, 0, 0))
