extends GutTest
## A turn as named phases, one test per transition: Draw -> Main -> Clash (or End when there is nothing to strike
## with) -> End -> the other keeper's Draw, and Over once a light is out.

var cards := Cards.from_file()
var duel: Duel


func before_each():
	var deck := Rivals.from_files().deck(Rivals.KEEPER_DECK)
	duel = Duel.start(cards, [deck, deck], [20, 20], 7)


func _wisp(id: String) -> Dictionary:
	var card := cards.card(id)
	return {"id": id, "power": card.power, "guard": card.guard}


func test_a_duel_opens_on_the_first_keepers_draw():
	assert_eq(duel.phase, Duel.Phase.DRAW)
	assert_eq(duel.active, 0)
	assert_eq(duel.turn, 1)
	assert_eq(duel.keepers[0].hand.size(), Duel.HAND_START)
	assert_eq(duel.keepers[1].hand.size(), Duel.HAND_START)


func test_draw_gives_kindling_and_a_card_then_main():
	duel.advance()
	assert_eq(duel.phase, Duel.Phase.MAIN)
	assert_eq(duel.keepers[0].kindling, 1)
	assert_eq(duel.keepers[0].hand.size(), Duel.HAND_START + 1)


func test_main_goes_to_clash_when_the_keeper_has_wisps():
	duel.advance()
	duel.keepers[0].row[0] = _wisp("reed_hound")
	duel.keepers[1].row[0] = _wisp("bog_warden")
	duel.end_main()
	assert_eq(duel.phase, Duel.Phase.CLASH)


func test_main_skips_clash_when_no_wisp_can_strike():
	duel.advance()
	duel.end_main()
	assert_eq(duel.phase, Duel.Phase.END)


func test_clash_strikes_each_lane_then_ends():
	duel.advance()
	duel.keepers[0].row = [_wisp("reed_hound"), null, _wisp("glow_imp")]
	duel.keepers[1].row = [_wisp("bog_warden"), null, null]
	duel.end_main()
	duel.advance()
	assert_eq(duel.keepers[1].row[0].guard, 4, "lane 0 struck the warden")
	assert_eq(duel.phase, Duel.Phase.CLASH)
	duel.advance()
	assert_eq(duel.keepers[1].light, 17, "lane 2 struck the rival")
	duel.advance()
	assert_eq(duel.phase, Duel.Phase.END)


func test_end_passes_the_turn_to_the_other_keeper():
	duel.advance()
	duel.end_main()
	duel.advance()
	assert_eq(duel.phase, Duel.Phase.DRAW)
	assert_eq(duel.active, 1)
	assert_eq(duel.turn, 2)


func test_a_light_put_out_ends_the_duel():
	duel.advance()
	duel.keepers[0].row[1] = _wisp("lantern_heron")
	duel.keepers[1].light = 4
	duel.end_main()
	duel.advance()
	assert_eq(duel.phase, Duel.Phase.OVER)
	assert_eq(duel.winner, 0)
	duel.advance()
	assert_eq(duel.phase, Duel.Phase.OVER, "nothing moves an ended duel")
