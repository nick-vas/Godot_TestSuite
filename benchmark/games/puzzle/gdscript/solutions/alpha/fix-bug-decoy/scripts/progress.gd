class_name Progress
extends RefCounted
## What a save says about the levels: which are solved and in how few moves (0: solved before moves were kept), and
## which are open. A level opens when the one before it is solved.


## Records a solve; true when it is the level's first or a new best. A worse replay keeps the best.
static func record(save: Dictionary, level: int, moves: int) -> bool:
	var solved: Dictionary = save.solved
	var key := str(level)
	var best := int(solved.get(key, 0))
	solved[key] = moves
	return best == 0 or moves < best


static func is_solved(save: Dictionary, level: int) -> bool:
	return save.solved.has(str(level))


## The fewest moves a level was solved in, 0 when it is not solved or the moves were not kept.
static func best(save: Dictionary, level: int) -> int:
	return int(save.solved.get(str(level), 0))


static func is_unlocked(save: Dictionary, level: int) -> bool:
	return level <= 1 or is_solved(save, level - 1)


## The sum of the best moves of every solved level, for the victory screen.
static func total_moves(save: Dictionary) -> int:
	var total := 0
	for key: String in save.solved:
		total += int(save.solved[key])
	return total
