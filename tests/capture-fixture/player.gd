# Stands in for gameplay: it moves while the game runs and stops when the tree is paused.
extends Node3D


func _process(delta: float) -> void:
	position.x += delta
