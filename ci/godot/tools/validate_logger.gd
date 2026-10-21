# Collects the engine's errors in-process for validate.gd (Godot 4.5+ has Logger). Errors also go to stderr, which can reach the
# kit's log out of order with validate.gd's markers on stdout; collecting them here ties each one to the file that caused it.
extends Logger

const PREFIX := {0: "ERROR", 2: "SCRIPT ERROR", 3: "SHADER ERROR"}  # ErrorType; warnings (1) are not failures

var _lines: PackedStringArray = []
var _mutex := Mutex.new()


func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if not PREFIX.has(error_type):
		return
	var text := rationale if rationale != "" else code
	var at := " (%s:%d)" % [file, line] if file.begins_with("res://") else (" (line %d)" % line if file == "" and line > 0 else "")
	_mutex.lock()
	_lines.append("%s: %s%s" % [PREFIX[error_type], text, at])
	_mutex.unlock()


func take() -> PackedStringArray:
	_mutex.lock()
	var lines := _lines.duplicate()
	_lines.clear()
	_mutex.unlock()
	return lines
