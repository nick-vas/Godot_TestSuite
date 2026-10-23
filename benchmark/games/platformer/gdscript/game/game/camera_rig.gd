class_name CameraRig
extends Camera3D
## The side view (orthographic). It looks ahead in the direction the climber faces, follows vertically when the climber
## lands or leaves a window round where it last stood (platform snapping, so a jump does not bob the screen), eases
## towards that at a rate that is the same at any tick rate, and stays inside the level's bounds, so it never shows
## past the level's ends.

const DISTANCE := 20.0
const LOOK_AHEAD := 2.5
## The climber's feet sit this far below the centre of the view, so more of what is above shows.
const HEIGHT_OFFSET := 2.0
## While airborne the view follows vertically only once the climber is this far from where it last stood.
const WINDOW := 2.5
## How quickly the view catches up, per second.
const SMOOTHING := 5.0

## The part of the level the view may show (x and y; z is ignored).
var limits := AABB(Vector3(-100, -100, 0), Vector3(200, 200, 0))

var _focus := Vector2.ZERO
var _settled_y := 0.0


## Jumps straight to the climber at a level's start or a respawn.
func reset_to(target: Vector3, bounds: AABB) -> void:
	limits = bounds
	_settled_y = target.y
	_focus = Vector2(target.x, target.y + HEIGHT_OFFSET)
	position = _clamped(_focus)
	reset_physics_interpolation()


func follow(target: Vector3, grounded: bool, facing: float, delta: float) -> void:
	if grounded or absf(target.y - _settled_y) > WINDOW:
		_settled_y = target.y
	var wanted := Vector2(target.x + facing * LOOK_AHEAD, _settled_y + HEIGHT_OFFSET)
	_focus = _focus.lerp(wanted, 1.0 - exp(-SMOOTHING * delta))
	position = _clamped(_focus)


## Half the width and height of what the view shows, in metres.
func half_extents() -> Vector2:
	var view := get_viewport().get_visible_rect().size
	return Vector2(size * view.x / maxf(view.y, 1.0) / 2.0, size / 2.0)


func _clamped(focus: Vector2) -> Vector3:
	var half := half_extents()
	var low := Vector2(limits.position.x, limits.position.y) + half
	var high := Vector2(limits.end.x, limits.end.y) - half
	var x := clampf(focus.x, low.x, maxf(high.x, low.x))
	var y := clampf(focus.y, low.y, maxf(high.y, low.y))
	return Vector3(x, y, DISTANCE)
