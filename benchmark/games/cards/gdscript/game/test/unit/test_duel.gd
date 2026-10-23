extends GutTest
## Duel: what each rite does when played, once.

var cards := Cards.from_file()


func _at_main(hand: Array[String]) -> Duel:
	var deck := Rivals.from_files().deck(Rivals.KEEPER_DECK)
	var duel := Duel.start(cards, [deck, deck], [20, 20], 7)
	duel.keepers[0].hand = hand
	duel.keepers[0].kindling = 6
	duel.phase = Duel.Phase.MAIN
	return duel


func test_flare_burns_the_rival_for_three():
	var duel := _at_main(["flare"])
	assert_true(duel.play(0, 0))
	assert_eq(duel.keepers[1].light, 17)


func test_mending_oil_restores_light_up_to_the_start():
	var duel := _at_main(["mending_oil", "mending_oil"])
	duel.keepers[0].light = 14
	duel.play(0, 0)
	assert_eq(duel.keepers[0].light, 18)
	duel.play(0, 0)
	assert_eq(duel.keepers[0].light, 20)


func test_marsh_insight_draws_two():
	var duel := _at_main(["marsh_insight"])
	var deck_before := duel.keepers[0].deck.size()
	duel.play(0, 0)
	assert_eq(duel.keepers[0].hand.size(), 2)
	assert_eq(duel.keepers[0].deck.size(), deck_before - 2)


func test_douse_puts_out_the_strongest_wisp_across():
	var duel := _at_main(["douse"])
	duel.keepers[1].row = [{"id": "reed_hound", "power": 2, "guard": 3}, {"id": "fen_stalker", "power": 4, "guard": 3}, null]
	duel.play(0, 0)
	assert_null(duel.keepers[1].row[1])
	assert_not_null(duel.keepers[1].row[0])
	assert_eq(duel.keepers[1].discard, ["fen_stalker"] as Array[String])


func test_rekindle_returns_the_newest_fallen_wisp():
	var duel := _at_main(["rekindle"])
	duel.keepers[0].discard = ["glow_imp", "flare", "reed_hound", "mending_oil"] as Array[String]
	duel.play(0, 0)
	assert_eq(duel.keepers[0].hand, ["reed_hound"] as Array[String])
	assert_eq(duel.keepers[0].discard, ["glow_imp", "flare", "mending_oil", "rekindle"] as Array[String])


func test_a_rite_with_nothing_to_act_on_cannot_be_played():
	var duel := _at_main(["douse", "rekindle"])
	assert_false(duel.can_play(0, 0), "douse with no wisp across")
	assert_false(duel.can_play(0, 1), "rekindle with no fallen wisp")
	assert_false(duel.play(0, 0))
	assert_eq(duel.keepers[0].hand.size(), 2)
