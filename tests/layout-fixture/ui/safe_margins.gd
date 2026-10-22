## A MarginContainer that keeps its children inside SafeArea. Anchor it full rect.
extends MarginContainer

@export var extra := 0


func _ready() -> void:
	SafeArea.changed.connect(_apply)
	_apply()


func _apply() -> void:
	var view := get_viewport_rect()
	var safe := SafeArea.canvas_rect()
	add_theme_constant_override("margin_left", int(ceil(safe.position.x - view.position.x)) + extra)
	add_theme_constant_override("margin_top", int(ceil(safe.position.y - view.position.y)) + extra)
	add_theme_constant_override("margin_right", int(ceil(view.end.x - safe.end.x)) + extra)
	add_theme_constant_override("margin_bottom", int(ceil(view.end.y - safe.end.y)) + extra)
