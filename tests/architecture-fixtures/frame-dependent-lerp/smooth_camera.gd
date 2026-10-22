extends Camera2D

# Not flagged: the GDScript counterparts.
@export var target: Node2D
@export var rate := 10.0

func _process(delta: float) -> void:
	position = position.lerp(target.position, 1.0 - exp(-rate * delta))
	var w := 1.0 - pow(0.001, delta)
	zoom = zoom.lerp(Vector2(2, 2), w)
	modulate = Color.RED.lerp(Color.WHITE, 0.5)

func midpoint(a: float, b: float) -> float:
	return lerp(a, b, 0.5)
