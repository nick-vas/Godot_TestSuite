# The `placement` runner's half inside Godot: templates/placement_check.gd on the levels placement.json names, with each
# limit read from the gameplay script constant placement.json names (never a copy of the number).
#   godot --headless --path <project> -s placement.gd -- --check=<kit>/templates/placement_check.gd
# placement.json, in the project folder:
#   { "levels": ["res://levels", "res://extra/arena.tscn"],
#     "limits": { "reach": "res://player.gd:REACH", "zipline_max_angle": "res://zipline.gd:MAX_ANGLE_DEGREES",
#                 "eye_height": 1.7 } }
# "levels" are folders (every .tscn under them, as PlacementCheck.scenes_in finds them) or scenes. "limits" sets the
# check's properties: "<script>:<CONSTANT>" reads a constant of a GDScript, anything else is the value itself.
# Prints "@@placement-scene <path>" per scene checked, "@@placement <finding>" per finding (PlacementCheck's lines),
# "@@placement-summary <line>" for its summary and "@@placement-error <message>" for what stopped it. Exits 0; the
# runner judges.
extends SceneTree

var _opt := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_opt[arg.get_slice("=", 0).trim_prefix("--")] = arg.substr(arg.find("=") + 1)
	_run.call_deferred()


func _fail(message: String) -> void:
	print("@@placement-error " + message)
	quit(0)


func _run() -> void:
	var check_class := load(str(_opt.get("check", ""))) as GDScript
	if check_class == null:
		_fail("the kit's placement_check.gd did not load from %s" % _opt.get("check", ""))
		return
	var text := FileAccess.get_file_as_string("res://placement.json")
	var config = JSON.parse_string(text)
	if not config is Dictionary:
		_fail("placement.json is not a JSON object")
		return
	for key in config:
		if not key in ["levels", "limits"]:
			_fail("placement.json: unknown setting '%s' (settings: levels, limits)" % key)
			return
	var check = check_class.new()
	var limits = config.get("limits", {})
	if not limits is Dictionary:
		_fail("placement.json: limits is not an object")
		return
	for name in limits:
		if not name in check or name in ["findings", "exemptions", "ready_frames"]:
			_fail("placement.json: '%s' is not a limit of placement_check.gd" % name)
			return
		var value = limits[name]
		if value is String and value.contains(":") and value.begins_with("res://") and value.get_slice(":", value.get_slice_count(":") - 1).is_valid_identifier():
			var constant: String = value.get_slice(":", value.get_slice_count(":") - 1)
			var path: String = value.substr(0, value.length() - constant.length() - 1)
			var script := load(path) as Script
			if script == null:
				_fail("placement.json: limit '%s' names %s, which does not load" % [name, path])
				return
			var constants := script.get_script_constant_map()
			if not constants.has(constant):
				_fail("placement.json: limit '%s' names %s, which has no constant %s (it has: %s)" % [name, path, constant, ", ".join(constants.keys())])
				return
			value = constants[constant]
		var current = check.get(name)
		if typeof(current) == TYPE_INT and typeof(value) == TYPE_FLOAT:
			value = int(value)
		if typeof(current) != TYPE_NIL and typeof(value) != typeof(current) and not (typeof(current) == TYPE_FLOAT and typeof(value) == TYPE_INT):
			_fail("placement.json: limit '%s' is %s, not a %s" % [name, type_string(typeof(value)), type_string(typeof(current))])
			return
		check.set(name, value)
	var paths: Array[String] = []
	for level in config.get("levels", []):
		if str(level).ends_with(".tscn"):
			paths.append(str(level))
		else:
			paths.append_array(check_class.scenes_in(str(level)))
	if paths.is_empty():
		_fail("placement.json: no scenes under %s" % ", ".join(config.get("levels", [])))
		return
	# Its own counts file: a placement test the game also runs keeps its own change since the last run.
	check.counts_file = "res://.godot/placement-runner-counts.json"
	var findings: Array[String] = await check.check_scenes(root, paths)
	for path in paths:
		print("@@placement-scene " + path)
	for finding in findings:
		print("@@placement " + finding)
	for line in check.summary().split("\n", false):
		print("@@placement-summary " + line)
	quit(0)
