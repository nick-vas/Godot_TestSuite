extends GutTest
## Deck: the shuffle follows the seed and nothing else, and what makes a deck legal.

## The top six cards of the keeper deck shuffled with seed 7: a C# port shuffling the same way deals the same.
const PINNED_7: Array[String] = ["flare", "lantern_heron", "rekindle", "flare", "ember_mote", "mending_oil"]

var cards := Cards.from_file()
var keeper_deck := Rivals.from_files().deck(Rivals.KEEPER_DECK)


func _shuffled(seed_value: int) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Deck.shuffled(keeper_deck, rng)


func test_a_seed_always_deals_the_same_deck():
	assert_eq(_shuffled(42), _shuffled(42))


func test_seed_7_deals_this_order():
	var top := _shuffled(7).slice(0, 6)
	assert_eq(top, PINNED_7)


func test_different_seeds_deal_differently():
	var seen := {}
	for seed_value in range(1, 21):
		seen["/".join(PackedStringArray(_shuffled(seed_value)))] = true
	assert_gt(seen.size(), 18)


func test_a_shuffle_keeps_every_card():
	var sorted_before := keeper_deck.duplicate()
	sorted_before.sort()
	var after := _shuffled(3)
	after.sort()
	assert_eq(after, sorted_before)


func test_a_deck_with_a_third_copy_or_too_few_cards_is_not_legal():
	assert_eq(Deck.problems(keeper_deck, cards).size(), 0)
	var bad := keeper_deck.duplicate()
	bad[0] = "flare"
	assert_eq(Deck.problems(bad, cards), PackedStringArray(["3 copies of flare"]))
	assert_eq(Deck.problems(keeper_deck.slice(1), cards), PackedStringArray(["19 cards, not 20"]))
