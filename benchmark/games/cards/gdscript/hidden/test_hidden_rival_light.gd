extends GutTest
## Hidden check for the alpha's fix-architecture: the HUD's rival light follows a Flare, a Clash and a new duel.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.start_rival(1, 7)
	await wait_physics_frames(30)


func _light_text() -> String:
	return game.get_node("HUD/RivalLight").text


func test_hidden_the_rival_light_follows_a_flare():
	assert_eq(game.phase, "Main")
	game.duel.keepers[0].hand.append("flare")
	game.duel.keepers[0].kindling = 2
	assert_true(game.play_card(game.duel.keepers[0].hand.size() - 1))
	await wait_physics_frames(2)
	assert_eq(_light_text(), "Light: 9")


func test_hidden_the_rival_light_follows_a_clash():
	game.duel.keepers[0].row[0] = {"id": "lantern_heron", "power": 5, "guard": 5}
	game.end_turn()
	await wait_physics_frames(30)
	assert_eq(game.duel.keepers[1].light, 7)
	assert_eq(_light_text(), "Light: 7")


func test_hidden_a_new_duel_shows_its_rivals_light():
	game.start_rival(2, 3)
	await wait_physics_frames(2)
	assert_eq(_light_text(), "Light: 15")
