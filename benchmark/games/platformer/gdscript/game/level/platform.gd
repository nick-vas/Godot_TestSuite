class_name Platform
extends StaticBody3D
## A block of the level. Its collision box and its look come from size, so a level is a list of positions and sizes.

@export var size := Vector3(4, 1, 2)
@export var color := Color("#4d6b3c")


func _ready() -> void:
	var box := BoxShape3D.new()
	box.size = size
	($Shape as CollisionShape3D).shape = box
	var body := BoxMesh.new()
	body.size = size
	($Mesh as MeshInstance3D).mesh = body
	($Mesh as MeshInstance3D).material_override = Level.flat_material(color)
	# A strip of moss along the top, so the surface to land on reads at a glance.
	var top := BoxMesh.new()
	top.size = Vector3(size.x, 0.18, size.z + 0.02)
	($Top as MeshInstance3D).mesh = top
	($Top as MeshInstance3D).position.y = size.y / 2.0 - 0.09
	($Top as MeshInstance3D).material_override = Level.flat_material(Color("#8fd16a"))
