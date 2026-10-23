class_name SaveStore
extends RefCounted
## The player's save, JSON in user://save.json: version, solved (level id -> fewest moves), settings (volume, locale).

const VERSION := 2
const DEFAULT_PATH := "user://save.json"

var path: String
## Off with --no-save, so bot runs and tests never touch the player's save.
var enabled := true


func _init(save_path := DEFAULT_PATH) -> void:
	path = save_path


static func defaults() -> Dictionary:
	return {"version": VERSION, "solved": {}, "settings": {"volume": 1.0, "locale": "en"}}


## The save as the current version, or the defaults when there is none or it cannot be read.
func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return defaults()
	# A damaged save is the player's loss, not an engine error: start from the defaults.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return defaults()
	return migrate(json.data)


## The saved data, with defaults for anything missing.
static func migrate(raw: Dictionary) -> Dictionary:
	var data := defaults()
	var solved: Variant = raw.get("solved", {})
	if typeof(solved) == TYPE_DICTIONARY:
		for key: Variant in solved:
			data.solved[str(key)] = int(solved[key])
	var settings: Variant = raw.get("settings", {})
	if typeof(settings) == TYPE_DICTIONARY:
		data.settings.volume = clampf(float(settings.get("volume", 1.0)), 0.0, 1.0)
		data.settings.locale = str(settings.get("locale", "en"))
	return data


func write(data: Dictionary) -> bool:
	if not enabled:
		return false
	var out := defaults()
	out.solved = data.get("solved", {})
	out.settings = data.get("settings", out.settings)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(out, "  "))
	return true
