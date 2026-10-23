extends GutTest
## Ai: it plays only what the rules allow, passes when nothing is worth it, and its weights show in its choices.

var cards := Cards.from_file()
var rivals := Rivals.from_files()
var duel: Duel


func before_each():
	duel = rivals.start_duel(cards, 1, 9)
	duel.advance()


func _set_hand(hand: Array[String], kindling: int) -> void:
	duel.keepers[0].hand = hand
	duel.keepers[0].kindling = kindling


func test_the_ai_only_chooses_cards_it_can_pay_for():
	_set_hand(["lantern_heron", "fen_stalker", "ember_mote"], 2)
	assert_eq(Ai.new().choose(duel, 0), 2)


func test_the_ai_passes_when_nothing_can_be_played():
	_set_hand(["lantern_heron", "douse"], 4)
	assert_eq(Ai.new().choose(duel, 0), -1, "a heron it cannot pay for, nothing to douse")


func test_the_ai_takes_a_winning_flare():
	_set_hand(["lantern_heron", "flare"], 6)
	duel.keepers[1].light = 3
	assert_eq(Ai.new().choose(duel, 0), 1)


func test_the_ai_never_mends_at_full_light_and_mends_when_low():
	_set_hand(["mending_oil"], 2)
	assert_eq(Ai.new().choose(duel, 0), -1)
	duel.keepers[0].light = 6
	assert_eq(Ai.new().choose(duel, 0), 0)


func test_caution_values_a_wall_more_than_aggression_does():
	_set_hand(["bog_warden"], 3)
	assert_gt(Ai.new(0.5, 2.0).score(duel, 0, 0), Ai.new(2.0, 0.5).score(duel, 0, 0))


func test_two_ais_play_a_duel_to_its_end():
	var winner := Ai.play_out(rivals.start_duel(cards, 1, 3), [Ai.new(), rivals.ai_for(1)])
	assert_true(winner == 0 or winner == 1, "winner %d" % winner)
