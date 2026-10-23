extends GutTest
## Progress: solving levels keeps the earlier ones, a worse replay keeps the best, and levels open one by one.


func test_solving_a_level_keeps_the_levels_solved_before():
	var save := SaveStore.defaults()
	Progress.record(save, 1, 3)
	Progress.record(save, 2, 6)
	assert_true(Progress.is_solved(save, 1))
	assert_true(Progress.is_solved(save, 2))
	assert_eq(Progress.best(save, 1), 3)


func test_a_worse_replay_keeps_the_best():
	var save := SaveStore.defaults()
	assert_true(Progress.record(save, 1, 4))
	assert_false(Progress.record(save, 1, 9))
	assert_eq(Progress.best(save, 1), 4)


func test_a_better_replay_is_the_new_best():
	var save := SaveStore.defaults()
	Progress.record(save, 1, 9)
	assert_true(Progress.record(save, 1, 4))
	assert_eq(Progress.best(save, 1), 4)


func test_levels_open_one_after_another():
	var save := SaveStore.defaults()
	assert_true(Progress.is_unlocked(save, 1))
	assert_false(Progress.is_unlocked(save, 2))
	Progress.record(save, 1, 3)
	assert_true(Progress.is_unlocked(save, 2))
	assert_false(Progress.is_unlocked(save, 3))


func test_the_total_adds_up_the_best_moves():
	var save := SaveStore.defaults()
	Progress.record(save, 1, 3)
	Progress.record(save, 2, 7)
	assert_eq(Progress.total_moves(save), 10)
