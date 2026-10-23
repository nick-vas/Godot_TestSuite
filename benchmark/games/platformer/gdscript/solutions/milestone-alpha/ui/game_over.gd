extends Control
## The end of a lost run: its score and the best.

signal menu_pressed

var _points := 0
var _best := 0

@onready var _title: Label = $Box/Title
@onready var _score: Label = $Box/ScoreLabel
@onready var _best_label: Label = $Box/BestLabel
@onready var _menu: Button = $Box/MenuButton


func setup(points: int, best: int) -> void:
	_points = points
	_best = best


func _ready() -> void:
	_menu.pressed.connect(menu_pressed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("GAMEOVER_TITLE")
	_score.text = tr("GAMEOVER_SCORE") % _points
	_best_label.text = tr("GAMEOVER_BEST") % _best
	_menu.text = tr("GAMEOVER_MENU")
