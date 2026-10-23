class_name Thorns
extends Node3D
## A patch of thorns on the ground: touching it hurts. Its width comes from size; the spikes are drawn from it.

const SPIKE_WIDTH := 0.5

@export var size := Vector3(1.5, 0.5, 1.0)


func _ready() -> void:
	var count := maxi(1, roundi(size.x / SPIKE_WIDTH))
	var spike := PrismMesh.new()
	spike.size = Vector3(size.x / count, size.y, size.z)
	var material := Level.flat_material(Color("#c23b4b"))
	for i in count:
		var part := MeshInstance3D.new()
		part.mesh = spike
		part.material_override = material
		part.position = Vector3(-size.x / 2.0 + (i + 0.5) * size.x / count, size.y / 2.0, 0)
		add_child(part)
