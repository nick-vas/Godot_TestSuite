# Lays out each scene at several screen profiles (phones, a tablet, an ultrawide monitor) and reports Controls and
# TouchScreenButtons that are off screen, inside a profile's unsafe area (a notch, the status bar, the home indicator), or
# too small to touch or click. With --min-control-dp above 0 it also reports, on touch profiles, on-screen game controls
# under that size (small-control): every TouchScreenButton and every Control in the group "touch_control", the controls
# a player presses without looking at them. Layout needs no rendering, so this runs headless.
#   godot --headless --path <project> -s layout.gd -- --scenes=res://ui/menu.tscn "--profiles=phone_portrait;tablet"
#         --min-dp=48 --min-css=24 --min-control-dp=75 --checks=off-screen,unsafe-area,small-target,small-control
# Profiles are separated by ";". A profile is a built-in name or name:WIDTHxHEIGHT@DPI[:touch][:insets=LEFT,TOP,RIGHT,BOTTOM].
# If the game has a SafeArea autoload with set_insets(left, top, right, bottom) (SetInsets in C#), the profile's insets are
# passed to it first, so the game's own safe-area handling is what gets measured (a fake notch).
# Prints "@@layout <profile>|<scene>|<node path>|<kind>|<detail>" per problem, "@@layout-checked <profile> <count>" per
# profile and "@@layout-error <scene>|<message>" when a scene cannot be loaded. Exits 0; the runner judges.
extends SceneTree

const BUILTIN := {
	# A Pixel 7-class phone: 1080x2400 at about 420 dpi; a status bar or cutout at the top, the gesture bar at the bottom.
	"phone_portrait": {"size": Vector2i(1080, 2400), "dpi": 420.0, "touch": true, "insets": [0, 128, 0, 66]},
	"phone_landscape": {"size": Vector2i(2400, 1080), "dpi": 420.0, "touch": true, "insets": [128, 0, 128, 66]},
	# An iPad-class tablet: 2048x1536 at 264 dpi; the status bar and the home indicator.
	"tablet": {"size": Vector2i(2048, 1536), "dpi": 264.0, "touch": true, "insets": [0, 48, 0, 40]},
	# A 34-inch ultrawide monitor: about 110 dpi, a mouse, no insets.
	"ultrawide": {"size": Vector2i(3440, 1440), "dpi": 110.0, "touch": false, "insets": [0, 0, 0, 0]},
	# The Steam Deck: 1280x800 on a 7-inch screen, about 216 dpi (the OLED model's 7.4 inches, about 204). It has a
	# touchscreen, but games are played with its controls and trackpads, so targets are judged as pointer targets.
	"steam_deck": {"size": Vector2i(1280, 800), "dpi": 216.0, "touch": false, "insets": [0, 0, 0, 0]},
}

var _opt := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_opt[arg.get_slice("=", 0).trim_prefix("--")] = arg.substr(arg.find("=") + 1)
	_run.call_deferred()


func _run() -> void:
	var scenes := str(_opt.get("scenes", "")).split(",", false)
	var names := str(_opt.get("profiles", "phone_portrait;phone_landscape;tablet;ultrawide")).split(";", false)
	var min_dp := float(_opt.get("min-dp", "48"))      # Android: 48 dp. Apple: 44 pt, about the same physical size.
	var min_css := float(_opt.get("min-css", "24"))    # WCAG 2.2 SC 2.5.8 (AA): 24 CSS px for pointer targets.
	# Thumb controls used without looking: working ones in a GDC talk on touch controls were 75 points, about 75 dp
	# (docs/gdc/controls-you-can-feel.md). 0 turns the check off.
	var min_control_dp := float(_opt.get("min-control-dp", "0"))
	var checks := str(_opt.get("checks", "off-screen,unsafe-area,small-target,small-control")).split(",", false)
	var safe_area := root.get_node_or_null("SafeArea")
	var setter := ""
	if safe_area != null:
		setter = "set_insets" if safe_area.has_method("set_insets") else ("SetInsets" if safe_area.has_method("SetInsets") else "")
	for profile_text in names:
		var p := _profile(profile_text.strip_edges())
		if p.is_empty():
			print("@@layout-error %s|unknown profile (use a built-in name or name:WIDTHxHEIGHT@DPI[:touch][:insets=L,T,R,B])" % profile_text)
			continue
		root.size = p.size
		await process_frame
		if setter != "":
			safe_area.call(setter, p.insets[0], p.insets[1], p.insets[2], p.insets[3])
		var safe_win := Rect2(p.insets[0], p.insets[1], p.size.x - p.insets[0] - p.insets[2], p.size.y - p.insets[1] - p.insets[3])
		var checked := 0
		for scene_path in scenes:
			var packed := load(scene_path.strip_edges()) as PackedScene
			if packed == null:
				print("@@layout-error %s|cannot be loaded" % scene_path)
				continue
			var scene := packed.instantiate()
			root.add_child(scene)
			# Containers sort on the next frame; two frames let nested containers settle.
			await process_frame
			await process_frame
			checked += _check(p, scene_path, scene, safe_win, min_dp, min_css, min_control_dp, checks)
			scene.queue_free()
			await process_frame
		if setter != "":
			safe_area.call(setter, 0, 0, 0, 0)
		print("@@layout-checked %s %d" % [p.name, checked])
	quit(0)


func _profile(text: String) -> Dictionary:
	if BUILTIN.has(text):
		var b: Dictionary = BUILTIN[text].duplicate(true)
		b["name"] = text
		return b
	var parts := text.split(":")
	if parts.size() < 2 or not parts[1].contains("@") or not parts[1].get_slice("@", 0).contains("x"):
		return {}
	var dims := parts[1].get_slice("@", 0).split("x")
	var out := {"name": parts[0], "size": Vector2i(int(dims[0]), int(dims[1])), "dpi": float(parts[1].get_slice("@", 1)),
		"touch": false, "insets": [0, 0, 0, 0]}
	if out.size.x <= 0 or out.size.y <= 0 or out.dpi <= 0.0:
		return {}
	for extra in parts.slice(2):
		if extra == "touch":
			out.touch = true
		elif extra.begins_with("insets="):
			var values := Array(extra.trim_prefix("insets=").split(",")).map(func(s: String) -> int: return int(s))
			if values.size() != 4:
				return {}
			out.insets = values
	return out


func _check(p: Dictionary, scene_path: String, scene: Node, safe_win: Rect2, min_dp: float, min_css: float,
		min_control_dp: float, checks: PackedStringArray) -> int:
	var win := Rect2(Vector2.ZERO, Vector2(p.size))
	var to_window := root.get_final_transform()   # canvas (stretched) coordinates -> window pixels
	var checked := 0
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for child in n.get_children():
			stack.push_back(child)
		var rect := Rect2()
		var interactive := true
		# A control the player presses without looking (a TouchScreenButton, or a Control in the group "touch_control"):
		# on touch profiles it is also judged against min-control-dp.
		var thumb := true
		var b := n as TouchScreenButton
		if b != null:
			# A Node2D, not a Control. Touch-only buttons are neither drawn nor pressed without a touchscreen.
			if not b.is_visible_in_tree() or (not p.touch and b.visibility_mode == TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY):
				continue
			var area := _touch_area(b)
			if not area.has_area():
				continue
			rect = to_window * (b.get_global_transform_with_canvas() * area)
		else:
			var c := n as Control
			if c == null or not c.is_visible_in_tree() or c.size.x <= 0 or c.size.y <= 0:
				continue
			thumb = c.is_in_group("touch_control")
			interactive = thumb or _is_interactive(c)
			var has_text := (c is Label or c is RichTextLabel) and str(c.get("text")).strip_edges() != ""
			if not interactive and not has_text:
				continue
			rect = to_window * (c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size))
		checked += 1
		var where := str(scene.get_path_to(n))
		# Content inside a ScrollContainer is meant to leave the screen.
		var scrolled := _inside_scroll(n)
		if not scrolled and not win.encloses(rect.grow(-0.5)):
			if checks.has("off-screen"):
				_report(p.name, scene_path, where, "off-screen", "%s is outside the %dx%d window" % [_r(rect), p.size.x, p.size.y])
		elif not scrolled and not safe_win.encloses(rect.grow(-0.5)):
			if checks.has("unsafe-area"):
				_report(p.name, scene_path, where, "unsafe-area", "%s is outside the safe area %s" % [_r(rect), _r(safe_win)])
		if interactive and checks.has("small-target"):
			var short_side := minf(rect.size.x, rect.size.y)
			if p.touch:
				var dp: float = short_side * 160.0 / float(p.dpi)
				if dp < min_dp:
					_report(p.name, scene_path, where, "small-target", "%.0f dp (%.1f mm, %.0f px), under %.0f dp" % [dp, short_side / p.dpi * 25.4, short_side, min_dp])
			else:
				var css: float = short_side * 96.0 / float(p.dpi)
				if css < min_css:
					_report(p.name, scene_path, where, "small-target", "%.0f CSS px (%.0f px), under %.0f" % [css, short_side, min_css])
		if thumb and p.touch and min_control_dp > 0.0 and checks.has("small-control"):
			var side := minf(rect.size.x, rect.size.y)
			var control_dp: float = side * 160.0 / float(p.dpi)
			if control_dp < min_control_dp:
				_report(p.name, scene_path, where, "small-control", "%.0f dp (%.1f mm, %.0f px), under %.0f dp" % [control_dp, side / p.dpi * 25.4, side, min_control_dp])
	return checked


# The part of a TouchScreenButton that takes touches, in its own coordinates. As Godot 4.7 hit-tests it: the shape, moved
# to the texture's centre when shape_centered is on and there is a texture (else left around the origin); without a
# shape, the texture's rectangle; with neither, nothing.
func _touch_area(b: TouchScreenButton) -> Rect2:
	var texture_size := b.texture_normal.get_size() if b.texture_normal != null else Vector2.ZERO
	if b.shape != null:
		var area := b.shape.get_rect()
		if b.shape_centered:
			area.position += texture_size * 0.5
		return area
	return Rect2(Vector2.ZERO, texture_size)


func _is_interactive(c: Control) -> bool:
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE and c.focus_mode == Control.FOCUS_NONE:
		return false
	return c is BaseButton or (c is Range and not c is ProgressBar) or c is LineEdit or c is TextEdit or c is ItemList \
		or c is TabBar or c is Tree


func _inside_scroll(n: Node) -> bool:
	var a := n.get_parent()
	while a != null:
		if a is ScrollContainer:
			return true
		a = a.get_parent()
	return false


func _report(profile: String, scene_path: String, where: String, kind: String, detail: String) -> void:
	print("@@layout %s|%s|%s|%s|%s" % [profile, scene_path, where, kind, detail])


func _r(r: Rect2) -> String:
	return "(%d,%d %dx%d)" % [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
