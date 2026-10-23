extends Node2D
## One level being played: the board, the mote's slide, undo and restart, the HUD, pause and the solved panel. Main
## starts it with setup(); on its own (a flow, a test, the editor) it reads the command line and the levels itself.
## A move lands in Board at once; the view then slides the mote over a few ticks while input waits.

signal level_solved(level: int, moves: int)
## The last level is solved.
signal finished(victory: bool)
signal menu_requested

## Ticks the mote takes per tile of a slide: quick, like ice, but slow enough to follow.
const SLIDE_TICKS_PER_TILE := 2
const BOARD_CENTER := Vector2(640, 410)
const MOVE_ACTIONS := {"move_up": Vector2i.UP, "move_right": Vector2i.RIGHT, "move_down": Vector2i.DOWN, "move_left": Vector2i.LEFT}

var levels: Levels
var options: LaunchOptions
var board: Board
var solver := Solver.new()
var level := 1
var par := 0
## "playing", "sliding" (input waits for the mote), "solved" or "done".
var state := "playing"
## The exit cannot be reached from here any more: the HUD says to undo or restart.
var stuck := false
## How many times the game asked the solver whether the exit can still be reached, for the performance test.
var stuck_checks := 0

var _first_level := 0
var _slide_ticks := 0
var _slide_total := 0
var _slide_from := Vector2i.ZERO

@onready var grid: Node2D = $Grid
@onready var _level_label: Label = $HUD/LevelLabel
@onready var _moves_label: Label = $HUD/MovesLabel
@onready var _stuck_label: Label = $HUD/StuckLabel
@onready var _undo_button: Button = $HUD/UndoButton
@onready var _restart_button: Button = $HUD/RestartButton
@onready var _pause_button: Button = $HUD/PauseButton
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _solved_menu: CanvasLayer = $SolvedMenu
@onready var _sfx_slide: AudioStreamPlayer = $SfxSlide


## first_level: the level to start at (the command line's --level when 0).
func setup(game_levels: Levels, game_options: LaunchOptions, first_level := 0) -> void:
	levels = game_levels
	options = game_options
	_first_level = first_level


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	if levels == null:
		levels = Levels.from_file()
	_undo_button.pressed.connect(undo)
	_restart_button.pressed.connect(restart)
	_pause_button.pressed.connect(_pause_menu.open)
	_pause_menu.quit_pressed.connect(menu_requested.emit)
	_solved_menu.next_pressed.connect(next_level)
	_solved_menu.menu_pressed.connect(menu_requested.emit)
	_refresh_text()
	start_level(_first_level if _first_level > 0 else options.level)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_undo_button.text = tr("HUD_UNDO")
	_restart_button.text = tr("HUD_RESTART")
	_pause_button.text = tr("HUD_PAUSE")
	_stuck_label.text = tr("HUD_STUCK")
	_update_hud()


func _update_hud() -> void:
	if board == null:
		return
	_level_label.text = tr("HUD_LEVEL") % level
	_moves_label.text = tr("HUD_MOVES") % [board.moves, par]
	_stuck_label.visible = stuck


func start_level(number: int) -> void:
	if not levels.has_level(number):
		push_error("There is no level %d" % number)
		return
	level = number
	_load(levels.board(number), levels.par(number))


func _load(next_board: Board, next_par: int) -> void:
	board = next_board
	par = next_par
	state = "playing"
	stuck = false
	_solved_menu.close()
	grid.show_board(board, BOARD_CENTER)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if state != "playing":
		return
	for action: String in MOVE_ACTIONS:
		if event.is_action_pressed(action):
			try_move(MOVE_ACTIONS[action])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("undo"):
		undo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		restart()
		get_viewport().set_input_as_handled()


## Starts a slide; false when the mote cannot go that way, a slide is under way, or the level is over.
func try_move(direction: Vector2i) -> bool:
	if state != "playing":
		return false
	var from := board.position
	if not board.move(direction):
		return false
	_slide_from = from
	_slide_ticks = 0
	_slide_total = maxi(1, (absi(board.position.x - from.x) + absi(board.position.y - from.y)) * SLIDE_TICKS_PER_TILE)
	state = "sliding"
	# The sparks it collects stay drawn until the mote reaches them.
	var drawn := board.sparks.duplicate()
	drawn.append_array(board.last_collected)
	grid.show_sparks(drawn)
	_sfx_slide.play()
	_update_hud()
	return true


func undo() -> bool:
	if state != "playing" or not board.undo():
		return false
	_show_position()
	return true


func restart() -> void:
	if state != "playing" or not board.can_undo():
		return
	board.restart()
	_show_position()


func _show_position() -> void:
	grid.show_board(board, BOARD_CENTER)
	_check_stuck()
	_update_hud()


func _physics_process(_delta: float) -> void:
	if state == "sliding":
		_slide_ticks += 1
		grid.place_mote(_slide_from, board.position, float(_slide_ticks) / _slide_total)
		if _slide_ticks >= _slide_total:
			_arrived()


func _arrived() -> void:
	state = "playing"
	grid.show_sparks(board.sparks)
	if board.solved:
		_solved()
	else:
		_check_stuck()
	_update_hud()


## Asks the solver whether the exit can still be reached from here. Once per move: a search is too dear for every frame.
func _check_stuck() -> void:
	stuck_checks += 1
	stuck = not board.solved and solver.solve(board).is_empty()
	_stuck_label.visible = stuck


func _solved() -> void:
	state = "solved"
	stuck = false
	print("[Run] level %d done" % level)
	level_solved.emit(level, board.moves)
	_solved_menu.open(board.moves, par, "SOLVED_NEXT" if levels.has_level(level + 1) else "SOLVED_FINISH")


## The next level after a solved one; after the last level the run is over.
func next_level() -> void:
	if state != "solved":
		return
	if levels.has_level(level + 1):
		start_level(level + 1)
		return
	print("[Run] victory")
	state = "done"
	finished.emit(true)

