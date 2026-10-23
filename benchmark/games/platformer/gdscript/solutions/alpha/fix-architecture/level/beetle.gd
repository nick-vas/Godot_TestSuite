class_name Beetle
extends Node3D
## A beetle walking back and forth on its platform. It moves itself, so pausing the tree stops it; the game decides
## what touching it does. Its speed, points and colour come from data/beetles.json by kind.

const SIZE := Vector3(0.9, 0.6, 0.8)

@export var kind := "crawler"
## How far either side of where it was placed it walks.
@export var patrol := 2.0

var speed := 1.5
var points := 50

var _home_x := 0.0
var _direction := -1.0


func _ready() -> void:
	_home_x = position.x


func setup(row: Dictionary) -> void:
	speed = float(row.get("speed", speed))
	points = int(row.get("points", points))
	($Mesh as MeshInstance3D).material_override = Level.flat_material(Color.html(str(row.get("color", "#a05030"))))


func _physics_process(delta: float) -> void:
	position.x += _direction * speed * delta
	if position.x < _home_x - patrol:
		position.x = _home_x - patrol
		_direction = 1.0
	elif position.x > _home_x + patrol:
		position.x = _home_x + patrol
		_direction = -1.0
