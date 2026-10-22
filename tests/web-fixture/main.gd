extends Control


func _ready() -> void:
	$Label.text = "Hello from the web"
	print("[web-fixture] ready")
	if OS.has_feature("broken"):
		var missing: Node = null
		missing.queue_free()
