extends Node

func _ready() -> void:
	if Steam.isSteamRunningOnSteamDeck():
		get_window().size = Vector2i(1280, 800)
