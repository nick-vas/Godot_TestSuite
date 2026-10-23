extends GutTest
## Hidden check for the alpha's fix-bug: on a 16:9 screen the camera keeps the climber in view at the foot and the top
## of The Climb, and never shows past the level's edges. What the view shows is worked out here from Camera3D's own
## rule (an orthographic size is the height of the view), not from the game's code.

var _window_size: Vector2i
var game: Node3D


func before_each():
	_window_size = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func after_each():
	get_tree().root.size = _window_size


func _half_view() -> Vector2:
	var view: Vector2 = game.get_viewport().get_visible_rect().size
	var half_height: float = game.camera.size / 2.0
	return Vector2(half_height * view.x / view.y, half_height)


func _assert_climber_in_view(where: String) -> void:
	var half := _half_view()
	var camera: Vector3 = game.camera.position
	var feet: Vector3 = game.player.position
	assert_true(absf(feet.x - camera.x) <= half.x - 0.4, "%s: across, climber %.2f, view %.2f +- %.2f" % [where, feet.x, camera.x, half.x])
	assert_true(feet.y >= camera.y - half.y, "%s: feet %.2f above the bottom of the view %.2f" % [where, feet.y, camera.y - half.y])
	assert_true(feet.y + 1.0 <= camera.y + half.y, "%s: head %.2f below the top of the view %.2f" % [where, feet.y + 1.0, camera.y + half.y])


func test_hidden_the_climber_is_in_view_at_the_foot_of_the_climb():
	game.start_level(3)
	await wait_physics_frames(60)
	_assert_climber_in_view("the foot of the climb")


func test_hidden_the_climber_is_in_view_at_the_top_of_the_climb():
	game.start_level(3)
	var top := AABB()
	for box: AABB in game.current.platform_boxes():
		if box.end.y > top.end.y:
			top = box
	game.player.place(Vector3(top.get_center().x, top.end.y, 0))
	await wait_physics_frames(120)
	_assert_climber_in_view("the top of the climb")


func test_hidden_the_view_stays_inside_the_level():
	await wait_physics_frames(30)
	var half := _half_view()
	var bounds: AABB = game.current.bounds()
	assert_true(game.camera.position.x - half.x >= bounds.position.x - 0.01, "the view starts inside the level")
	assert_true(game.camera.position.y - half.y >= bounds.position.y - 0.01, "the view's bottom is inside the level")
	_assert_climber_in_view("the start of level 1")
