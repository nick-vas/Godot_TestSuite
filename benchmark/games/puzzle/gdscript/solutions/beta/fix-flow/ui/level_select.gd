extends Control
## The levels, one button each: open once the level before is solved, with the best moves of a solved one.

signal level_chosen(id: int)
signal closed

var _levels: Levels
var _save: Dictionary

@onready var _title: Label = $Box/Title
@onready var _grid: GridContainer = $Box/Grid
@onready var _back: Button = $Box/BackButton


func setup(levels: Levels, save: Dictionary) -> void:
	_levels = levels
	_save = save


func _ready() -> void:
	if _levels == null:
		_levels = Levels.from_file()
	if _save.is_empty():
		_save = SaveStore.defaults()
	for id in range(1, _levels.level_count() + 1):
		var button := Button.new()
		button.name = "Level%dButton" % id
		button.custom_minimum_size = Vector2(150, 88)
		button.add_theme_font_size_override("font_size", 22)
		button.disabled = not Progress.is_unlocked(_save, id)
		button.pressed.connect(level_chosen.emit.bind(id))
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
		var best := Progress.best(_save, id)
		button.text = tr("SELECT_LEVEL") % id
		if best > 0:
			button.text += "\n" + tr("SELECT_BEST") % best
