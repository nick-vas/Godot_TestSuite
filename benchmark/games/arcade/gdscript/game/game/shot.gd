class_name Shot
extends Sprite2D
## A shot from the ship (up) or an enemy (down). It moves itself; the game checks what it hits.

var velocity := Vector2.ZERO
var hostile := false
## Set once it has hit something, so it hits nothing else before it is removed.
var spent := false
var size := Vector2(6, 16)


func _physics_process(delta: float) -> void:
	position += velocity * delta
