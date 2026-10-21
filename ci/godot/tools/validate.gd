# Loads every script, scene, resource and shader in the project, and instantiates every scene, so that broken
# references and parse errors fail CI even in files no test touches. Run by the "validate" runner:
#   godot --headless --path <project> -s <this file>
# Each file is wrapped in marker lines; the runner attributes any ERROR printed in between to that file.
extends SceneTree

const EXTENSIONS := ["gd", "tscn", "scn", "tres", "res", "gdshader"]
const SKIP_DIRS := ["res://addons", "res://.godot"]


func _initialize() -> void:
	# Godot 4.5+: collect each file's errors in-process, so they are reported with its end marker on stdout.
	var capture: Object = null
	if ClassDB.class_exists("Logger"):
		capture = load(get_script().resource_path.get_base_dir().path_join("validate_logger.gd")).new()
		OS.call("add_logger", capture)
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	for path in files:
		if capture:
			capture.take()  # drop anything logged before this file
		print("@@validate begin %s" % path)
		var problem := _check(path)
		if capture:
			for line in capture.take():
				print("@@validate error %s" % line)  # filtered by the runner like any engine error
		print("@@validate end %s %s" % [path, problem if problem else "ok"])
	print("@@validate done %d" % files.size())
	if capture:
		OS.call("remove_logger", capture)
	quit(0)


func _collect(dir: String, files: Array[String]) -> void:
	if dir in SKIP_DIRS or FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_collect(dir.path_join(sub), files)
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in EXTENSIONS:
			files.append(dir.path_join(file))


func _check(path: String) -> String:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		return "failed to load"
	if resource is Script:
		var script := resource as Script
		var abstract: bool = script.has_method("is_abstract") and script.call("is_abstract")
		if not script.can_instantiate() and not abstract:
			return "script does not compile"
	elif resource is PackedScene:
		# Instantiate without adding to the tree: constructors run, _ready does not.
		var node := (resource as PackedScene).instantiate()
		if node == null:
			return "scene does not instantiate"
		node.free()
	elif resource is Shader:
		# Loading does not compile a shader headless; asking for its uniforms does, and prints SHADER ERROR if it is broken.
		# A fresh Shader with the same code compiles here, between this file's markers, even if Godot already compiled (and
		# reported) the loaded one at startup.
		var fresh := Shader.new()
		fresh.code = (resource as Shader).code + "\n// validate\n"  # different text, so no compile cache can skip it
		fresh.get_shader_uniform_list()
	return ""
