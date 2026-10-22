# Checks the characters of every translated string against the fonts that would draw them, headless. Run by the l10n
# runner (lib/Localization.ps1):
#   godot --headless --path <project> -s <this file> -- --glyph-chars=<abs file> --glyph-themes=res://ui/hud.tres,...
# --glyph-chars is a file of code points, one per line in decimal: the characters of the translations, which the runner
# reads from the tables (an imported, compressed .translation lists its texts but not their keys). The fonts are the
# default one (the project theme's default font, else gui/theme/custom_font, else Godot's own) and every font of the
# project theme and of the given themes, each with its fallbacks.
# Font.has_char walks the fallbacks but never the system fonts that allow_system_fallback draws from, so what it lacks
# may be drawn on this machine and be a box on a player's (measured on 4.7.2, docs/localization.md). A SystemFont is
# found on the machine that runs the game, so what it has here proves nothing: characters that only a SystemFont in the
# chain could draw are listed apart. One line per font and finding:
#   @@glyphs-font <n>|<name>|<where>
#   @@glyphs-missing <n>|<code>,<code>,...                no font in the chain has these
#   @@glyphs-system <n>|<system font names>|<code>,...    only a SystemFont in the chain could draw these
#   @@glyphs-error <message>
extends SceneTree

# Godot's own limit on the fallback chain (font.cpp, MAX_FALLBACK_DEPTH).
const MAX_DEPTH := 64

var _fonts: Array[Font] = []
var _own: Dictionary = {}


func _initialize() -> void:
	var chars_file := ""
	var themes := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--glyph-chars="):
			chars_file = arg.trim_prefix("--glyph-chars=")
		elif arg.begins_with("--glyph-themes="):
			themes = arg.trim_prefix("--glyph-themes=").split(",", false)
	var codes := PackedInt32Array()
	for line in FileAccess.get_file_as_string(chars_file).split("\n", false):
		if line.strip_edges().is_valid_int():
			codes.append(int(line.strip_edges()))

	var project_theme := ThemeDB.get_project_theme()
	var default_font: Font = null
	if project_theme != null and project_theme.has_default_font():
		default_font = project_theme.default_font
	elif ThemeDB.get_default_theme().has_default_font():
		default_font = ThemeDB.get_default_theme().default_font
	else:
		default_font = ThemeDB.fallback_font
	_add(default_font, "default font")
	var theme_paths := PackedStringArray()
	if project_theme != null and project_theme.resource_path != "":
		theme_paths.append(project_theme.resource_path)
	for path in themes:
		if not theme_paths.has(path):
			theme_paths.append(path)
	for path in theme_paths:
		var theme := load(path) as Theme
		if theme == null:
			print("@@glyphs-error %s is not a Theme" % path)
			continue
		if theme.has_default_font():
			_add(theme.default_font, "%s default_font" % path)
		for type in theme.get_font_type_list():
			for item in theme.get_font_list(type):
				_add(theme.get_font(item, type), "%s %s/%s" % [path, type, item])

	for n in _fonts.size():
		_check(n, codes)
	quit()


func _add(font: Font, where: String) -> void:
	if font == null or _fonts.has(font):
		return
	_fonts.append(font)
	var name := font.resource_path
	if font == ThemeDB.fallback_font and name == "":
		name = "Godot's default font (%s)" % font.get_font_name()
	elif name == "":
		name = "a %s" % font.get_class()
	print("@@glyphs-font %d|%s|%s" % [_fonts.size() - 1, name, where])


func _check(n: int, codes: PackedInt32Array) -> void:
	var font := _fonts[n]
	var bundled: Array[Font] = []
	var system: Array[SystemFont] = []
	_walk(font, 0, bundled, system, {})
	var missing := PackedStringArray()
	var only_system := PackedStringArray()
	for code in codes:
		if system.is_empty():
			if not font.has_char(code):
				missing.append(str(code))
		elif not bundled.any(func(f: Font) -> bool: return _own_has(f, code)):
			only_system.append(str(code))
	if not missing.is_empty():
		print("@@glyphs-missing %d|%s" % [n, ",".join(missing)])
	if not only_system.is_empty():
		var names := PackedStringArray()
		for f in system:
			names.append(", ".join(f.font_names) if not f.font_names.is_empty() else "no font name")
		print("@@glyphs-system %d|%s|%s" % [n, "; ".join(names), ",".join(only_system)])


# The fonts that can draw for this one: itself (a FontVariation draws with its base font's face) and its fallbacks, as
# Font::_update_rids walks them. A FontVariation without fallbacks of its own uses its base font's.
func _walk(font: Font, depth: int, bundled: Array[Font], system: Array[SystemFont], seen: Dictionary) -> void:
	if font == null or depth > MAX_DEPTH or seen.has(font):
		return
	seen[font] = true
	var fallbacks: Array = font.fallbacks
	if font is FontVariation:
		var base: Font = (font as FontVariation).base_font
		if base == null:
			base = ThemeDB.fallback_font
		if fallbacks.is_empty():
			_walk(base, depth + 1, bundled, system, seen)
		else:
			_walk_face(base, bundled, system)
	elif font is SystemFont:
		system.append(font as SystemFont)
	else:
		bundled.append(font)
	for fallback in fallbacks:
		_walk(fallback as Font, depth + 1, bundled, system, seen)


# Only the face of a variation's base font, when the variation has fallbacks of its own.
func _walk_face(font: Font, bundled: Array[Font], system: Array[SystemFont]) -> void:
	for _depth in MAX_DEPTH:
		if not (font is FontVariation):
			break
		font = (font as FontVariation).base_font if (font as FontVariation).base_font != null else ThemeDB.fallback_font
	if font is SystemFont:
		system.append(font as SystemFont)
	elif font != null:
		bundled.append(font)


# A bundled font's own characters, without its fallbacks: a copy with none.
func _own_has(font: Font, code: int) -> bool:
	if not _own.has(font):
		var copy := font.duplicate() as Font
		copy.fallbacks = []
		_own[font] = copy
	return (_own[font] as Font).has_char(code)
