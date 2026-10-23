extends CanvasLayer
## The panel over a solved level: the moves against par, Next (Finish on the last level, none on a daily drift) and
## Back to menu.

signal next_pressed
signal menu_pressed

var _moves := 0
var _par := 0
var _next_key := "SOLVED_NEXT"

@onready var _title: Label = $Box/Title
@onready var _moves_label: Label = $Box/MovesLabel
@onready var _next: Button = $Box/NextButton
@onready var _menu: Button = $Box/MenuButton


func _ready() -> void:
	visible = false
	_next.pressed.connect(next_pressed.emit)
	_menu.pressed.connect(menu_pressed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("SOLVED_TITLE")
	_moves_label.text = tr("SOLVED_MOVES") % [_moves, _par]
	_next.text = tr(_next_key) if _next_key != "" else ""
	_menu.text = tr("SOLVED_MENU")


## next_key: the Next button's text key, or "" for no Next button.
func open(moves: int, par: int, next_key: String) -> void:
	_moves = moves
	_par = par
	_next_key = next_key
	_next.visible = next_key != ""
	_refresh_text()
	visible = true


func close() -> void:
	visible = false
