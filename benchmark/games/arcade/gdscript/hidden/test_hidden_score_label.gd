extends GutTest
## Hidden check for the alpha's fix-architecture: the HUD's score still follows the score, also once a wave is gone.


func test_hidden_score_label_follows_points():
	var game: Node2D = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	var enemy: Node2D = game.enemies.get_child(0)
	game.spawn_shot(enemy.position, Vector2.ZERO, false)
	await wait_physics_frames(3)
	assert_eq(game.score.points, 100)
	assert_string_contains(game.get_node("HUD/ScoreLabel").text, "100")


func test_hidden_score_label_updates_with_no_enemies_left():
	var game: Node2D = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	for enemy: Node2D in game.enemies.get_children():
		game.enemies.remove_child(enemy)
		enemy.free()
	game.score.hit(250)
	await wait_physics_frames(2)
	assert_string_contains(game.get_node("HUD/ScoreLabel").text, "250")
