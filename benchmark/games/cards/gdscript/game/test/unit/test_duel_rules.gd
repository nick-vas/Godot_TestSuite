extends GutTest
## The duel's core rules, each pinned by a test: kindling, lanes, strikes, the discard pile and the hand limit.

var cards := Cards.from_file()
var duel: Duel


func before_each():
	var deck := Rivals.from_files().deck(Rivals.KEEPER_DECK)
	duel = Duel.start(cards, [deck, deck], [20, 20], 11)


func _wisp(id: String) -> Dictionary:
	var card := cards.card(id)
	return {"id": id, "power": card.power, "guard": card.guard}


func _main_with(hand: Array[String], kindling: int) -> void:
	duel.advance()
	duel.keepers[0].hand = hand
	duel.keepers[0].kindling = kindling


func test_a_card_costing_more_than_the_kindling_left_cannot_be_played():
	_main_with(["reed_hound", "fen_stalker"], 4)
	assert_true(duel.play(0, 0))
	assert_eq(duel.keepers[0].kindling, 2)
	assert_false(duel.can_play(0, 0), "4 to pay with 2 left")
	assert_false(duel.play(0, 0))
	assert_eq(duel.keepers[0].hand, ["fen_stalker"] as Array[String])


func test_kindling_is_the_turn_number_up_to_six():
	var seen: Array[int] = []
	for i in 8:
		duel.advance()
		seen.append(duel.keepers[duel.active].kindling)
		duel.end_main()
		while duel.phase != Duel.Phase.DRAW:
			duel.advance()
		duel.advance()
		duel.end_main()
		while duel.phase != Duel.Phase.DRAW:
			duel.advance()
	assert_eq(seen, [1, 2, 3, 4, 5, 6, 6, 6] as Array[int])


func test_a_wisp_takes_the_first_free_lane_and_none_fits_a_full_row():
	_main_with(["ember_mote", "ember_mote", "reed_hound", "glow_imp"], 6)
	duel.keepers[0].row[0] = _wisp("bog_warden")
	assert_true(duel.play(0, 0))
	assert_eq(duel.keepers[0].row[1].id, "ember_mote")
	assert_true(duel.play(0, 0))
	assert_eq(duel.keepers[0].row[2].id, "ember_mote")
	assert_false(duel.can_play(0, 0), "the row is full")
	assert_false(duel.play(0, 0))
	assert_eq(duel.keepers[0].hand.size(), 2)


func test_wisps_across_strike_each_other():
	_main_with([], 1)
	duel.keepers[0].row[0] = _wisp("fen_stalker")
	duel.keepers[1].row[0] = _wisp("bog_warden")
	duel.end_main()
	duel.advance()
	assert_eq(duel.keepers[1].row[0].guard, 2, "the warden took 4")
	assert_eq(duel.keepers[0].row[0].guard, 2, "the stalker took 1")
	assert_eq(duel.keepers[1].light, 20)


func test_a_fallen_wisp_goes_to_the_discard_pile():
	_main_with([], 1)
	duel.keepers[0].row[1] = _wisp("glow_imp")
	duel.keepers[1].row[1] = _wisp("reed_hound")
	duel.end_main()
	duel.advance()
	assert_null(duel.keepers[0].row[1], "the imp fell")
	assert_null(duel.keepers[1].row[1], "the hound fell")
	assert_eq(duel.keepers[0].discard, ["glow_imp"] as Array[String])
	assert_eq(duel.keepers[1].discard, ["reed_hound"] as Array[String])


func test_an_unblocked_wisp_strikes_the_keeper():
	_main_with([], 1)
	duel.keepers[0].row[2] = _wisp("lantern_heron")
	duel.keepers[1].row[0] = _wisp("bog_warden")
	duel.end_main()
	duel.advance()
	assert_eq(duel.keepers[1].light, 15)
	assert_eq(duel.keepers[1].row[0].guard, 6, "the warden in another lane is untouched")


func test_a_card_drawn_into_a_full_hand_is_discarded():
	var top := duel.keepers[0].deck[0]
	duel.keepers[0].hand = ["flare", "flare", "douse", "douse", "rekindle", "rekindle", "glow_imp"] as Array[String]
	duel.advance()
	assert_eq(duel.keepers[0].hand.size(), Duel.HAND_MAX)
	assert_eq(duel.keepers[0].discard, [top] as Array[String])


func test_the_duel_ends_when_a_light_reaches_zero():
	_main_with([], 1)
	duel.keepers[0].row[0] = _wisp("glow_imp")
	duel.keepers[1].light = 3
	duel.end_main()
	duel.advance()
	assert_eq(duel.keepers[1].light, 0)
	assert_eq(duel.phase, Duel.Phase.OVER)
	assert_eq(duel.winner, 0)
