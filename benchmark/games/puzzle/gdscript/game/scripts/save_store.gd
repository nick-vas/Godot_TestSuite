class_name SaveStore
extends RefCounted
## The player's save, JSON in user://save.json: version, solved (level id -> fewest moves), settings (volume, locale).
## Version 2 is current; version 1 kept only a list of cleared level ids and had no settings, and players still have such files.

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


## Any version's data as the current version.
static func migrate(raw: Dictionary) -> Dictionary:
	var data := defaults()
	var version := int(raw.get("version", 1))
	if version == 1:
		# Version 1 did not keep moves: a cleared level is solved, its best unknown (0).
		var cleared: Variant = raw.get("cleared", [])
		if typeof(cleared) == TYPE_ARRAY:
			for id: Variant in cleared:
				data.solved[str(int(id))] = 0
		return data
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
