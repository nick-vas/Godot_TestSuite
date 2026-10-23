class_name LevelGenerator
extends RefCounted
## The daily drift: a level made from a seed. Each attempt draws walls and snow, then the start, the exit and the sparks,
## from its own generator seeded by (seed, attempt), and the solver keeps the first one solvable in MIN_PAR to MAX_PAR
## moves. Same seed, same level, on every run and machine: nothing here reads the clock or the global generator.

const SIZE := Vector2i(9, 8)
const SPARKS := 2
const WALL_CHANCE := 0.17
const SNOW_CHANCE := 0.07
const MIN_PAR := 4
const MAX_PAR := 14
const MAX_ATTEMPTS := 60
## The level when no attempt is valid, so the daily always starts; a seed sweep test keeps this from happening.
const FALLBACK := ["#########", "#S..#...#", "#.#...*.#", "#...:#..#", "#.*.....#", "#..#..#.#", "#......E#", "#########"]


## {rows, par, seed, attempts}; attempts is 0 when the fallback was used.
static func generate(run_seed: int) -> Dictionary:
	var solver := Solver.new()
	# One seed for the whole run of attempts, so the same daily seed always draws the same.
	seed(run_seed)
	for attempt in MAX_ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = derive(run_seed, attempt)
		var rows := draw(rng)
		var par := solver.min_moves(Board.from_rows(rows))
		if par >= MIN_PAR and par <= MAX_PAR:
			print("[gen] seed %d valid after %d attempts" % [run_seed, attempt + 1])
			return {"rows": rows, "par": par, "seed": run_seed, "attempts": attempt + 1}
	print("[gen] seed %d: no valid level in %d attempts, using the fallback" % [run_seed, MAX_ATTEMPTS])
	return {"rows": FALLBACK.duplicate(), "par": solver.min_moves(Board.from_rows(FALLBACK)), "seed": run_seed, "attempts": 0}


## Each attempt's own seed: a fixed formula, the same in every language (no hash of the runtime's own).
static func derive(run_seed: int, attempt: int) -> int:
	return run_seed * 1009 + attempt


## One candidate level: walls round the edge, walls and snow inside, then the marks on distinct ice tiles.
static func draw(rng: RandomNumberGenerator) -> Array[String]:
	var rows: Array[String] = []
	var ice: Array[Vector2i] = []
	for y in SIZE.y:
		var row := ""
		for x in SIZE.x:
			var roll := rng.randf()
			if x == 0 or y == 0 or x == SIZE.x - 1 or y == SIZE.y - 1 or roll < WALL_CHANCE:
				row += Board.WALL
			elif roll < WALL_CHANCE + SNOW_CHANCE:
				row += Board.SNOW
			else:
				row += Board.ICE
				ice.append(Vector2i(x, y))
		rows.append(row)
	var marks: Array[String] = [Board.START, Board.EXIT]
	for i in SPARKS:
		marks.append(Board.SPARK)
	for mark in marks:
		if ice.is_empty():
			break
		var i := randi_range(0, ice.size() - 1)
		var cell := ice[i]
		ice.remove_at(i)
		rows[cell.y] = rows[cell.y].substr(0, cell.x) + mark + rows[cell.y].substr(cell.x + 1)
	return rows
