# Saves a PNG of each given scene after it has run for a few frames. Run by `godot-ci.ps1 shot`:
#   godot --path <project> --resolution 1920x1080 -s <this file> -- --shot-scenes=res://a.tscn,res://b.tscn --shot-frames=60 --shot-dir=<abs dir>
# It reads the viewport's own texture after the frame is drawn, so the picture has the window's real resolution (the movie
# writer is tied to the startup window size). Headless runs draw nothing, so there is no picture: run it with a display.
# With --shot-baseline=<abs dir>, each picture is compared with the same-named PNG there: it prints the share of pixels that
# changed and saves <name>.compare.png, before | after | changes in red, for a person or an agent to look at.
extends SceneTree

# A pixel counts as changed when a colour channel moves by more than this (0..1); small enough for a recoloured label,
# large enough to ignore compression and dithering noise.
const CHANGE_THRESHOLD := 0.1

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
				var baseline_dir := str(_options.get("baseline", ""))
				if baseline_dir != "":
					_compare(scene_path, image, baseline_dir.path_join(file.get_file()), file.get_basename() + ".compare.png")
			else:
				print("@@shot error %s: save_png failed (%s)" % [scene_path, error_string(err)])
		scene.queue_free()
		await process_frame
	quit(0)


# Compares a fresh screenshot with its baseline at quarter resolution (fast in GDScript, and enough to see what moved) and saves
# before | after | changes side by side. Prints "@@shot compare <scene>|<compare png>|<percent changed>|<size changed 0/1>".
func _compare(scene_path: String, after: Image, baseline_file: String, compare_file: String) -> void:
	if not FileAccess.file_exists(baseline_file):
		print("@@shot compare %s|-|-1|0" % scene_path)
		return
	var before := Image.load_from_file(baseline_file)
	if before == null or before.is_empty():
		print("@@shot error %s: cannot read baseline %s" % [scene_path, baseline_file])
		return
	var size_changed := before.get_size() != after.get_size()
	var w := maxi(after.get_width() / 4, 1)
	var h := maxi(after.get_height() / 4, 1)
	var a := after.duplicate() as Image
	var b := before.duplicate() as Image
	for img in [a, b]:
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var diff := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var changed := 0
	for y in h:
		for x in w:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) > CHANGE_THRESHOLD or absf(ca.g - cb.g) > CHANGE_THRESHOLD or absf(ca.b - cb.b) > CHANGE_THRESHOLD:
				changed += 1
				diff.set_pixel(x, y, Color(1, 0, 0))
			else:
				var grey := ca.get_luminance() * 0.4
				diff.set_pixel(x, y, Color(grey, grey, grey))
	var sheet := Image.create(w * 3 + 8, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(1, 1, 1))
	sheet.blit_rect(b, Rect2i(0, 0, w, h), Vector2i(0, 0))
	sheet.blit_rect(a, Rect2i(0, 0, w, h), Vector2i(w + 4, 0))
	sheet.blit_rect(diff, Rect2i(0, 0, w, h), Vector2i(w * 2 + 8, 0))
	sheet.save_png(compare_file)
	print("@@shot compare %s|%s|%.2f|%d" % [scene_path, compare_file, 100.0 * changed / (w * h), 1 if size_changed else 0])
