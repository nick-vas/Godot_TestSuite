extends Control
## Who made what, from credits.json (written by the kit's credits command from assets.json).

signal closed

const CREDITS_PATH := "res://credits.json"

@onready var _title: Label = $Box/Title
@onready var _text: Label = $Box/Text
@onready var _back: Button = $Box/BackButton


func _ready() -> void:
	_back.pressed.connect(closed.emit)
	_text.text = "\n".join(read_lines(CREDITS_PATH))
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("CREDITS_TITLE")
	_back.text = tr("CREDITS_BACK")


## The credits as lines: each section's heading (a translation key) and its entries, empty sections left out.
static func read_lines(path: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if not FileAccess.file_exists(path):
		return lines
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return lines
	for section: Variant in parsed.get("sections", []):
		if typeof(section) != TYPE_DICTIONARY or section.get("entries", []).is_empty():
			continue
		lines.append(TranslationServer.translate(str(section.get("heading", ""))))
		for entry: Variant in section.entries:
			if typeof(entry) == TYPE_DICTIONARY:
				lines.append("%s (%s)" % [entry.get("text", entry.get("title", "")), entry.get("licence", "")])
		lines.append("")
	return lines
