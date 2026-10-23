extends GutTest
## A duel kept in the save comes back as it was, so Continue carries on where the player stopped.

const PATH := "user://test_duel_save.json"

var cards := Cards.from_file()
var rivals := Rivals.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


## A duel played by two AIs up to the player's Main phase of turn 7.
func _duel_in_play() -> Duel:
	var duel := rivals.start_duel(cards, 2, 21)
	var ais := [Ai.new(), rivals.ai_for(2)]
	while not (duel.turn == 7 and duel.phase == Duel.Phase.MAIN):
		if duel.phase == Duel.Phase.MAIN:
			var index: int = ais[duel.active].choose(duel, duel.active)
			if index < 0:
				duel.end_main()
			else:
				duel.play(duel.active, index)
		else:
			duel.advance()
	return duel


func test_a_saved_duel_comes_back_with_its_hands_decks_rows_and_light():
	var duel := _duel_in_play()
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	data.duel = duel.to_dict()
	assert_true(store.write(data))
	var back := Duel.from_dict(cards, store.read().duel)
	assert_eq(back.turn, 7)
	assert_eq(back.phase, Duel.Phase.MAIN)
	assert_eq(back.active, 0)
	for seat in 2:
		assert_eq(back.keepers[seat].light, duel.keepers[seat].light, "seat %d light" % seat)
		assert_eq(back.keepers[seat].kindling, duel.keepers[seat].kindling, "seat %d kindling" % seat)
		assert_eq(back.keepers[seat].hand, duel.keepers[seat].hand, "seat %d hand" % seat)
		assert_eq(back.keepers[seat].deck, duel.keepers[seat].deck, "seat %d deck" % seat)
		assert_eq(back.keepers[seat].row, duel.keepers[seat].row, "seat %d row" % seat)


func test_a_restored_duel_plays_on_to_its_end():
	var back := Duel.from_dict(cards, _duel_in_play().to_dict())
	var winner := Ai.play_out(back, [Ai.new(), rivals.ai_for(2)])
	assert_true(winner == 0 or winner == 1, "winner %d" % winner)
