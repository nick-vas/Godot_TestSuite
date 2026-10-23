extends GutTest
## Hidden check for the beta's fix-bug: a seed always deals the same cards, whatever the global generator did before,
## seeds that differ deal differently, and shuffling leaves the global generator alone.

var cards := Cards.from_file()
var rivals := Rivals.from_files()


func _deal(seed_value: int) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Deck.shuffled(rivals.deck(Rivals.KEEPER_DECK), rng)


func test_hidden_the_same_seed_deals_the_same_in_any_order():
	var first := _deal(2026)
	randomize()
	_deal(5)
	randomize()
	assert_eq(_deal(2026), first)


func test_hidden_two_duels_with_one_seed_deal_the_same_hands():
	var first := rivals.start_duel(cards, 3, 77)
	randomize()
	var second := rivals.start_duel(cards, 3, 77)
	for seat in 2:
		assert_eq(second.keepers[seat].hand, first.keepers[seat].hand, "seat %d hand" % seat)
		assert_eq(second.keepers[seat].deck, first.keepers[seat].deck, "seat %d deck" % seat)


func test_hidden_seeds_that_differ_deal_differently():
	var seen := {}
	for seed_value in range(100, 130):
		seen["/".join(PackedStringArray(_deal(seed_value)))] = true
	assert_gt(seen.size(), 25)


func test_hidden_shuffling_leaves_the_global_generator_alone():
	seed(99)
	var expected := randi()
	seed(99)
	_deal(7)
	rivals.start_duel(cards, 1, 8)
	assert_eq(randi(), expected)
