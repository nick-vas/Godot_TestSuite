extends Control
## The title menu, and the holder of whatever screen is showing: the game, settings, game over or victory.
## Screens are children of Main rather than scene changes, so the save and the loaded tables live in one place.

const GAME_SCENE := preload("res://game/game.tscn")
const SETTINGS_SCENE := preload("res://ui/settings.tscn")
const GAME_OVER_SCENE := preload("res://ui/game_over.tscn")
const VICTORY_SCENE := preload("res://ui/victory.tscn")

var options: LaunchOptions
var store: SaveStore
var save: Dictionary
var waves: Waves
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
	waves = Waves.from_files()
	_start.pressed.connect(start_game)
	_settings.pressed.connect(show_settings)
	_quit.pressed.connect(get_tree().quit)
	_refresh_text()
	if options.autoplay:
		start_game()


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


func start_game() -> void:
	var game := GAME_SCENE.instantiate()
	game.name = "Game"
	game.setup(waves, options, int(save.best))
	game.finished.connect(_on_game_finished)
	game.quit_requested.connect(show_menu)
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


func _on_game_finished(victory: bool, points: int) -> void:
	if points > int(save.best):
		save.best = points
		store.write(save)
	if options.autoplay:
		# A bot run ends here; free the game first so nothing is left in use when the engine exits.
		_close_screen.call_deferred()
		_quit_after_frames(3)
		return
	var screen := (VICTORY_SCENE if victory else GAME_OVER_SCENE).instantiate()
	screen.name = "Victory" if victory else "GameOver"
	screen.setup(points, int(save.best))
	screen.menu_pressed.connect(show_menu)
	# The game is still inside its own physics step; swap it out once that step is over.
	_show.call_deferred(screen)


## Lets the freed game's sounds stop before the engine exits, so the exit is clean.
func _quit_after_frames(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	get_tree().quit()
