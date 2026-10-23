extends GutTest
## Hidden check for the beta's fix-playthrough: the AI only ever chooses a play the rules allow, in every position of
## many seeded duels against every rival, and it never plays a wisp into a full row.

var cards := Cards.from_file()
var rivals := Rivals.from_files()


func test_hidden_every_choice_is_legal_through_whole_duels():
	var checked := 0
	for id in range(1, rivals.count() + 1):
		for seed_value in range(1, 9):
			var duel := rivals.start_duel(cards, id, seed_value)
			var ais := [Ai.new(), rivals.ai_for(id)]
			for step in 4000:
				if duel.phase == Duel.Phase.OVER:
					break
				if duel.phase != Duel.Phase.MAIN:
					duel.advance()
					continue
				var index: int = ais[duel.active].choose(duel, duel.active)
				checked += 1
				if index >= 0 and not duel.can_play(duel.active, index):
					fail_test("rival %d seed %d turn %d: seat %d chose %s, which the rules refuse" % [id, seed_value, duel.turn, duel.active, duel.keepers[duel.active].hand[index]])
					return
				if index < 0:
					duel.end_main()
				else:
					duel.play(duel.active, index)
			assert_eq(duel.phase, Duel.Phase.OVER, "rival %d seed %d ended" % [id, seed_value])
	assert_gt(checked, 500)


func test_hidden_a_full_row_is_never_played_into():
	var duel := rivals.start_duel(cards, 2, 5)
	duel.advance()
	for lane in Keeper.LANES:
		duel.keepers[0].row[lane] = {"id": "ember_mote", "power": 1, "guard": 2}
	duel.keepers[0].kindling = 6
	duel.keepers[0].hand = ["lantern_heron", "flare"] as Array[String]
	assert_eq(Ai.new().choose(duel, 0), 1)
	duel.keepers[0].hand = ["lantern_heron", "fen_stalker"] as Array[String]
	assert_eq(Ai.new().choose(duel, 0), -1)
