extends GutTest
## Hidden check for the beta's fix-performance: a pass over 200 shots and 60 enemies tests only the pairs that can
## touch, and still finds every hit.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(1)
	game.set_physics_process(false)
	for child: Node in game.enemies.get_children():
		game.enemies.remove_child(child)
		child.free()
	for child: Node in game.shots.get_children():
		game.shots.remove_child(child)
		child.free()


func _grid_of_enemies() -> Array:
	var row := {"id": "grunt", "hp": 1, "points": 100, "drift": 0, "fire": 0, "color": "#e05050", "boss": false}
	var placed := []
	for r in 6:
		for c in 10:
			placed.append(game.spawn_enemy(row, 0.0, Vector2(100.0 + c * 120.0, 80.0 + r * 60.0)))
	return placed


func test_hidden_few_checks_for_many_shots():
	_grid_of_enemies()
	# 200 shots spread over the screen below the formation, where none of them touches an enemy.
	for i in 200:
		game.spawn_shot(Vector2(20.0 + (i % 40) * 31.0, 500.0 + (i / 40) * 30.0), Vector2.ZERO, false)
	game.collision_checks = 0
	game.resolve_shot_hits()
	assert_lt(game.collision_checks, 2000, "shot-against-enemy checks for one pass")
	assert_eq(game.enemies.get_child_count(), 60, "no enemy was hit")


func test_hidden_every_hit_is_still_found():
	var placed := _grid_of_enemies()
	for i in range(0, 60, 7):
		game.spawn_shot(placed[i].position + Vector2(3, 0), Vector2.ZERO, false)
	# A shot on the edge between two columns of the screen.
	game.spawn_shot(placed[2].position + Vector2(-22, 0), Vector2.ZERO, false)
	game.resolve_shot_hits()
	assert_eq(game.enemies.get_child_count(), 60 - 10)
	assert_eq(game.score.combo, 10)
