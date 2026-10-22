extends Node
# Speaks the focused object's description when the assist action is pressed. project.godot leaves
# audio/general/text_to_speech at its default (off), so doctor warns that the first line is late or lost.

var description := ""

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("assist") and description != "":
		var voices := DisplayServer.tts_get_voices_for_language(TranslationServer.get_locale().split("_")[0])
		if not voices.is_empty():
			DisplayServer.tts_speak(description, voices[0], 50, 1.0, 1.0, 1, true)
