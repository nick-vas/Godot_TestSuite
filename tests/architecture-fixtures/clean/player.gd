extends Node2D

signal died

@onready var _sprite: Sprite2D = $Sprite2D

func _process(delta: float) -> void:
	_sprite.rotation += delta
