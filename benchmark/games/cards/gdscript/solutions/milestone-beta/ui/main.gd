extends Control
## The title menu, and the holder of whatever screen is showing: the rival select, the game, settings or
## victory. Screens are children of Main rather than scene changes, so the save and the data live in one place.

const GAME_SCENE := preload("res://game/game.tscn")
const RIVAL_SELECT_SCENE := preload("res://ui/rival_select.tscn")
const SETTINGS_SCENE := preload("res://ui/settings.tscn")
const VICTORY_SCENE := preload("res://ui/victory.tscn")

var options: LaunchOptions
var store: SaveStore
var save: Dictionary
var rivals: Rivals
var cards: Cards
var _screen: Node

@onready var _menu: Control = $Menu
@onready var _title: Label = $Menu/Title
@onready var _start: Button = $Menu/StartButton
@onready var _continue: Button = $Menu/ContinueButton
@onready var _settings: Button = $Menu/SettingsButton
@onready var _quit: Button = $Menu/QuitButton
@onready var _version: Label = $Menu/VersionLabel


func _ready() -> void:
	options = LaunchOptions.from_command_line()
	store = SaveStore.new()
	store.enabled = not options.no_save
	save = store.read()
	apply_settings(save.settings)
	rivals = Rivals.from_files()
	cards = Cards.from_file()
	_start.pressed.connect(show_rival_select)
	_continue.pressed.connect(continue_duel)
	_settings.pressed.connect(show_settings)
	_quit.pressed.connect(get_tree().quit)
	_refresh_text()
	show_menu()
	if options.autoplay:
		start_rival(options.rival)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("MENU_TITLE")
	_start.text = tr("MENU_START")
	_continue.text = tr("MENU_CONTINUE")
	_settings.text = tr("MENU_SETTINGS")
	_quit.text = tr("MENU_QUIT")
	_version.text = tr("MENU_VERSION") % ProjectSettings.get_setting("application/config/version", "")


static func apply_settings(settings: Dictionary) -> void:
	TranslationServer.set_locale(str(settings.get("locale", "en")))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.get("volume", 1.0)), 0.0001)))


func show_rival_select() -> void:
	var select := RIVAL_SELECT_SCENE.instantiate()
	select.name = "RivalSelect"
	select.setup(rivals, save)
	select.rival_chosen.connect(start_rival)
	select.closed.connect(show_menu)
	_show(select)


func start_rival(id: int) -> void:
	_start_game(id, {})


## Carries on the duel kept in the save.
func continue_duel() -> void:
	if typeof(save.duel) == TYPE_DICTIONARY:
		_start_game(0, save.duel)


func _start_game(id: int, saved: Dictionary) -> void:
	var game := GAME_SCENE.instantiate()
	game.name = "Game"
	game.setup(rivals, cards, options, id, saved)
	game.duel_over.connect(_on_duel_over)
	game.checkpoint.connect(_on_checkpoint)
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
	_continue.visible = typeof(save.duel) == TYPE_DICTIONARY


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


## The player's turn began: the duel is kept so Continue can carry on from here.
func _on_checkpoint(data: Dictionary) -> void:
	save.duel = data
	store.write(save)


func _on_duel_over(rival: int, won: bool) -> void:
	Ladder.record(save, rival, won)
	save.duel = null
	store.write(save)


func _on_finished(victory: bool) -> void:
	if options.autoplay:
		# A bot run ends here; free the game first so nothing is left in use when the engine exits.
		_close_screen.call_deferred()
		_quit_after_frames(3)
		return
	if not victory:
		show_menu.call_deferred()
		return
	var screen := VICTORY_SCENE.instantiate()
	screen.name = "Victory"
	screen.setup(Ladder.total_wins(save))
	screen.menu_pressed.connect(show_menu)
	# The game is still inside its own physics step or a button's signal; swap it out once that is over.
	_show.call_deferred(screen)


## Lets the freed game's sounds stop before the engine exits, so the exit is clean.
func _quit_after_frames(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	get_tree().quit()
