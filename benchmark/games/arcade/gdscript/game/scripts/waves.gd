class_name Waves
extends RefCounted
## The levels and their waves from data/levels.json (one row per wave) and the enemies from data/enemies.json.
## Kept free of the engine's scenes so the tests can read the real tables.

const LEVELS_PATH := "res://data/levels.json"
const ENEMIES_PATH := "res://data/enemies.json"

## Enemy id -> its row (hp, points, drift, fire, color, boss).
var enemies := {}
## Level number -> its wave rows, in file order.
var _levels := {}


static func from_files(levels_path := LEVELS_PATH, enemies_path := ENEMIES_PATH) -> Waves:
	var waves := Waves.new()
	waves.load_tables(_read_rows(enemies_path), _read_rows(levels_path))
	return waves


func load_tables(enemy_rows: Array, wave_rows: Array) -> void:
	for row: Dictionary in enemy_rows:
		enemies[str(row.id)] = row
	for row: Dictionary in wave_rows:
		var level := int(row.level)
		if not _levels.has(level):
			_levels[level] = []
		_levels[level].append(row)


func level_count() -> int:
	return _levels.size()


## The waves of a level: dictionaries with enemy, count, formation (line, v, grid) and speed.
func waves(level: int) -> Array:
	return _levels.get(level, [])


func enemy(id: String) -> Dictionary:
	return enemies.get(id, {})


## The boss of a level (an enemy marked boss in one of its waves), or an empty dictionary.
func boss(level: int) -> Dictionary:
	for wave: Dictionary in waves(level):
		var row := enemy(str(wave.enemy))
		if row.get("boss", false):
			return row
	return {}


static func _read_rows(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("Waves: %s is missing" % path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Waves: %s is not a JSON array" % path)
		return []
	return parsed
