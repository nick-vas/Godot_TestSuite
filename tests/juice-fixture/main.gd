extends Node2D
## A stand-in for a game with a bot: a "hit" every 30 frames, answered by a "flash" 2 frames later (33 ms at 60 fps), or
## 12 frames later (200 ms) when run with --late, which juice.json's 100 ms window must reject.

var _time_ms := 0.0
var _frame := 0
var _delay := 12 if "--late" in OS.get_cmdline_user_args() else 2
var _pending: Array[int] = []


func _process(delta: float) -> void:
	_time_ms += delta * 1000.0
	_frame += 1
	if _frame % 30 == 0:
		print("[juice] event hit %.1f" % _time_ms)
		_pending.append(_frame + _delay)
	while not _pending.is_empty() and _pending[0] <= _frame:
		_pending.pop_front()
		print("[juice] feedback flash %.1f" % _time_ms)
