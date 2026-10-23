class_name Bot
extends RefCounted
## The --autoplay player: it asks the solver for the first move of a shortest solution from where it stands. Like a
## player it takes a moment before each move, so a run can be watched and its feedback checked in game time.

## Ticks it thinks before each move: a fifth of a second.
const THINK_TICKS := 12

var solver := Solver.new()
var _wait := THINK_TICKS


## {ready, direction}: not ready while it thinks; once ready, Vector2i.ZERO means the exit cannot be reached.
func decide(board: Board) -> Dictionary:
	_wait -= 1
	if _wait > 0:
		return {"ready": false, "direction": Vector2i.ZERO}
	_wait = THINK_TICKS
	return {"ready": true, "direction": solver.hint(board)}
