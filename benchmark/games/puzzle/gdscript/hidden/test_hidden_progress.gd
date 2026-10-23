extends GutTest
## Hidden check for the alpha's fix-bug: solving levels keeps every earlier one with its best moves.


func test_hidden_three_levels_stay_solved():
	var save := SaveStore.defaults()
	Progress.record(save, 1, 3)
	Progress.record(save, 2, 6)
	Progress.record(save, 3, 7)
	for id in [1, 2, 3]:
		assert_true(Progress.is_solved(save, id), "level %d" % id)
	assert_true(Progress.is_unlocked(save, 4))
	assert_eq(Progress.best(save, 2), 6)


func test_hidden_a_worse_replay_keeps_the_best_and_the_others():
	var save := SaveStore.defaults()
	Progress.record(save, 1, 3)
	Progress.record(save, 2, 6)
	Progress.record(save, 1, 10)
	assert_eq(Progress.best(save, 1), 3)
	assert_eq(Progress.best(save, 2), 6)
