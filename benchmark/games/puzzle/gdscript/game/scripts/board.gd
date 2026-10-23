class_name Board
extends RefCounted
## One level's state and its rules, kept free of the engine's scenes so the tests and the solver need no scene.
## The mote slides until the tile ahead is a wall (the edge counts as one). Snow stops it on the snow. Every spark it
## passes is collected. The exit is ice until the last spark is collected; after that it stops the mote and solves the level.

const WALL := "#"
const ICE := "."
const SNOW := ":"
const SPARK := "*"
const START := "S"
const EXIT := "E"
## The order the solver and the bot try directions in, so their solutions are the same in every language.
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var width := 0
var height := 0
var start := Vector2i.ZERO
var exit := Vector2i(-1, -1)
var position := Vector2i.ZERO
## The sparks not collected yet, in reading order.
var sparks: Array[Vector2i] = []
var moves := 0
var solved := false
## The sparks the last move collected, in the order it passed them.
var last_collected: Array[Vector2i] = []

var _rows := PackedStringArray()
## One entry per move made: where the mote was, the sparks left then, and the move count.
var _history: Array[Dictionary] = []


static func from_rows(rows: Array) -> Board:
	var board := Board.new()
	board.height = rows.size()
	for y in rows.size():
		var row := str(rows[y])
		board._rows.append(row)
		board.width = maxi(board.width, row.length())
		for x in row.length():
			match row[x]:
				START:
					board.start = Vector2i(x, y)
				EXIT:
					board.exit = Vector2i(x, y)
				SPARK:
					board.sparks.append(Vector2i(x, y))
	board.position = board.start
	return board


## The tile at a cell: one of WALL, ICE, SNOW, SPARK, START or EXIT; outside the level, a wall.
func tile(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= height or cell.x < 0 or cell.x >= _rows[cell.y].length():
		return WALL
	return _rows[cell.y][cell.x]


func rows() -> PackedStringArray:
	return _rows.duplicate()


## Where a slide from a cell ends with the given sparks still out, without changing the board: the cell it stops on, the
## sparks it collects on the way, and whether it stops on the open exit.
func slide(from: Vector2i, direction: Vector2i, remaining: Array[Vector2i]) -> Dictionary:
	var at := from
	var collected: Array[Vector2i] = []
	var reached_exit := false
	while tile(at + direction) != WALL:
		at += direction
		if at in remaining and not at in collected:
			collected.append(at)
		if at == exit and collected.size() == remaining.size():
			reached_exit = true
			break
		if tile(at) == SNOW:
			break
	return {"to": at, "collected": collected, "solved": reached_exit}


## Slides the mote. A move that cannot leave its tile is not a move: nothing changes and it is not counted.
func move(direction: Vector2i) -> bool:
	if solved:
		return false
	var result := slide(position, direction, sparks)
	if result.to == position:
		return false
	_history.append({"position": position, "sparks": sparks.duplicate(), "moves": moves})
	position = result.to
	for cell: Vector2i in result.collected:
		sparks.erase(cell)
	last_collected.assign(result.collected)
	moves += 1
	solved = result.solved
	return true


## Takes back the last move: the position, the sparks and the move count as they were before it.
func undo() -> bool:
	if _history.is_empty():
		return false
	var last: Dictionary = _history.pop_back()
	position = last.position
	sparks.assign(last.sparks)
	moves = last.moves
	solved = false
	last_collected.clear()
	return true


func can_undo() -> bool:
	return not _history.is_empty()


## Back to the start of the level, as if no move had been made.
func restart() -> void:
	while undo():
		pass
