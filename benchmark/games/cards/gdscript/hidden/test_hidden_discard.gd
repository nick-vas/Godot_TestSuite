extends GutTest
## Hidden check for the alpha's fix-bug: a duel kept in the save comes back with both discard piles, in order, so
## Rekindle after Continue brings back the wisp that fell last.

const PATH := "user://test_hidden_discard.json"

var cards := Cards.from_file()
var rivals := Rivals.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _through_the_save(duel: Duel) -> Duel:
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	data.duel = duel.to_dict()
	assert_true(store.write(data))
	return Duel.from_dict(cards, store.read().duel)


func _duel_at_main() -> Duel:
	var duel := rivals.start_duel(cards, 2, 13)
	duel.advance()
	return duel


func test_hidden_both_discard_piles_come_back_in_order():
	var duel := _duel_at_main()
	duel.keepers[0].discard = ["reed_hound", "flare", "glow_imp", "mending_oil"] as Array[String]
	duel.keepers[1].discard = ["marsh_insight", "bog_warden"] as Array[String]
	var back := _through_the_save(duel)
	assert_eq(back.keepers[0].discard, duel.keepers[0].discard)
	assert_eq(back.keepers[1].discard, duel.keepers[1].discard)


func test_hidden_rekindle_after_continue_brings_back_the_last_fallen_wisp():
	var duel := _duel_at_main()
	duel.keepers[0].hand = ["rekindle"] as Array[String]
	duel.keepers[0].kindling = 2
	duel.keepers[0].discard = ["reed_hound", "glow_imp", "flare"] as Array[String]
	var back := _through_the_save(duel)
	assert_true(back.play(0, 0))
	assert_eq(back.keepers[0].hand, ["glow_imp"] as Array[String])
	assert_eq(back.keepers[0].discard, ["reed_hound", "flare", "rekindle"] as Array[String])


func test_hidden_a_duel_played_on_keeps_its_discards_through_the_save():
	var duel := rivals.start_duel(cards, 2, 21)
	var ais := [Ai.new(), rivals.ai_for(2)]
	while duel.turn < 9 and duel.phase != Duel.Phase.OVER:
		if duel.phase == Duel.Phase.MAIN:
			var index: int = ais[duel.active].choose(duel, duel.active)
			if index < 0 or not duel.play(duel.active, index):
				duel.end_main()
		else:
			duel.advance()
	assert_gt(duel.keepers[0].discard.size() + duel.keepers[1].discard.size(), 0, "cards were played")
	var back := _through_the_save(duel)
	for seat in 2:
		assert_eq(back.keepers[seat].discard, duel.keepers[seat].discard, "seat %d" % seat)
