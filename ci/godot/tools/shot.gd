# Saves a PNG of each given scene after it has run for a few frames. Run by `godot-ci.ps1 shot`:
#   godot --path <project> --resolution 1920x1080 -s <this file> -- --shot-scenes=res://a.tscn,res://b.tscn --shot-frames=60 --shot-dir=<abs dir>
# It reads the viewport's own texture after the frame is drawn, so the picture has the window's real resolution (the movie
# writer is tied to the startup window size). Headless runs draw nothing, so there is no picture: run it with a display.
# With --shot-baseline=<abs dir>, each picture is compared with the same-named PNG there: it prints the share of pixels that
# changed and saves <name>.compare.png, before | after | changes in red, for a person or an agent to look at.
# With --shot-locales=fr,ar,pseudo, every scene is taken again in each locale (<name>.<locale>.png), and after each picture
# the visible labels and buttons are checked for text that is cut off, off screen, or missing glyphs.
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

	# The project's own locale first, then each --shot-locales entry ("pseudo" is pseudolocalization).
	var passes := PackedStringArray([""])
	passes.append_array(str(_options.get("locales", "")).split(",", false))
	var own_locale := TranslationServer.get_locale()
	for pass_name in passes:
		_set_pass(pass_name, own_locale)
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
				var file := dir.path_join(scene_path.get_file().get_basename() + ("." + pass_name if pass_name != "" else "") + ".png")
				var err := image.save_png(file)
				if err == OK:
					print("@@shot ok %s|%s|%d|%d|%s" % [scene_path, file, image.get_width(), image.get_height(), pass_name])
					var baseline_dir := str(_options.get("baseline", ""))
					if baseline_dir != "":
						_compare(scene_path, image, baseline_dir.path_join(file.get_file()), file.get_basename() + ".compare.png")
					_check_text(scene)
				else:
					print("@@shot error %s: save_png failed (%s)" % [scene_path, error_string(err)])
			scene.queue_free()
			await process_frame
	_set_pass("", own_locale)
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


# A locale ("fr", "ar_EG") or "pseudo": the project's text accented, 40% longer (German and Finnish run about 30% longer than
# English) and in [brackets], so a cut-off end or a hard-coded string shows at a glance. "" restores the project's own.
func _set_pass(pass_name: String, own_locale: String) -> void:
	var pseudo := pass_name == "pseudo"
	if pseudo:
		ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 0.4)
		ProjectSettings.set_setting("internationalization/pseudolocalization/replace_with_accents", true)
		ProjectSettings.set_setting("internationalization/pseudolocalization/prefix", "[")
		ProjectSettings.set_setting("internationalization/pseudolocalization/suffix", "]")
	TranslationServer.set_locale(own_locale if pass_name == "" or pseudo else pass_name)
	TranslationServer.pseudolocalization_enabled = pseudo
	TranslationServer.reload_pseudolocalization()
	if pass_name != "" and not pseudo and not TranslationServer.get_loaded_locales().has(pass_name) \
			and not TranslationServer.get_loaded_locales().has(pass_name.get_slice("_", 0)):
		print("@@shot error locale %s: no translation for it is loaded (internationalization/locale/translations)" % pass_name)


# Visible labels and buttons whose text is cut off, partly off screen, or has characters none of its fonts can draw (a
# system font may draw them on this machine, but not on a player's). Prints "@@shot text <node>|<kind>|<detail>".
func _check_text(node: Node) -> void:
	var screen := root.get_visible_rect()
	var reported := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty() and reported < 50:
		var n: Node = stack.pop_back()
		for child in n.get_children():
			stack.push_back(child)
		var control := n as Control
		if control == null or not control.is_visible_in_tree() or not (control is Label or control is Button):
			continue
		var raw := str(control.get("text"))
		if raw.strip_edges() == "":
			continue
		var shown := control.atr(raw)
		var where := str(node.get_path_to(control))
		var font := control.get_theme_font("font")
		var font_size := control.get_theme_font_size("font_size")
		var problems := PackedStringArray()
		var rect := control.get_global_rect()
		if rect.intersects(screen) and not screen.encloses(rect):
			problems.append("off screen|%s" % _quote(shown))
		var label := control as Label
		if label != null and label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			if label.get_visible_line_count() < label.get_line_count():
				problems.append("cut off|%d of %d lines show: %s" % [label.get_visible_line_count(), label.get_line_count(), _quote(shown)])
		else:
			var clips: bool = control.get("clip_text") or int(control.get("text_overrun_behavior")) != TextServer.OVERRUN_NO_TRIMMING
			var style := control.get_theme_stylebox("normal")
			var room := control.size.x - (style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT) if style else 0.0)
			var needed := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if clips and needed > room + 1.0:
				problems.append("cut off|needs %d px, has %d: %s" % [ceili(needed), floori(room), _quote(shown)])
		var missing := ""
		for i in shown.length():
			var code := shown.unicode_at(i)
			if code > 32 and not _is_format_char(code) and not font.has_char(code) and not missing.contains(char(code)):
				missing += char(code)
		if missing != "":
			problems.append("missing glyphs|%s in %s" % [_quote(missing), _quote(shown)])
		for problem in problems:
			print("@@shot text %s|%s" % [where, problem])
			reported += 1


func _quote(text: String) -> String:
	var flat := text.replace("\n", " ").replace("|", "/")
	return "\"%s\"" % (flat.left(60) + "..." if flat.length() > 60 else flat)


# Zero-width and direction marks, variation selectors and the BOM: invisible, so no font needs a glyph for them.
func _is_format_char(code: int) -> bool:
	return (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069) \
		or (code >= 0xFE00 and code <= 0xFE0F) or code == 0xFEFF