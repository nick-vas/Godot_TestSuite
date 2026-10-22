## Autoload: the unobscured part of the screen in viewport (canvas) coordinates, and a fake notch for desktop tests.
## --safe-area=left,top,right,bottom (window pixels) after "--" overrides the platform's answer, so a desktop run or a
## CI check can show what a phone with a notch would hide.
extends Node

signal changed

var _override := Rect2i()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--safe-area="):
			var p := arg.get_slice("=", 1).split(",")
			if p.size() == 4:
				set_insets(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
	get_tree().root.size_changed.connect(func() -> void: changed.emit())


## Insets in window pixels; all zero removes the fake notch.
func set_insets(left: int, top: int, right: int, bottom: int) -> void:
	var win := get_tree().root.size
	_override = Rect2i(left, top, win.x - left - right, win.y - top - bottom) if left + top + right + bottom > 0 else Rect2i()
	changed.emit()


## Safe rectangle in window pixels.
func window_rect() -> Rect2i:
	var win := Rect2i(Vector2i.ZERO, get_tree().root.size)
	if _override.has_area():
		return _override
	if OS.has_feature("mobile"):
		# Screen coordinates; a mobile game is full screen, so the window starts at the screen origin.
		var r := DisplayServer.get_display_safe_area()
		r.position -= DisplayServer.window_get_position()
		return r.intersection(win)
	return win


## Safe rectangle in the coordinates Controls use (after stretch).
func canvas_rect() -> Rect2:
	return get_tree().root.get_final_transform().affine_inverse() * Rect2(window_rect())
