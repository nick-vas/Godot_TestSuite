extends Node2D
## Draws a board: walls, ice, snow, the exit (dim while closed, bright once open) and the sparks still out. The mote is
## the child sprite Mote, which the game moves along a slide.

const TILE := 60.0
const WALL_COLOR := Color(0.16, 0.22, 0.34)
const ICE_COLOR := Color(0.62, 0.8, 0.92)
const SNOW_COLOR := Color(0.94, 0.96, 1.0)
const EXIT_CLOSED := Color(0.35, 0.42, 0.5)
const EXIT_OPEN := Color(0.3, 0.85, 0.55)
const SPARK_TEXTURE := preload("res://art/spark.png")

var board: Board
## The sparks drawn: those the board has left, plus, during a slide, those the mote has not reached yet.
var _sparks: Array[Vector2i] = []

@onready var mote: Sprite2D = $Mote


## Shows a board centred on a point of the screen, the mote on its tile.
func show_board(shown: Board, center: Vector2) -> void:
	board = shown
	position = (center - Vector2(shown.width, shown.height) * TILE / 2.0).round()
	show_sparks(shown.sparks)
	place_mote(shown.position, shown.position, 1.0)


func show_sparks(cells: Array[Vector2i]) -> void:
	_sparks.assign(cells)
	queue_redraw()


## The mote a share t of the way along a slide.
func place_mote(from: Vector2i, to: Vector2i, t: float) -> void:
	mote.position = cell_center(from).lerp(cell_center(to), clampf(t, 0.0, 1.0))


func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


func _draw() -> void:
	if board == null:
		return
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(cell) * TILE, Vector2(TILE, TILE))
			match board.tile(cell):
				Board.WALL:
					draw_rect(rect, WALL_COLOR)
				Board.SNOW:
					draw_rect(rect, SNOW_COLOR)
				_:
					draw_rect(rect, ICE_COLOR)
					draw_rect(rect, ICE_COLOR.darkened(0.12), false, 1.0)
	var exit_rect := Rect2(Vector2(board.exit) * TILE, Vector2(TILE, TILE)).grow(-8.0)
	draw_rect(exit_rect, EXIT_OPEN if _sparks.is_empty() else EXIT_CLOSED)
	for cell: Vector2i in _sparks:
		draw_texture(SPARK_TEXTURE, cell_center(cell) - SPARK_TEXTURE.get_size() / 2.0)
