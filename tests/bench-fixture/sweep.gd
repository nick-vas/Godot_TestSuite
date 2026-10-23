# bench -Sweep's scene: --cost=<ms> makes every frame that much slower, so p99 follows the value; --cost=error prints an
# engine error, a run the sweep must report as failed.
extends Node2D

var cost_ms := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cost="):
			var value := arg.trim_prefix("--cost=")
			if value == "error":
				push_error("sweep fixture: --cost=error")
			else:
				cost_ms = int(value)


func _process(_delta: float) -> void:
	if cost_ms > 0:
		OS.delay_msec(cost_ms)
