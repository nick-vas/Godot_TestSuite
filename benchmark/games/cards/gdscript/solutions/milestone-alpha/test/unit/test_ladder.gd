extends GutTest
## Ladder: wins and losses per rival, and which rivals are open.


func test_rival_one_is_open_and_the_next_opens_when_it_is_beaten():
	var save := SaveStore.defaults()
	assert_true(Ladder.is_unlocked(save, 1))
	assert_false(Ladder.is_unlocked(save, 2))
	Ladder.record(save, 1, true)
	assert_true(Ladder.is_unlocked(save, 2))
	assert_false(Ladder.is_unlocked(save, 3))


func test_a_loss_opens_nothing_and_is_counted():
	var save := SaveStore.defaults()
	Ladder.record(save, 1, false)
	Ladder.record(save, 1, false)
	assert_false(Ladder.is_beaten(save, 1))
	assert_eq(Ladder.losses(save, 1), 2)
	assert_false(Ladder.is_unlocked(save, 2))


func test_wins_add_up_across_rivals():
	var save := SaveStore.defaults()
	Ladder.record(save, 1, true)
	Ladder.record(save, 1, true)
	Ladder.record(save, 2, true)
	Ladder.record(save, 3, false)
	assert_eq(Ladder.wins(save, 1), 2)
	assert_eq(Ladder.total_wins(save), 3)
