extends GutTest
## The game scene: a shot on an enemy destroys it, scores, and the HUD shows it.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func test_level_one_starts_with_six_grunts():
	assert_eq(game.enemies.get_child_count(), 6)
	assert_eq(game.enemies.get_child(0).id, "grunt")


func test_a_shot_on_an_enemy_destroys_it_and_scores():
	var enemy: Node2D = game.enemies.get_child(0)
	game.spawn_shot(enemy.position, Vector2.ZERO, false)
	await wait_physics_frames(2)
	assert_eq(game.enemies.get_child_count(), 5)
	assert_eq(game.score.points, 100)


func test_the_hud_shows_the_new_score():
	var enemy: Node2D = game.enemies.get_child(0)
	game.spawn_shot(enemy.position, Vector2.ZERO, false)
	await wait_physics_frames(2)
	assert_string_contains(game.get_node("HUD/ScoreLabel").text, "100")
