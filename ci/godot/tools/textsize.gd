# The textsize runner's Godot side: the size of every visible text on each scene, in real pixels on a given window
# (the Steam Deck's 1280x800 by default), run headless.
#   godot --headless --path <project> -s textsize.gd -- --scenes=res://a.tscn,res://b.tscn --resolutions=1280x800 [--min=9] [--want=12]
#     [--subtitle-group=subtitles] [--subtitle-min=28] [--subtitle-want=46]
# Headless Godot has no window (its size is 0x0), so the stretch scale is computed from the project settings the way
# Window::_update_viewport_size does, instead of read from the viewport (checked against Godot in all 80 combinations of
# stretch mode, aspect, scale and window size). Text height is measured from the font's own outlines: "H" (capitals) and
# "x" at the scaled size, which matched screenshots within 1 px on Godot 4.7.2.
# Text in the subtitle group (a control in it, or inside a node in it, hidden or not: subtitles are hidden between lines)
# also has a subtitle size, given at 1080p and scaled with the window's height: under --subtitle-min fails, under
# --subtitle-want warns.
# Prints, per resolution:
#   @@textsize-scale <WxH> <scale>
#   @@textsize-cutoff <WxH> <base WxH>              (integer scale mode on a window smaller than the base: drawn 1:1, cut off)
#   @@textsize <WxH>|<scene>|<node>|<font size>|<em px>|<cap px>|<x px>|<FAIL|WARN|ok>
#   @@textsize-subtitle <WxH>|<scene>|<node>|<font size>|<em px>|<cap px>|<min px>|<want px>|<FAIL|WARN|ok>
#   @@textsize-error <scene>|<message>
extends SceneTree

const TEXT_CONTROLS := ["Label", "Button", "LineEdit", "RichTextLabel", "TextEdit", "OptionButton", "CheckBox", "CheckButton", "LinkButton", "MenuButton", "SpinBox"]

var _opt := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_opt[arg.get_slice("=", 0).trim_prefix("--")] = arg.substr(arg.find("=") + 1)
	var min_px := float(_opt.get("min", "9"))
	var want_px := float(_opt.get("want", "12"))
	var subtitle_group := StringName(str(_opt.get("subtitle-group", "subtitles")))
	var subtitle_min := float(_opt.get("subtitle-min", "28"))
	var subtitle_want := float(_opt.get("subtitle-want", "46"))
	var scenes := str(_opt.get("scenes", ProjectSettings.get_setting("application/run/main_scene", ""))).split(",", false)
	var resolutions := str(_opt.get("resolutions", "1280x800")).split(",", false)
	for res in resolutions:
		var parts := res.split("x")
		var window := Vector2(float(parts[0]), float(parts[1]))
		var s := stretch_scale(window)
		var sub_min := subtitle_min * window.y / 1080.0   # a share of the screen's height, as at 1080p
		var sub_want := subtitle_want * window.y / 1080.0
		print("@@textsize-scale %s %.4f" % [res, s])
		var base := base_size()
		if _integer() and (base.x > window.x or base.y > window.y):
			print("@@textsize-cutoff %s %dx%d" % [res, base.x, base.y])
		for path in scenes:
			var packed := load(path) as PackedScene
			if packed == null:
				print("@@textsize-error %s|cannot be loaded" % path)
				continue
			var scene := packed.instantiate()
			root.add_child(scene)
			await process_frame   # _ready may set text, fonts or theme overrides
			var stack: Array[Node] = [scene]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				for child in n.get_children():
					stack.push_back(child)
				var c := n as Control
				if c == null or not TEXT_CONTROLS.has(c.get_class()):
					continue
				var subtitle := in_group(c, scene, subtitle_group)
				if not subtitle and not c.is_visible_in_tree():
					continue
				var rich := c is RichTextLabel
				var font_size := c.get_theme_font_size("normal_font_size" if rich else "font_size")
				var font := c.get_theme_font("normal_font" if rich else "font")
				var node_scale := c.get_global_transform_with_canvas().get_scale().y   # the node's own and its parents' scale
				var em := font_size * s * node_scale
				var cap := glyph_height(font, "H", em)
				var xh := glyph_height(font, "x", em)
				if subtitle:
					var sub_verdict := "FAIL" if em < sub_min else ("WARN" if em < sub_want else "ok")
					print("@@textsize-subtitle %s|%s|%s|%d|%.2f|%.2f|%.2f|%.2f|%s" % [res, path, scene.get_path_to(c), font_size, em, cap, sub_min, sub_want, sub_verdict])
					if not c.is_visible_in_tree():
						continue
				var verdict := "ok"
				if em < min_px:
					verdict = "FAIL"   # the font size itself is under the minimum: fails under any reading of the rule
				elif cap < min_px or em < want_px:
					verdict = "WARN"   # capitals drawn under the minimum, or under the recommended size
				print("@@textsize %s|%s|%s|%d|%.2f|%.2f|%.2f|%s" % [res, path, scene.get_path_to(c), font_size, em, cap, xh, verdict])
			scene.queue_free()
			await process_frame
	quit(0)


func _integer() -> bool:
	return str(ProjectSettings.get_setting("display/window/stretch/scale_mode", "fractional")) == "integer"


# The control, or one of its parents up to the scene's root, is in the group.
static func in_group(c: Node, scene: Node, group: StringName) -> bool:
	var n := c
	while n != null:
		if n.is_in_group(group):
			return true
		if n == scene:
			return false
		n = n.get_parent()
	return false


static func base_size() -> Vector2:
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
		ProjectSettings.get_setting("display/window/size/viewport_height", 648))


# From the project's base canvas to window pixels (stretch mode canvas_items or viewport; with "disabled" the canvas is
# drawn 1:1 and only the scale factor applies).
static func stretch_scale(window: Vector2) -> float:
	var base := base_size()
	var mode := str(ProjectSettings.get_setting("display/window/stretch/mode", "disabled"))
	var aspect := str(ProjectSettings.get_setting("display/window/stretch/aspect", "keep"))
	var factor := float(ProjectSettings.get_setting("display/window/stretch/scale", 1.0))
	var integer := str(ProjectSettings.get_setting("display/window/stretch/scale_mode", "fractional")) == "integer"
	if mode == "disabled":
		return factor
	# Every aspect but "ignore" ends at min(sx, sy) (bars or more room on the other axis); "ignore" scales the axes apart,
	# and text height follows y.
	var s := window.y / base.y if aspect == "ignore" else minf(window.x / base.x, window.y / base.y)
	s *= factor
	if integer:
		s = maxf(floorf(s), 1.0)   # floored after the factor, never below 1: a base bigger than the window is cut off
	return s


static func glyph_height(font: Font, ch: String, px: float) -> float:
	if font == null or font.get_rids().is_empty():
		return px
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	var glyph := ts.font_get_glyph_index(rid, 100, ch.unicode_at(0), 0)
	return ts.font_get_glyph_size(rid, Vector2i(100, 0), glyph).y * px / 100.0
