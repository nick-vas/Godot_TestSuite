class_name Levels
extends RefCounted
## The hand-made levels from data/levels.json: an array of rows with id (1, 2, ...), rows (the tiles, one string per
## line, in Board's letters) and par (the fewest moves that solve it, which the tests hold to the solver's answer).

const PATH := "res://data/levels.json"

## Level id -> its row, in the file's order.
var _levels := {}


static func from_file(path := PATH) -> Levels:
	var levels := Levels.new()
	levels.load_rows(_read_rows(path))
	return levels


func load_rows(rows: Array) -> void:
	for row: Dictionary in rows:
		_levels[int(row.id)] = row


func level_count() -> int:
	return _levels.size()


func has_level(id: int) -> bool:
	return _levels.has(id)


func level(id: int) -> Dictionary:
	return _levels.get(id, {})


func par(id: int) -> int:
	return int(level(id).get("par", 0))


## A fresh board of a level, at its start.
func board(id: int) -> Board:
	return Board.from_rows(level(id).get("rows", []))


static func _read_rows(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("Levels: %s is missing" % path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Levels: %s is not a JSON array" % path)
		return []
	return parsed
