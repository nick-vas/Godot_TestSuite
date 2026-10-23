class_name Solver
extends RefCounted
## Shortest solutions, by a breadth-first search over (where the mote is, which sparks are left). The levels are small
## (at most 11 by 9 tiles and three sparks), so a search visits a few hundred states. The tests use it to prove every
## level can be solved at its par; the game uses it to tell a stuck player, and the bot to play.

## States the last search took off its queue: what it cost, for the tests that keep it cheap.
var expanded := 0


## The moves of a shortest solution from the board's current state; empty when the exit cannot be reached (or the
## level is already solved). Directions are tried in Board.DIRECTIONS order, so the solution is always the same one.
func solve(board: Board) -> Array[Vector2i]:
	expanded = 0
	var none: Array[Vector2i] = []
	if board.solved:
		return none
	var queue: Array[Dictionary] = [{"at": board.position, "sparks": board.sparks.duplicate(), "path": none}]
	var seen := {_key(board.position, board.sparks): true}
	var head := 0
	while head < queue.size():
		var state: Dictionary = queue[head]
		head += 1
		expanded += 1
		for direction: Vector2i in Board.DIRECTIONS:
			var result := board.slide(state.at, direction, state.sparks)
			if result.to == state.at:
				continue
			var path: Array[Vector2i] = state.path.duplicate()
			path.append(direction)
			if result.solved:
				return path
			var left: Array[Vector2i] = state.sparks.duplicate()
			for cell: Vector2i in result.collected:
				left.erase(cell)
			var key := _key(result.to, left)
			if seen.has(key):
				continue
			seen[key] = true
			queue.append({"at": result.to, "sparks": left, "path": path})
	return none


## The fewest moves that solve the board from where it is, or -1 when it cannot be solved.
func min_moves(board: Board) -> int:
	if board.solved:
		return 0
	var path := solve(board)
	return path.size() if not path.is_empty() else -1


## The first move of a shortest solution from the board's current state; Vector2i.ZERO when there is none.
func hint(board: Board) -> Vector2i:
	var path := solve(board)
	return path[0] if not path.is_empty() else Vector2i.ZERO


func _key(at: Vector2i, left: Array[Vector2i]) -> String:
	return "%d,%d|%s" % [at.x, at.y, left]
