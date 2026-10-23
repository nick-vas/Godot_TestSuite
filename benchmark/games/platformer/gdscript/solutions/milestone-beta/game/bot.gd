class_name Bot
extends RefCounted
## The --autoplay player. It runs right, jumps near the end of the ground it stands on, up onto a higher platform ahead,
## and over (or onto) a beetle ahead, holding jump for the full arc. It never looks at thorns: that blind spot is where
## it gets hurt, once per patch, which the juice run needs to see.

## Jump when the ground ends this close ahead ...
const EDGE_LEAD := 0.45
## ... or a higher platform starts this close ahead, if it is no higher than it can climb ...
const STEP_LOOK := 1.4
const CLIMB_MAX := 1.9
## ... or a beetle is this close ahead.
const BEETLE_LOOK := 2.4

var _boxes: Array[AABB] = []


func setup(boxes: Array[AABB]) -> void:
	_boxes = boxes


## direction (always right), jump_pressed (this tick) and jump_held.
func decide(feet: Vector3, on_floor: bool, rising: bool, beetles: Array) -> Dictionary:
	var jump := on_floor and _should_jump(feet, beetles)
	return {"direction": 1.0, "jump_pressed": jump, "jump_held": jump or rising}


func _should_jump(feet: Vector3, beetles: Array) -> bool:
	var ground_end := _ground_end(feet)
	if not is_nan(ground_end) and ground_end - feet.x < EDGE_LEAD:
		return true
	for box in _boxes:
		var ahead := box.position.x - feet.x
		var rise := box.end.y - feet.y
		if ahead > 0.0 and ahead < STEP_LOOK and rise > 0.3 and rise <= CLIMB_MAX:
			return true
	for beetle: Node3D in beetles:
		var ahead := beetle.position.x - feet.x
		if ahead > 0.0 and ahead < BEETLE_LOOK and absf(beetle.position.y - feet.y) < 0.8:
			return true
	return false


## Where the ground under the feet ends on the right, across platforms that touch at the same height; NAN in the air.
func _ground_end(feet: Vector3) -> float:
	var end := NAN
	for box in _boxes:
		if absf(box.end.y - feet.y) < 0.15 and box.position.x - Player.HALF_WIDTH <= feet.x and feet.x <= box.end.x + Player.HALF_WIDTH:
			end = box.end.x if is_nan(end) else maxf(end, box.end.x)
	if is_nan(end):
		return end
	var grew := true
	while grew:
		grew = false
		for box in _boxes:
			if absf(box.end.y - feet.y) < 0.15 and box.position.x <= end + 0.01 and box.end.x > end:
				end = box.end.x
				grew = true
	return end
