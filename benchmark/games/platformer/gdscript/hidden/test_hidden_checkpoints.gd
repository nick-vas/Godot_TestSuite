extends GutTest
## Hidden check for the prototype's add-feature: checkpoints in Rules.


func test_hidden_respawn_is_the_start_before_any_checkpoint():
	var rules := Rules.new()
	rules.start_level(Vector3(2, 1, 0))
	assert_eq(rules.respawn_point(), Vector3(2, 1, 0))


func test_hidden_a_further_checkpoint_is_kept_and_a_nearer_one_is_not():
	var rules := Rules.new()
	rules.start_level(Vector3(2, 1, 0))
	assert_true(rules.reach_checkpoint(Vector3(30, 4, 0)))
	assert_eq(rules.respawn_point(), Vector3(30, 4, 0))
	assert_false(rules.reach_checkpoint(Vector3(12, 1, 0)))
	assert_false(rules.reach_checkpoint(Vector3(30, 4, 0)), "the same checkpoint again is not new")
	assert_eq(rules.respawn_point(), Vector3(30, 4, 0))


func test_hidden_start_level_resets_the_checkpoint():
	var rules := Rules.new()
	rules.start_level(Vector3(2, 1, 0))
	rules.reach_checkpoint(Vector3(30, 4, 0))
	rules.start_level(Vector3(5, 0, 0))
	assert_eq(rules.respawn_point(), Vector3(5, 0, 0))
	assert_eq(rules.hearts, Rules.START_HEARTS)
