# Plays every *.flow.json in the project against the real scene tree, headless. Run by the "flows" runner:
#   godot --headless --path <project> -s <this file> -- [name filter]
# A flow is a scene plus steps (press, action, wait, assert...). Each flow is wrapped in marker lines; the runner
# attributes any ERROR printed in between to that flow. See docs/flows.md for the format.
extends SceneTree

const SKIP_DIRS := ["res://addons", "res://.godot"]
const FRAME_LIMIT := 3600

var _failure := ""
var _scene: Node


func _initialize() -> void:
	var filter := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		filter = user_args[0]
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	var ran := 0
	for path in files:
		if filter != "" and not path.contains(filter):
			continue
		ran += 1
		print("@@flow begin %s" % path)
		await _run_flow(path)
		print("@@flow end %s %s" % [path, _failure if _failure else "ok"])
	print("@@flow done %d" % ran)
	quit(0)


func _collect(dir: String, files: Array[String]) -> void:
	if dir in SKIP_DIRS or FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_collect(dir.path_join(sub), files)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".flow.json"):
			files.append(dir.path_join(file))


func _run_flow(path: String) -> void:
	_failure = ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_failure = "not a JSON object"
		return
	var flow: Dictionary = parsed
	var scene_path: String = str(flow.get("scene", ""))
	if scene_path == "":
		_failure = "missing \"scene\""
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failure = "cannot load %s" % scene_path
		return
	# A fixed seed makes randomness repeatable, so a flow is a test and not a gamble.
	seed(int(flow.get("seed", 0)))
	_scene = packed.instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await process_frame

	var steps: Array = flow.get("steps", [])
	for i in steps.size():
		var step: Variant = steps[i]
		if typeof(step) != TYPE_DICTIONARY:
			_failure = "step %d is not an object" % (i + 1)
			break
		var problem: String = await _step(step)
		if problem != "":
			_failure = "step %d (%s): %s" % [i + 1, JSON.stringify(step), problem]
			break

	for action in InputMap.get_actions():
		Input.action_release(action)
	_scene.queue_free()
	await process_frame
	_scene = null


# Returns "" when the step passed, else the reason it failed.
func _step(step: Dictionary) -> String:
	if step.has("wait"):
		for _n in int(step["wait"]):
			await physics_frame
		return ""
	if step.has("press"):
		var button := _node(str(step["press"]))
		if button == null:
			return "no node %s" % step["press"]
		if not button is BaseButton:
			return "%s is not a button" % step["press"]
		(button as BaseButton).pressed.emit()
		await process_frame
		return ""
	if step.has("action"):
		var action := str(step["action"])
		if not InputMap.has_action(action):
			return "no input action %s (see Project Settings > Input Map)" % action
		var press := InputEventAction.new()
		press.action = action
		press.pressed = true
		press.strength = float(step.get("strength", 1.0))
		Input.parse_input_event(press)
		for _n in maxi(int(step.get("hold", 1)), 1):
			await physics_frame
		var release := InputEventAction.new()
		release.action = action
		release.pressed = false
		Input.parse_input_event(release)
		await physics_frame
		return ""
	if step.has("set"):
		var target := _node(str(step["set"]))
		if target == null:
			return "no node %s" % step["set"]
		target.set_indexed(NodePath(str(step.get("prop", ""))), step.get("value"))
		return ""
	if step.has("call"):
		var callee := _node(str(step["call"]))
		if callee == null:
			return "no node %s" % step["call"]
		var method := str(step.get("method", ""))
		if not callee.has_method(method):
			return "%s has no method %s" % [step["call"], method]
		callee.callv(method, step.get("args", []))
		await process_frame
		return ""
	if step.has("assert"):
		return _check(step["assert"])
	if step.has("wait_until"):
		var limit := int(step.get("timeout", 300))
		for _n in mini(limit, FRAME_LIMIT):
			if _check(step["wait_until"]) == "":
				return ""
			await physics_frame
		return "condition not met after %d frames: %s" % [limit, _check(step["wait_until"])]
	return "unknown step (use wait, press, action, set, call, assert, wait_until)"


func _node(path: String) -> Node:
	if path == "" or path == ".":
		return _scene
	if path.begins_with("/"):
		return root.get_node_or_null(path)
	return _scene.get_node_or_null(path)


# Condition: { node, [prop], equals | not_equals | gt | ge | lt | le | contains | exists }
func _check(cond: Variant) -> String:
	if typeof(cond) != TYPE_DICTIONARY:
		return "condition must be an object"
	var node := _node(str(cond.get("node", ".")))
	if cond.has("exists"):
		var found := node != null
		return "" if found == bool(cond["exists"]) else "node %s %s" % [cond.get("node", "."), "is missing" if not found else "exists"]
	if node == null:
		return "no node %s" % cond.get("node", ".")
	var prop := str(cond.get("prop", ""))
	if prop == "":
		return "condition needs a prop"
	var actual: Variant = node.get_indexed(NodePath(prop))
	for op in ["equals", "not_equals", "gt", "ge", "lt", "le", "contains"]:
		if not cond.has(op):
			continue
		var expected: Variant = cond[op]
		var ok := false
		match op:
			"equals": ok = _same(actual, expected)
			"not_equals": ok = not _same(actual, expected)
			"gt": ok = actual > expected
			"ge": ok = actual >= expected
			"lt": ok = actual < expected
			"le": ok = actual <= expected
			"contains": ok = str(expected) in str(actual)
		return "" if ok else "%s.%s is %s, expected %s %s" % [cond.get("node", "."), prop, str(actual), op, str(expected)]
	return "condition has no operator (equals, not_equals, gt, ge, lt, le, contains, exists)"


# JSON numbers arrive as floats, so compare numbers by value.
func _same(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)
