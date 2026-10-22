extends Node2D

signal died

@onready var _sprite: Sprite2D = $Sprite2D

func _process(delta: float) -> void:
	_sprite.rotation += delta
	position = position.lerp(get_global_mouse_position(), 1.0 - exp(-8.0 * delta))
