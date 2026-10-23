extends GutTest
## Fatigue: an empty deck costs light, more each time, so every duel ends.

var cards := Cards.from_file()
var duel: Duel


func before_each():
	var deck := Rivals.from_files().deck(Rivals.KEEPER_DECK)
	duel = Duel.start(cards, [deck, deck], [20, 20], 5)
	duel.keepers[0].deck.clear()


func test_each_draw_from_an_empty_deck_costs_one_more_light():
	assert_false(duel.draw_card(0))
	assert_eq(duel.keepers[0].light, 19)
	duel.draw_card(0)
	duel.draw_card(0)
	assert_eq(duel.keepers[0].light, 14)
	assert_eq(duel.keepers[0].fatigue, 3)
	assert_eq(duel.keepers[0].hand.size(), Duel.HAND_START)


func test_fatigue_can_put_out_a_light_at_the_draw():
	duel.keepers[0].light = 1
	duel.advance()
	assert_eq(duel.phase, Duel.Phase.OVER)
	assert_eq(duel.winner, 1)
