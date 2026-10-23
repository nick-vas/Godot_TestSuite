extends GutTest
## Hidden check for the beta's fix-performance: the AI is asked for the player's suggestion once per change, not every
## frame, and the suggestion is still the card the AI would play.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.start_rival(1, 7)
	await wait_physics_frames(30)


func _playable() -> int:
	for index in game.duel.keepers[0].hand.size():
		if game.duel.can_play(0, index):
			return index
	return -1


func test_hidden_an_idle_turn_asks_at_most_once():
	assert_eq(game.phase, "Main")
	var before: int = game.suggest_checks
	await wait_physics_frames(120)
	assert_lte(game.suggest_checks - before, 1)


func test_hidden_a_play_asks_once_or_twice():
	game.duel.keepers[0].kindling = 6
	var index := _playable()
	assert_gte(index, 0)
	var before: int = game.suggest_checks
	assert_true(game.play_card(index))
	await wait_physics_frames(10)
	assert_between(game.suggest_checks - before, 1, 2)


func test_hidden_the_suggestion_is_still_shown():
	game.duel.keepers[0].kindling = 6
	game.play_card(_playable())
	await wait_physics_frames(2)
	assert_eq(game.suggested, Ai.new().choose(game.duel, 0))
	if game.suggested >= 0:
		assert_eq(game.get_node("HUD/Hand/Card%d" % game.suggested).modulate, Color(1.0, 0.92, 0.55))


func test_hidden_the_rivals_turn_asks_little():
	var before: int = game.suggest_checks
	game.end_turn()
	for i in 900:
		await wait_physics_frames(1)
		if game.turn == 3 and game.phase == "Main":
			break
	assert_eq(game.turn, 3)
	assert_lte(game.suggest_checks - before, 3)
