extends Node
# Prints the same error twice with different numbers, as a game does from a loop: one error key. ERROR_KEYS_FIXTURE=2
# adds a second, different error.

func _ready() -> void:
	for wave in [7, 12]:
		push_error("Wave %d spawned %d enemies outside the arena" % [wave, wave * 3])
	if OS.get_environment("ERROR_KEYS_FIXTURE") == "2":
		push_error("The arena has no exit")
