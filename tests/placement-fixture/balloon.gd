# A balloon that drifts 0.1 m every physics frame: tall and easy to see, and no use as a landmark.
extends Node3D


func _physics_process(_delta: float) -> void:
	position.x += 0.1
