# Measures frame pacing of one scene and prints the result as one "@@bench <json>" line. Run by `hyperdot.ps1 bench`:
#   godot [--headless] --path <project> -s <this file> -- --bench-scene=res://x.tscn --bench-seconds=20 --bench-warmup=3 [game args]
# It records the wall-clock time of every frame, not an average FPS: averages hide the hitches players notice. Game args
# after "--" stay visible to the game (OS.get_cmdline_user_args()), so a "--stress" or "--autoplay" flag still works.
# Custom monitors the game registers (Performance.add_custom_monitor), for example C# GC collection counts, are reported as
# start, end and delta, which is how a C# game shows "zero GC in the frame loop".
# Each frame time is paired with where the camera was, so slow frames get a place as well as a time: "hotspots" are the
# grid cells of camera positions with the worst 99th-percentile frame time (--bench-cell sets the cell size).
# "loadMs" is how long the scene took from load() until its first frame was done: reading the resource, instantiating
# it, adding it to the tree (its _ready) and drawing that frame. "frameHistogram" puts every frame in a fixed bucket by the
# frame rate it would sustain: 120, 60, 30 and 20 fps (8.33, 16.67, 33.33 and 50 ms), and slower.
extends SceneTree

const MAX_HITCHES := 50
const MAX_HOTSPOTS := 10
# Default hotspot cell: 10 m in 3D (a room, a stretch of road), 512 px in 2D (about a quarter of a 1080p screen's width).
const CELL_3D := 10.0
const CELL_2D := 512.0
# Upper bounds of the frame-time histogram's buckets, in ms: a frame at most this long sustains 120, 60, 30 and 20 fps.
const HISTOGRAM_MS := [1000.0 / 120.0, 1000.0 / 60.0, 1000.0 / 30.0, 1000.0 / 20.0]

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
	var load_start := Time.get_ticks_usec()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_finish({"error": "cannot load %s" % scene_path})
		return
	var loaded := Time.get_ticks_usec()
	var scene := packed.instantiate()
	var instantiated := Time.get_ticks_usec()
	root.add_child(scene)
	current_scene = scene
	# The scene's _ready runs on the next frame, not inside _initialize; custom monitors it registers exist only after that.
	await process_frame
	var first_frame := Time.get_ticks_usec()

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
	var primitives := PackedFloat64Array()
	var gpu_ms := PackedFloat64Array()
	# Where each frame was seen from, and by which kind of camera (3, 2, or 0 for none).
	var places := PackedVector3Array()
	var kinds := PackedByteArray()
	# GPU time per frame: what shaders, particles and post-processing cost (0 when nothing is drawn).
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var start := Time.get_ticks_usec()
	var last := start
	while last - start < seconds * 1000000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		stamps.append((now - start) / 1000000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		_sample_camera(places, kinds)
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
	var hitch_count := 0
	for i in times.size():
		if times[i] > hitch_ms:
			hitch_count += 1
			if hitches.size() < MAX_HITCHES:
				hitches.append({"t": snappedf(stamps[i], 0.001), "ms": snappedf(times[i], 0.01), "pos": _place(places[i], kinds[i])})
	var kind := _main_kind(kinds)
	var cell := float(_options.get("cell", "0"))
	if cell <= 0.0:
		cell = CELL_3D if kind == 3 else CELL_2D
	if kind == 0:
		cell = 0.0
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
		"frameHistogram": _histogram(sorted),
		"over20ms": _count_over(sorted, 20.0),
		"over33ms": _count_over(sorted, 33.0),
		"hitchThresholdMs": snappedf(hitch_ms, 0.01),
		"hitches": hitches,
		"hitchCount": hitch_count,
		"camera": {3: "3d", 2: "2d"}.get(kind, "none"),
		"hotspotCell": cell,
		"hotspots": _hotspots(times, places, kinds, kind, cell),
		"loadMs": snappedf((first_frame - load_start) / 1000.0, 0.1),
		"loadBreakdownMs": {
			"resource": snappedf((loaded - load_start) / 1000.0, 0.1),
			"instantiate": snappedf((instantiated - loaded) / 1000.0, 0.1),
			"firstFrame": snappedf((first_frame - instantiated) / 1000.0, 0.1),
		},
		"drawCalls": {"avg": snappedf(draw_total / maxi(count, 1), 0.1), "max": draw_max},
		"primitives": _avg_max(primitives, 1.0),
		"gpuMs": _avg_max(gpu_ms, 0.001),
		"textureMemoryMB": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.01),
		"videoMemoryMB": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.01),
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


# The camera the player sees through: the root viewport's Camera3D, else its Camera2D. A 2D camera's place is the centre of
# the screen, which is not its own position while it is smoothed or held at a limit. Cameras inside a SubViewport are not seen.
func _sample_camera(places: PackedVector3Array, kinds: PackedByteArray) -> void:
	var camera_3d := root.get_camera_3d()
	if camera_3d != null:
		places.append(camera_3d.global_position)
		kinds.append(3)
		return
	var camera_2d := root.get_camera_2d()
	if camera_2d != null:
		var centre := camera_2d.get_screen_center_position()
		places.append(Vector3(centre.x, centre.y, 0.0))
		kinds.append(2)
		return
	places.append(Vector3.ZERO)
	kinds.append(0)


# The kind of camera most frames had (3, 2, or 0 when no frame had one). Only frames seen by that kind are placed in cells.
func _main_kind(kinds: PackedByteArray) -> int:
	var counts := {0: 0, 2: 0, 3: 0}
	for k in kinds:
		counts[k] += 1
	if counts[3] == 0 and counts[2] == 0:
		return 0
	return 3 if counts[3] >= counts[2] else 2


func _place(where: Vector3, kind: int) -> Variant:
	if kind == 3:
		return [snappedf(where.x, 0.01), snappedf(where.y, 0.01), snappedf(where.z, 0.01)]
	if kind == 2:
		return [snappedf(where.x, 0.01), snappedf(where.y, 0.01)]
	return null


# Buckets frame times into a grid of cells (cell units wide, aligned to 0) by camera position, and returns the cells with
# the worst 99th-percentile frame time first: where to look first, the way a heat map of frame rate over a level is read.
func _hotspots(times: PackedFloat64Array, places: PackedVector3Array, kinds: PackedByteArray, kind: int, cell: float) -> Array:
	if kind == 0:
		return []
	var cells := {}
	for i in times.size():
		if kinds[i] != kind:
			continue
		var key := (places[i] / cell).floor()
		if not cells.has(key):
			cells[key] = []
		cells[key].append(times[i])
	var spots := []
	for key: Vector3 in cells:
		var sorted := PackedFloat64Array(cells[key])
		sorted.sort()
		spots.append({
			"centre": _place((key + Vector3(0.5, 0.5, 0.5)) * cell, kind),
			"frames": sorted.size(),
			"p99Ms": snappedf(_percentile(sorted, 0.99), 0.01),
			"maxMs": snappedf(sorted[sorted.size() - 1], 0.01),
		})
	spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.p99Ms > b.p99Ms or (a.p99Ms == b.p99Ms and a.frames > b.frames))
	return spots.slice(0, MAX_HOTSPOTS)


# Average and maximum of a per-frame series, rounded to step.
func _avg_max(values: PackedFloat64Array, step: float) -> Dictionary:
	var total := 0.0
	var most := 0.0
	for v in values:
		total += v
		most = maxf(most, v)
	return {"avg": snappedf(total / maxi(values.size(), 1), step), "max": snappedf(most, step)}


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


# Frames per bucket of HISTOGRAM_MS, each bucket (fromMs, toMs]; the last one has no upper bound (toMs null).
func _histogram(sorted: PackedFloat64Array) -> Array:
	var buckets := []
	var low := 0.0
	var i := 0
	for edge in HISTOGRAM_MS + [INF]:
		var n := 0
		while i < sorted.size() and sorted[i] <= edge:
			n += 1
			i += 1
		buckets.append({
			"fromMs": snappedf(low, 0.01),
			"toMs": snappedf(edge, 0.01) if edge != INF else null,
			"frames": n,
			"percent": snappedf(100.0 * n / maxi(sorted.size(), 1), 0.1),
		})
		low = edge
	return buckets


func _count_over(sorted: PackedFloat64Array, ms: float) -> int:
	var n := 0
	for t in sorted:
		if t > ms:
			n += 1
	return n
