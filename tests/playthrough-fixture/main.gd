extends Node
# A stand-in game for the playthrough runner's self-test: with --autoplay its bot clears level 1 after one second of game
# time and reaches the ending after two, then quits; with --stuck as well, it never leaves level 1.

var _frames := 0
var _stuck := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_stuck = args.has("--stuck")
	set_process(args.has("--autoplay"))

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 60:
		print("[Run] level 1 done")
	elif _frames == 120 and not _stuck:
		print("[Run] ending reached")
		get_tree().quit()
