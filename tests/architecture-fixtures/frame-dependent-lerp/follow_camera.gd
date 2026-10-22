extends Camera2D

# Flagged: the GDScript forms of the same fixed weight per frame.
@export var target: Node2D
const SMOOTHING := 0.1

func _process(delta: float) -> void:
	position = position.lerp(target.position, 0.1)
	self.zoom.x = lerpf(zoom.x, 2.0, SMOOTHING)
	rotation = lerp_angle(rotation, target.rotation, 0.2)
