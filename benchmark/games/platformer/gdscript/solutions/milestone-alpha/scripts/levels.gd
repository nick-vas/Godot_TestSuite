class_name Levels
extends RefCounted
## The levels in order from data/levels.json (number, scene, name) and the beetles from data/beetles.json (speed,
## points, colour). Kept free of the engine's scenes so the tests can read the real tables.

const LEVELS_PATH := "res://data/levels.json"
const BEETLES_PATH := "res://data/beetles.json"

## Beetle id -> its row.
var beetles := {}
## Level rows, sorted by number.
var _rows: Array = []


static func from_files(levels_path := LEVELS_PATH, beetles_path := BEETLES_PATH) -> Levels:
	var levels := Levels.new()
	levels.load_tables(_read_rows(beetles_path), _read_rows(levels_path))
	return levels


func load_tables(beetle_rows: Array, level_rows: Array) -> void:
	for row: Dictionary in beetle_rows:
		beetles[str(row.id)] = row
	_rows = level_rows.duplicate()
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.number) < int(b.number))


func count() -> int:
	return _rows.size()


## The row of level number (1 is the first): id, number, scene, name. Empty when there is no such level.
func level(number: int) -> Dictionary:
	for row: Dictionary in _rows:
		if int(row.number) == number:
			return row
	return {}


func beetle(id: String) -> Dictionary:
	return beetles.get(id, {})


static func _read_rows(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("Levels: %s is missing" % path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Levels: %s is not a JSON array" % path)
		return []
	return parsed
