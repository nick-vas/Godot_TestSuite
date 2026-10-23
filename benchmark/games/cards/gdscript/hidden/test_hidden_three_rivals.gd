extends GutTest
## Hidden acceptance for the alpha milestone: three rivals with legal decks, and a save that keeps the record and the
## duel in progress, discard piles included.

const PATH := "user://test_hidden_three_rivals.json"

var cards := Cards.from_file()
var rivals := Rivals.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_hidden_three_rivals_with_legal_decks():
	assert_gte(rivals.count(), 3)
	for id in [1, 2, 3]:
		assert_true(rivals.has_rival(id), "rival %d" % id)
		var deck := rivals.deck(str(rivals.rival(id).deck))
		assert_eq(Deck.problems(deck, cards).size(), 0, "rival %d: %s" % [id, ", ".join(Deck.problems(deck, cards))])
		var winner := Ai.play_out(rivals.start_duel(cards, id, 4), [Ai.new(), rivals.ai_for(id)])
		assert_true(winner == 0 or winner == 1, "rival %d's duel ends" % id)


func test_hidden_the_save_keeps_the_record_and_the_duel():
	var duel := rivals.start_duel(cards, 3, 8)
	duel.advance()
	duel.keepers[0].discard = ["glow_imp", "flare"] as Array[String]
	var store := SaveStore.new(PATH)
	var data := store.read()
	data.record["1"] = {"wins": 1, "losses": 2}
	data.duel = duel.to_dict()
	assert_true(store.write(data))
	var back := SaveStore.new(PATH).read()
	assert_eq(int(back.record["1"].wins), 1)
	assert_eq(int(back.record["1"].losses), 2)
	var restored := Duel.from_dict(cards, back.duel)
	assert_eq(restored.turn, duel.turn)
	assert_eq(restored.keepers[0].hand, duel.keepers[0].hand)
	assert_eq(restored.keepers[0].discard, duel.keepers[0].discard)
	assert_eq(restored.keepers[1].deck, duel.keepers[1].deck)
