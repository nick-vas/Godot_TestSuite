extends Control
## What a phone rotation looks like to a game: the viewport's size_changed, whether "jump" was held when it came, the
## press and release events, and the layout a loading screen picks when it finishes.

var resizes := 0
var held_at_resize := false
var presses := 0
var releases := 0
var loading := false
var loaded_layout := ""
var _frames_left := 0


func _ready() -> void:
	get_viewport().size_changed.connect(_on_size_changed)


func _on_size_changed() -> void:
	resizes += 1
	held_at_resize = Input.is_action_pressed("jump")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		presses += 1
	elif event.is_action_released("jump"):
		releases += 1


# Flows pass numbers as floats, so the arguments are untyped. With early = true the screen picks its layout when loading
# starts, the bug a rotation during loading shows (test/flows/broken/layout_picked_too_early.flow.json).
func start_loading(frames, early = false) -> void:
	loading = true
	_frames_left = int(frames)
	if early:
		loaded_layout = _layout()


func _process(_delta: float) -> void:
	if not loading:
		return
	_frames_left -= 1
	if _frames_left <= 0:
		loading = false
		if loaded_layout == "":
			loaded_layout = _layout()


func _layout() -> String:
	var size := get_viewport_rect().size
	return "portrait" if size.y > size.x else "landscape"
