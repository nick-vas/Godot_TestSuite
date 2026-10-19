# Measures frame pacing of one scene and prints the result as one "@@bench <json>" line. Run by `godot-ci.ps1 bench`:
#   godot [--headless] --path <project> -s <this file> -- --bench-scene=res://x.tscn --bench-seconds=20 --bench-warmup=3 [game args]
# It records the wall-clock time of every frame, not an average FPS: averages hide the hitches players notice. Game args
# after "--" stay visible to the game (OS.get_cmdline_user_args()), so a "--stress" or "--autoplay" flag still works.
# Custom monitors the game registers (Performance.add_custom_monitor), for example C# GC collection counts, are reported as
# start, end and delta, which is how a C# game shows "zero GC in the frame loop".
extends SceneTree

const MAX_HITCHES := 50

var _options := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-") and arg.contains("="):
			_options[arg.get_slice("=", 0).trim_prefix("--bench-")] = arg.get_slice("=", 1)
	var scene_path := str(_options.get("scene", ""))
	if scene_path == "":
		scene_path = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var seconds := float(_options.get("seconds", "10"))
	var warmup := float(_options.get("warmup", "3"))
	if scene_path == "":
		_finish({"error": "no scene: pass -Scene or set a main scene"})
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_finish({"error": "cannot load %s" % scene_path})
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	# The scene's _ready runs on the next frame, not inside _initialize; custom monitors it registers exist only after that.
	await process_frame

	# Warm-up: first frames compile pipelines and fill caches, and would otherwise dominate the worst-case numbers.
	var warm_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warm_start < warmup * 1000000.0:
		await process_frame

	var monitors := {}
	for monitor_name in Performance.get_custom_monitor_names():
		monitors[str(monitor_name)] = {"start": Performance.get_custom_monitor(monitor_name)}
	var objects_start := Performance.get_monitor(Performance.OBJECT_COUNT)
	var memory_start := Performance.get_monitor(Performance.MEMORY_STATIC)

	var times := PackedFloat64Array()
	var stamps := PackedFloat64Array()
	var draw_calls := PackedFloat64Array()
	var start := Time.get_ticks_usec()
	var last := start
	while last - start < seconds * 1000000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		stamps.append((now - start) / 1000000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		last = now

	for monitor_name in monitors:
		var end_value: Variant = Performance.get_custom_monitor(StringName(monitor_name))
		monitors[monitor_name]["end"] = end_value
		monitors[monitor_name]["delta"] = float(end_value) - float(monitors[monitor_name]["start"])

	var sorted := times.duplicate()
	sorted.sort()
	var count := sorted.size()
	var total := 0.0
	for t in sorted:
		total += t
	var p50 := _percentile(sorted, 0.50)
	var hitch_ms := maxf(2.0 * p50, 8.33)
	var hitches := []
	for i in times.size():
		if times[i] > hitch_ms and hitches.size() < MAX_HITCHES:
			hitches.append({"t": snappedf(stamps[i], 0.001), "ms": snappedf(times[i], 0.01)})
	var draw_total := 0.0
	var draw_max := 0.0
	for d in draw_calls:
		draw_total += d
		draw_max = maxf(draw_max, d)

	_finish({
		"scene": scene_path,
		"seconds": seconds,
		"warmupSeconds": warmup,
		"frames": count,
		"fps": {
			"avg": snappedf(1000.0 * count / total, 0.1) if total > 0 else 0.0,
			"low1": snappedf(1000.0 / _slowest_mean(sorted, 0.01), 0.1),
			"low01": snappedf(1000.0 / _slowest_mean(sorted, 0.001), 0.1),
		},
		"frameMs": {
			"avg": snappedf(total / maxi(count, 1), 0.001),
			"p50": snappedf(p50, 0.001),
			"p90": snappedf(_percentile(sorted, 0.90), 0.001),
			"p99": snappedf(_percentile(sorted, 0.99), 0.001),
			"max": snappedf(sorted[count - 1], 0.001) if count > 0 else 0.0,
		},
		"over20ms": _count_over(sorted, 20.0),
		"over33ms": _count_over(sorted, 33.0),
		"hitchThresholdMs": snappedf(hitch_ms, 0.01),
		"hitches": hitches,
		"drawCalls": {"avg": snappedf(draw_total / maxi(count, 1), 0.1), "max": draw_max},
		"objects": {"start": objects_start, "end": Performance.get_monitor(Performance.OBJECT_COUNT)},
		"staticMemoryMB": {
			"start": snappedf(memory_start / 1048576.0, 0.01),
			"end": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.01),
		},
		"customMonitors": monitors,
		"display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED if DisplayServer.get_name() != "headless" else false,
		"maxFps": Engine.max_fps,
		"resolution": "%dx%d" % [root.size.x, root.size.y],
	})


func _finish(result: Dictionary) -> void:
	print("@@bench " + JSON.stringify(result))
	quit(0)


# Value at fraction q of an ascending array (nearest rank).
func _percentile(sorted: PackedFloat64Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(ceil(q * sorted.size())) - 1, 0, sorted.size() - 1)]


# Mean of the slowest fraction of frames: "1% low" FPS is 1000 / the mean of the slowest 1% of frame times.
func _slowest_mean(sorted: PackedFloat64Array, fraction: float) -> float:
	if sorted.is_empty():
		return 1000.0
	var n := maxi(1, int(ceil(sorted.size() * fraction)))
	var total := 0.0
	for i in range(sorted.size() - n, sorted.size()):
		total += sorted[i]
	return total / n


func _count_over(sorted: PackedFloat64Array, ms: float) -> int:
	var n := 0
	for t in sorted:
		if t > ms:
			n += 1
	return n
