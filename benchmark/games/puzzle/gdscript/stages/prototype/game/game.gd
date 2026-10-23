extends Node2D
## The prototype: three levels of sliding on ice, with undo and restart. A move lands in Board at once; the view then
## slides the mote over a few ticks while input waits. A solved level moves on to the next after a short pause.

## Ticks the mote takes per tile of a slide.
const SLIDE_TICKS_PER_TILE := 2
## Ticks a solved level stays on screen before the next one.
const NEXT_LEVEL_TICKS := 60
const BOARD_CENTER := Vector2(640, 410)
const MOVE_ACTIONS := {"move_up": Vector2i.UP, "move_right": Vector2i.RIGHT, "move_down": Vector2i.DOWN, "move_left": Vector2i.LEFT}

var levels: Levels
var board: Board
var level := 1
var par := 0
## "playing", "sliding" (input waits for the mote) or "solved".
var state := "playing"

var _slide_ticks := 0
var _slide_total := 0
var _slide_from := Vector2i.ZERO
var _next_in := -1

@onready var grid: Node2D = $Grid
@onready var _level_label: Label = $HUD/LevelLabel
@onready var _moves_label: Label = $HUD/MovesLabel
@onready var _undo_button: Button = $HUD/UndoButton
@onready var _restart_button: Button = $HUD/RestartButton


func _ready() -> void:
	levels = Levels.from_file()
	_undo_button.pressed.connect(undo)
	_restart_button.pressed.connect(restart)
	start_level(1)


func _update_hud() -> void:
	_level_label.text = "Level %d" % level
	_moves_label.text = "Moves: %d / par %d" % [board.moves, par]
	if state == "solved":
		_moves_label.text += "  Solved!"


func start_level(number: int) -> void:
	level = number
	board = levels.board(number)
	par = levels.par(number)
	state = "playing"
	_next_in = -1
	grid.show_board(board, BOARD_CENTER)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if state != "playing":
		return
	for action: String in MOVE_ACTIONS:
		if event.is_action_pressed(action):
			try_move(MOVE_ACTIONS[action])
			return
	if event.is_action_pressed("undo"):
		undo()
	elif event.is_action_pressed("restart"):
		restart()


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
	var drawn := board.sparks.duplicate()
	drawn.append_array(board.last_collected)
	grid.show_sparks(drawn)
	_update_hud()
	return true


func undo() -> bool:
	if state != "playing" or not board.undo():
		return false
	grid.show_board(board, BOARD_CENTER)
	_update_hud()
	return true


func restart() -> void:
	if state != "playing":
		return
	board.restart()
	grid.show_board(board, BOARD_CENTER)
	_update_hud()


func _physics_process(_delta: float) -> void:
	if state == "sliding":
		_slide_ticks += 1
		grid.place_mote(_slide_from, board.position, float(_slide_ticks) / _slide_total)
		if _slide_ticks >= _slide_total:
			state = "solved" if board.solved else "playing"
			grid.show_sparks(board.sparks)
			if board.solved:
				print("[Run] level %d done" % level)
				_next_in = NEXT_LEVEL_TICKS
			_update_hud()
	elif state == "solved" and _next_in > 0:
		_next_in -= 1
		if _next_in == 0:
			start_level(level + 1 if levels.has_level(level + 1) else 1)
