extends Control
## The title menu, and the holder of whatever screen is showing: the level select, the game, settings or victory. Screens are children of Main rather than scene changes, so the save and the levels live in one place.

const GAME_SCENE := preload("res://game/game.tscn")
const LEVEL_SELECT_SCENE := preload("res://ui/level_select.tscn")
const SETTINGS_SCENE := preload("res://ui/settings.tscn")
const VICTORY_SCENE := preload("res://ui/victory.tscn")

var options: LaunchOptions
var store: SaveStore
var save: Dictionary
var levels: Levels
var _screen: Node

@onready var _menu: Control = $Menu
@onready var _title: Label = $Menu/Title
@onready var _start: Button = $Menu/StartButton
@onready var _settings: Button = $Menu/SettingsButton
@onready var _quit: Button = $Menu/QuitButton
@onready var _version: Label = $Menu/VersionLabel


func _ready() -> void:
	options = LaunchOptions.from_command_line()
	store = SaveStore.new()
	store.enabled = not options.no_save
	save = store.read()
	apply_settings(save.settings)
	levels = Levels.from_file()
	_start.pressed.connect(show_level_select)
	_settings.pressed.connect(show_settings)
	_quit.pressed.connect(get_tree().quit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("MENU_TITLE")
	_start.text = tr("MENU_START")
	_settings.text = tr("MENU_SETTINGS")
	_quit.text = tr("MENU_QUIT")
	_version.text = tr("MENU_VERSION") % ProjectSettings.get_setting("application/config/version", "")


static func apply_settings(settings: Dictionary) -> void:
	TranslationServer.set_locale(str(settings.get("locale", "en")))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.get("volume", 1.0)), 0.0001)))


func show_level_select() -> void:
	var select := LEVEL_SELECT_SCENE.instantiate()
	select.name = "LevelSelect"
	select.setup(levels, save)
	select.level_chosen.connect(start_level)
	select.closed.connect(show_menu)
	_show(select)


func start_level(id: int) -> void:
	var game := GAME_SCENE.instantiate()
	game.name = "Game"
	game.setup(levels, options, id)
	game.level_solved.connect(_on_level_solved)
	game.finished.connect(_on_finished)
	game.menu_requested.connect(show_menu)
	_show(game)


func show_settings() -> void:
	var settings := SETTINGS_SCENE.instantiate()
	settings.name = "Settings"
	settings.setup(save)
	settings.closed.connect(_on_settings_closed)
	_show(settings)


func show_menu() -> void:
	_close_screen()
	_menu.visible = true


func _show(screen: Node) -> void:
	_close_screen()
	_menu.visible = false
	_screen = screen
	add_child(screen)


func _close_screen() -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
		_screen = null


func _on_settings_closed() -> void:
	store.write(save)
	show_menu()


## A solved level is kept with its moves.
func _on_level_solved(level: int, moves: int) -> void:
	Progress.record(save, level, moves)
	store.write(save)


func _on_finished(victory: bool) -> void:
	if not victory:
		show_menu.call_deferred()
		return
	var screen := VICTORY_SCENE.instantiate()
	screen.name = "Victory"
	screen.setup(Progress.total_moves(save))
	screen.menu_pressed.connect(show_menu)
	# The game is still inside its own physics step or a button's signal; swap it out once that is over.
	_show.call_deferred(screen)

