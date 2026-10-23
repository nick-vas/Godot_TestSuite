extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: five rivals, each with a legal deck, each beaten by the player's
## deck in some seeded duels and none beaten in all of them.

var cards := Cards.from_file()
var rivals := Rivals.from_files()


func test_hidden_five_rivals_each_fair():
	assert_gte(rivals.count(), 5)
	for id in range(1, 6):
		var deck := rivals.deck(str(rivals.rival(id).deck))
		assert_eq(Deck.problems(deck, cards).size(), 0, "rival %d" % id)
		var wins := 0
		for seed_value in range(1, 21):
			if Ai.play_out(rivals.start_duel(cards, id, seed_value), [Ai.new(), rivals.ai_for(id)]) == 0:
				wins += 1
		assert_between(wins, 1, 19, "rival %d: the player won %d of 20" % [id, wins])
