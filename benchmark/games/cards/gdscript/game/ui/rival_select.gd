extends Control
## The ladder of rivals, one button each: open once the rival before is beaten, with the wins against a beaten one.

signal rival_chosen(id: int)
signal closed

var _rivals: Rivals
var _save: Dictionary

@onready var _title: Label = $Box/Title
@onready var _grid: GridContainer = $Box/Grid
@onready var _back: Button = $Box/BackButton


func setup(rivals: Rivals, save: Dictionary) -> void:
	_rivals = rivals
	_save = save


func _ready() -> void:
	if _rivals == null:
		_rivals = Rivals.from_files()
	if _save.is_empty():
		_save = SaveStore.defaults()
	for id in range(1, _rivals.count() + 1):
		var button := Button.new()
		button.name = "Rival%dButton" % id
		button.custom_minimum_size = Vector2(320, 88)
		button.add_theme_font_size_override("font_size", 22)
		button.disabled = not Ladder.is_unlocked(_save, id)
		button.pressed.connect(rival_chosen.emit.bind(id))
		_grid.add_child(button)
	_back.pressed.connect(closed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("SELECT_TITLE")
	_back.text = tr("SELECT_BACK")
	for id in range(1, _grid.get_child_count() + 1):
		var button: Button = _grid.get_child(id - 1)
		button.text = tr("SELECT_RIVAL") % [id, tr(str(_rivals.rival(id).get("name", "")))]
		var wins := Ladder.wins(_save, id)
		if wins > 0:
			button.text += "  " + tr("SELECT_WINS") % wins
