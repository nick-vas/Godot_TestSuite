extends GutTest
## Hidden check for the prototype's add-feature: fatigue costs 1, 2, 3... light per draw from an empty deck, counted in
## Keeper.fatigue for each keeper apart, and can end the duel at the Draw.

var cards := Cards.from_file()
var duel: Duel


func before_each():
	var deck := Rivals.from_files().deck(Rivals.KEEPER_DECK)
	duel = Duel.start(cards, [deck, deck], [20, 20], 5)


func test_hidden_each_empty_draw_costs_one_more():
	duel.keepers[0].deck.clear()
	var hand := duel.keepers[0].hand.size()
	for expected in [19, 17, 14, 10]:
		assert_false(duel.draw_card(0))
		assert_eq(duel.keepers[0].light, expected)
	assert_eq(duel.keepers[0].fatigue, 4)
	assert_eq(duel.keepers[0].hand.size(), hand)


func test_hidden_fatigue_is_counted_per_keeper():
	duel.keepers[0].deck.clear()
	duel.keepers[1].deck.clear()
	duel.draw_card(0)
	duel.draw_card(0)
	duel.draw_card(1)
	assert_eq(duel.keepers[0].fatigue, 2)
	assert_eq(duel.keepers[1].fatigue, 1)
	assert_eq(duel.keepers[1].light, 19)


func test_hidden_a_deck_with_cards_costs_nothing():
	duel.draw_card(0)
	assert_eq(duel.keepers[0].light, 20)
	assert_eq(duel.keepers[0].fatigue, 0)


func test_hidden_fatigue_ends_the_duel_at_the_draw():
	duel.keepers[0].deck.clear()
	duel.keepers[0].fatigue = 2
	duel.keepers[0].light = 3
	duel.advance()
	assert_eq(duel.keepers[0].light, 0)
	assert_eq(duel.phase, Duel.Phase.OVER)
	assert_eq(duel.winner, 1)
