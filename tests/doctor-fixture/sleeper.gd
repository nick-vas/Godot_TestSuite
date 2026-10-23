extends RigidBody2D
# Reads its position in _physics_process but never moves itself: not reported.

signal fell

func _physics_process(_delta: float) -> void:
	if position == Vector2.ZERO or position.y > 1000.0:
		fell.emit()


func _ready() -> void:
	position = Vector2(10, 10)
