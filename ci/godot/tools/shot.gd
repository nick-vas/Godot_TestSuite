# Saves a PNG of each given scene after it has run for a few frames. Run by `godot-ci.ps1 shot`:
#   godot --path <project> --resolution 1920x1080 -s <this file> -- --shot-scenes=res://a.tscn,res://b.tscn --shot-frames=60 --shot-dir=<abs dir>
# It reads the viewport's own texture after the frame is drawn, so the picture has the window's real resolution (the movie
# writer is tied to the startup window size). Headless runs draw nothing, so there is no picture: run it with a display.
extends SceneTree

var _options := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-") and arg.contains("="):
			_options[arg.get_slice("=", 0).trim_prefix("--shot-")] = arg.get_slice("=", 1)
	if DisplayServer.get_name() == "headless":
		print("@@shot error headless: there is no image without a display")
		quit(0)
		return
	var scenes := PackedStringArray()
	for path in str(_options.get("scenes", "")).split(",", false):
		scenes.append(path.strip_edges())
	if scenes.is_empty():
		scenes.append(str(ProjectSettings.get_setting("application/run/main_scene", "")))
	var frames := maxi(int(_options.get("frames", "60")), 1)
	var dir := str(_options.get("dir", "user://screenshots"))
	DirAccess.make_dir_recursive_absolute(dir)

	for scene_path in scenes:
		var packed := load(scene_path) as PackedScene if scene_path != "" else null
		if packed == null:
			print("@@shot error %s: cannot load" % scene_path)
			continue
		var scene := packed.instantiate()
		root.add_child(scene)
		current_scene = scene
		for _n in frames:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			print("@@shot error %s: the viewport returned no image" % scene_path)
		else:
			var file := dir.path_join(scene_path.get_file().get_basename() + ".png")
			var err := image.save_png(file)
			if err == OK:
				print("@@shot ok %s|%s|%d|%d" % [scene_path, file, image.get_width(), image.get_height()])
			else:
				print("@@shot error %s: save_png failed (%s)" % [scene_path, error_string(err)])
		scene.queue_free()
		await process_frame
	quit(0)
