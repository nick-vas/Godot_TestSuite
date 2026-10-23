extends GutTest
## Hidden check for the prototype's fix-bug: Main goes to Clash whenever the active keeper has a wisp, whatever the
## other row holds, and skips it when the active keeper has none, whatever the other row holds.

var cards := Cards.from_file()
var duel: Duel


func before_each():
	var deck := Rivals.from_files().deck(Rivals.KEEPER_DECK)
	duel = Duel.start(cards, [deck, deck], [20, 20], 3)
	duel.advance()


func _wisp(id: String) -> Dictionary:
	var card := cards.card(id)
	return {"id": id, "power": card.power, "guard": card.guard}


func test_hidden_wisps_strike_a_rival_whose_row_is_empty():
	duel.keepers[0].row[0] = _wisp("reed_hound")
	duel.keepers[0].row[2] = _wisp("glow_imp")
	duel.end_main()
	assert_eq(duel.phase, Duel.Phase.CLASH)
	duel.advance()
	duel.advance()
	assert_eq(duel.keepers[1].light, 15)
	duel.advance()
	assert_eq(duel.phase, Duel.Phase.END)


func test_hidden_the_rivals_wisps_strike_an_empty_row_too():
	duel.end_main()
	duel.advance()
	duel.advance()
	assert_eq(duel.active, 1)
	assert_eq(duel.phase, Duel.Phase.MAIN)
	duel.keepers[1].row[1] = _wisp("fen_stalker")
	duel.end_main()
	assert_eq(duel.phase, Duel.Phase.CLASH)
	duel.advance()
	assert_eq(duel.keepers[0].light, 16)


func test_hidden_no_wisp_of_ones_own_skips_the_clash_even_facing_wisps():
	duel.keepers[1].row[0] = _wisp("bog_warden")
	duel.end_main()
	assert_eq(duel.phase, Duel.Phase.END)
	assert_eq(duel.keepers[1].row[0].guard, 6)
