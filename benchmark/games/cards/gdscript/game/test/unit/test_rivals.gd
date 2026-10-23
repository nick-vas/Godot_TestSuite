extends GutTest
## Rivals: each has a name, a legal deck and an AI, and the player's deck can beat each of them.

var cards := Cards.from_file()
var rivals := Rivals.from_files()


func test_the_rivals_are_numbered_from_one():
	assert_gte(rivals.count(), 3)
	for id in range(1, rivals.count() + 1):
		assert_true(rivals.has_rival(id), "rival %d" % id)
		assert_string_starts_with(str(rivals.rival(id).name), "RIVAL_")


func test_every_deck_is_legal():
	assert_eq(Deck.problems(rivals.deck(Rivals.KEEPER_DECK), cards).size(), 0, "the keeper's deck")
	for id in range(1, rivals.count() + 1):
		var problems := Deck.problems(rivals.deck(str(rivals.rival(id).deck)), cards)
		assert_eq(problems.size(), 0, "rival %d: %s" % [id, ", ".join(problems)])


func test_every_rival_can_be_beaten_and_can_win():
	for id in range(1, rivals.count() + 1):
		var wins := 0
		for seed_value in range(1, 21):
			var winner := Ai.play_out(rivals.start_duel(cards, id, seed_value), [Ai.new(), rivals.ai_for(id)])
			assert_true(winner >= 0, "rival %d seed %d ended (%d)" % [id, seed_value, winner])
			if winner == 0:
				wins += 1
		assert_between(wins, 1, 19, "rival %d: the player won %d of 20" % [id, wins])
