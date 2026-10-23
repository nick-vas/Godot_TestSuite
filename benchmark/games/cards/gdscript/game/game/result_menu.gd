extends CanvasLayer
## The panel over a finished duel: won or lost, Next (Finish after the last rival) once won, Rematch, and Back to menu.

signal next_pressed
signal rematch_pressed
signal menu_pressed

var _won := false
var _next_key := "RESULT_NEXT"

@onready var _title: Label = $Box/Title
@onready var _message: Label = $Box/MessageLabel
@onready var _next: Button = $Box/NextButton
@onready var _rematch: Button = $Box/RematchButton
@onready var _menu: Button = $Box/MenuButton


func _ready() -> void:
	visible = false
	_next.pressed.connect(next_pressed.emit)
	_rematch.pressed.connect(rematch_pressed.emit)
	_menu.pressed.connect(menu_pressed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("RESULT_WON") if _won else tr("RESULT_LOST")
	_message.text = tr("RESULT_WON_MESSAGE") if _won else tr("RESULT_LOST_MESSAGE")
	_next.text = tr(_next_key)
	_rematch.text = tr("RESULT_REMATCH")
	_menu.text = tr("RESULT_MENU")


## next_key: the Next button's text key; the button shows only after a win.
func open(won: bool, next_key: String) -> void:
	_won = won
	_next_key = next_key
	_next.visible = won
	_refresh_text()
	visible = true


func close() -> void:
	visible = false
