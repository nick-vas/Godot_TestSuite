class_name Rules
extends RefCounted
## Lives, invulnerability and what a collision does, kept free of the engine so the tests need no scene.

const START_LIVES := 3
const INVULNERABLE_SECONDS := 2.0

var lives: int
## Seconds of invulnerability left after the last hit.
var invulnerable := 0.0


func _init(start_lives := START_LIVES) -> void:
	lives = start_lives


func tick(delta: float) -> void:
	invulnerable = maxf(invulnerable - delta, 0.0)


func is_invulnerable() -> bool:
	return invulnerable > 0.0


## An enemy or its shot touched the ship: true when that cost a life.
func ship_hit() -> bool:
	if invulnerable > 0.0 or is_game_over():
		return false
	lives -= 1
	invulnerable = INVULNERABLE_SECONDS
	return true


func is_game_over() -> bool:
	return lives <= 0


## A shot hit an enemy (anything with hp and points) for damage: the points it scores, 0 unless it was destroyed.
func hit_enemy(enemy, damage := 1) -> int:
	enemy.hp -= damage
	if enemy.hp > 0:
		return 0
	return enemy.points
