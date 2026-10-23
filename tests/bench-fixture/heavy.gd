# A scene that is slow to load and costly to draw: _ready takes 300 ms, and 24 boxes, each with its own material, are
# at least 24 draw calls a frame. bench must report both (loadMs, drawCalls) and fail -MaxLoadMs and -MaxDrawCalls.
extends Node3D

const BOXES := 24


func _ready() -> void:
	OS.delay_msec(300)
	for i in BOXES:
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.from_hsv(float(i) / BOXES, 0.8, 0.9)
		box.material_override = material
		box.position = Vector3((i % 6) * 1.5 - 3.75, (i / 6) * 1.5 - 2.25, 0.0)
		add_child(box)
