extends GutTest
## Hidden check for the alpha's add-content: rival 4, The Heron Knight, with a legal deck that leans on big wisps, 21
## light, an aggressive AI, and a fair fight: in duels 1 to 20 the player's deck wins at least 5 and loses at least 2.

var cards := Cards.from_file()
var rivals := Rivals.from_files()


func after_each():
	TranslationServer.set_locale("en")


func test_hidden_rival_4_is_the_heron_knight():
	assert_true(rivals.has_rival(4))
	var entry := rivals.rival(4)
	TranslationServer.set_locale("en")
	assert_eq(TranslationServer.translate(str(entry.name)), "The Heron Knight")
	assert_eq(int(entry.light), 21)
	assert_gt(float(entry.aggression), 1.0)


func test_hidden_its_own_deck_is_legal_and_leans_on_big_wisps():
	var deck_id := str(rivals.rival(4).deck)
	assert_ne(deck_id, Rivals.KEEPER_DECK)
	for id in [1, 2, 3]:
		assert_ne(deck_id, str(rivals.rival(id).deck), "rival %d's deck" % id)
	var deck := rivals.deck(deck_id)
	assert_eq(Deck.problems(deck, cards).size(), 0, ", ".join(Deck.problems(deck, cards)))
	var big := 0
	for id in deck:
		var card := cards.card(id)
		if card.kind == Cards.WISP and card.cost >= 4:
			big += 1
	assert_gte(big, 4)


func test_hidden_the_fight_is_fair():
	var wins := 0
	for seed_value in range(1, 21):
		var winner := Ai.play_out(rivals.start_duel(cards, 4, seed_value), [Ai.new(), rivals.ai_for(4)])
		assert_true(winner >= 0, "seed %d ended" % seed_value)
		if winner == 0:
			wins += 1
	assert_between(wins, 5, 18, "the player won %d of 20" % wins)
