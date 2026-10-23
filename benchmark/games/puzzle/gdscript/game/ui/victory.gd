extends Control
## The end of the last level: every level solved, and the moves of the best solutions added up.

signal menu_pressed

var _total := 0

@onready var _title: Label = $Box/Title
@onready var _message: Label = $Box/MessageLabel
@onready var _menu: Button = $Box/MenuButton


func setup(total_moves: int) -> void:
	_total = total_moves


func _ready() -> void:
	_menu.pressed.connect(menu_pressed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("VICTORY_TITLE")
	_message.text = tr("VICTORY_MESSAGE") % _total
	_menu.text = tr("VICTORY_MENU")
