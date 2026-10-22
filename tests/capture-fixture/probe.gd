# Reports what capture mode changed, for tests/Test-Capture.ps1, which reads the lines from shot.log:
#   frame 10: "@@capture-probe {json}"; with --press-freeze-key it then presses F7, and frame 14 prints "@@capture-probe-key {json}".
# --fly holds cam_forward from the first frame, so the free camera moves.
extends Node

var _frame := 0
var _delta_sum := 0.0
var _start_usec := 0


# Also measures how fast delta runs against the clock on the wall for an always-processing node (frames 3 to 10).
func _process(delta: float) -> void:
	_frame += 1
	if _frame == 2:
		_start_usec = Time.get_ticks_usec()
	elif _frame > 2:
		_delta_sum += delta
	var args := OS.get_cmdline_user_args()
	if _frame == 1 and "--fly" in args:
		Input.action_press("cam_forward")
	elif _frame == 10:
		print("@@capture-probe " + JSON.stringify(_state()))
		if "--press-freeze-key" in args:
			for pressed in [true, false]:
				var key := InputEventKey.new()
				key.keycode = KEY_F7
				key.pressed = pressed
				Input.parse_input_event(key)
	elif _frame == 14 and "--press-freeze-key" in args:
		print("@@capture-probe-key " + JSON.stringify(_state()))


func _state() -> Dictionary:
	return {
		"music_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),
		"sfx_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		"master_muted": AudioServer.is_bus_mute(0),
		"mouse_hidden": Input.mouse_mode == Input.MOUSE_MODE_HIDDEN,
		"paused": get_tree().paused,
		"time_scale": Engine.time_scale,
		"physics_ticks": Engine.physics_ticks_per_second,
		"player_x": $"../Player".position.x,
		"camera_z": $"../FreeCamera".position.z,
		"hud_visible": $"../HUD".visible,
		"prompt_visible": $"../DoorPrompt".visible,
		"delta_per_real_second": _delta_sum / maxf((Time.get_ticks_usec() - _start_usec) / 1e6, 1e-6),
	}
