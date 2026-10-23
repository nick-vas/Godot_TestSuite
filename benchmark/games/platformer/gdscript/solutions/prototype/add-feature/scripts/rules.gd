class_name Rules
extends RefCounted
## Hearts, invulnerability, glowmoss, checkpoints and what touching things does, kept free of the engine so the tests
## need no scene. Hearts are per level: each level starts with them full.

const START_HEARTS := 3
const INVULNERABLE_SECONDS := 1.5
const MOSS_POINTS := 10

var hearts: int
## Seconds of invulnerability left after the last hurt.
var invulnerable := 0.0
## Glowmoss gathered this run, and the score (moss and stomped beetles).
var moss := 0
var score := 0

var _max_hearts: int
var _checkpoint := Vector3.ZERO


func _init(start_hearts := START_HEARTS) -> void:
	_max_hearts = start_hearts
	hearts = start_hearts


## A level begins at start: hearts full, no checkpoint reached yet.
func start_level(start: Vector3) -> void:
	hearts = _max_hearts
	invulnerable = 0.0
	_checkpoint = start


func tick(delta: float) -> void:
	invulnerable = maxf(invulnerable - delta, 0.0)


func is_invulnerable() -> bool:
	return invulnerable > 0.0


## Thorns or a beetle touched the climber: true when that cost a heart.
func hurt() -> bool:
	if invulnerable > 0.0 or is_game_over():
		return false
	hearts -= 1
	invulnerable = INVULNERABLE_SECONDS
	return true


## The climber fell out of the level: that always costs a heart, then a respawn at respawn_point().
func fell() -> void:
	if is_game_over():
		return
	hearts -= 1
	invulnerable = INVULNERABLE_SECONDS


func is_game_over() -> bool:
	return hearts <= 0


## A glowmoss tuft gathered: the points it scores.
func collect_moss() -> int:
	moss += 1
	score += MOSS_POINTS
	return MOSS_POINTS


## The climber landed on a beetle (anything with points): the points it scores.
func stomp(beetle) -> int:
	score += beetle.points
	return beetle.points


## A checkpoint touched at a place: kept when it is further along the level (by x) than the last one.
func reach_checkpoint(at: Vector3) -> bool:
	if at.x <= _checkpoint.x:
		return false
	_checkpoint = at
	return true


## Where the climber comes back after a fall: the furthest checkpoint reached, or the level's start.
func respawn_point() -> Vector3:
	return _checkpoint
