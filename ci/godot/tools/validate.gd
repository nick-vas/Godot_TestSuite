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
	elif path.get_extension() == "tres":
		# A key the class no longer has (a renamed or removed export) is dropped on load without an error, and the value
		# is lost the next time the file is saved.
		var unknown := _unknown_keys(path, resource)
		if not unknown.is_empty():
			return "keeps %s, which %s no longer has (a renamed or removed export?): the value is dropped on load and lost on the next save" % [", ".join(unknown), _class_of(resource)]
	elif resource is Shader:
		# Loading does not compile a shader headless; asking for its uniforms does, and prints SHADER ERROR if it is broken.
		# A fresh Shader with the same code compiles here, between this file's markers, even if Godot already compiled (and
		# reported) the loaded one at startup.
		var fresh := Shader.new()
		fresh.code = (resource as Shader).code + "\n// validate\n"  # different text, so no compile cache can skip it
		fresh.get_shader_uniform_list()
	return ""


# The keys under [resource] in a text resource that are not stored properties of the loaded object.
func _unknown_keys(path: String, resource: Resource) -> PackedStringArray:
	var stored := {}
	for property in resource.get_property_list():
		if property["usage"] & PROPERTY_USAGE_STORAGE:
			stored[property["name"]] = true
	var unknown := PackedStringArray()
	var key_line := RegEx.create_from_string("^([A-Za-z_][A-Za-z0-9_/]*) = ")
	var inside := false
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("["):
			inside = line.strip_edges() == "[resource]"
			continue
		if not inside:
			continue
		var found := key_line.search(line)
		if found == null:
			continue
		var key := found.get_string(1)
		if key.begins_with("metadata/") or stored.has(key):
			continue
		unknown.append(key)
	return unknown


func _class_of(resource: Resource) -> String:
	var script: Script = resource.get_script()
	if script:
		var name := script.get_global_name()
		return name if name != "" else script.resource_path.get_file()
	return resource.get_class()
