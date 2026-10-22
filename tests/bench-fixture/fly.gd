# A camera that flies along +X at a constant speed (5 m/s in 3D, starting at x = 25; 100 px/s in 2D) and makes every
# frame 25 ms slower while it is between x = 40 and x = 60 (400 and 600 px in 2D): one slow place, so `bench` must name
# it in "hotspots".
extends Node

@export var speed := 5.0
@export var slow_from := 40.0
@export var slow_to := 60.0

var _camera: Node


func _ready() -> void:
	_camera = get_node("Camera")


func _process(delta: float) -> void:
	_camera.position.x += speed * delta
	if _camera.position.x >= slow_from and _camera.position.x <= slow_to:
		OS.delay_usec(25000)
