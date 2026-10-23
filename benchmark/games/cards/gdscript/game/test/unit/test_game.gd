extends GutTest
## The game scene: a duel paced on the table, the player's hand, End turn and the result panel.

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


func test_the_duel_waits_for_the_player_in_main():
	assert_eq(game.phase, "Main")
	assert_eq(game.active, 0)
	assert_eq(game.get_node("HUD/Hand").get_child_count(), game.duel.keepers[0].hand.size())
	assert_false(game.get_node("HUD/EndTurnButton").disabled)
	await wait_physics_frames(60)
	assert_eq(game.phase, "Main", "still waiting")


func test_a_card_button_plays_its_card():
	var index := _playable()
	assert_gte(index, 0, "something to play")
	var before: int = game.duel.keepers[0].hand.size()
	game.get_node("HUD/Hand/Card%d" % index).pressed.emit()
	assert_eq(game.duel.keepers[0].hand.size(), before - 1)
	assert_eq(game.get_node("HUD/Hand").get_child_count(), before - 1)


func test_end_turn_passes_to_the_rival_and_back():
	game.get_node("HUD/EndTurnButton").pressed.emit()
	assert_ne(game.phase, "Main")
	for i in 600:
		await wait_physics_frames(1)
		if game.active == 0 and game.phase == "Main":
			break
	assert_eq(game.turn, 3)
	assert_eq(game.phase, "Main")


func test_a_lost_duel_shows_the_result_panel():
	game.duel.keepers[0].light = 1
	game.duel.keepers[1].row[0] = {"id": "lantern_heron", "power": 5, "guard": 5}
	game.end_turn()
	for i in 600:
		await wait_physics_frames(1)
		if game.state == "over":
			break
	assert_eq(game.state, "over")
	assert_eq(game.duel.winner, 1)
	assert_true(game.get_node("ResultMenu").visible)
	assert_false(game.get_node("ResultMenu/Box/NextButton").visible)
