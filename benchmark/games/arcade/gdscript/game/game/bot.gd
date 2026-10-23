class_name Bot
extends RefCounted
## The --autoplay player: it dodges enemy shots that are about to reach the ship, and otherwise lines up under the
## enemy it can reach first, leading drifting ones, and fires. Like a player it reacts only every few ticks, so it can
## be caught (the juice run needs a hit to check) but it still finishes all five levels.

## How far above the ship it looks for shots, and how wide a lane counts as "in the way".
const DANGER_HEIGHT := 190.0
const DANGER_HALF_WIDTH := 46.0
const AIM_TOLERANCE := 14.0
## Ticks between decisions: about a fifth of a second, a quick player's reaction time.
const REACTION_TICKS := 2

var _ticks := 0
## Where the shot it is dodging was when it last looked; NAN when it saw none.
var _dodge_from := NAN


## direction -1, 0 or 1 across the screen, and whether to fire. It aims every tick, but notices shots only every
## REACTION_TICKS ticks, as a player who is busy aiming would.
func decide(ship: Vector2, enemies: Array, shots: Array, shot_speed: float) -> Dictionary:
	_ticks += 1
	if _ticks % REACTION_TICKS == 1:
		var threat := _nearest_threat(ship, shots)
		_dodge_from = threat.position.x if threat != null else NAN
	if not is_nan(_dodge_from) and absf(_dodge_from - ship.x) <= DANGER_HALF_WIDTH:
		var away := 1.0 if _dodge_from <= ship.x else -1.0
		# Against a wall, dodge the other way through the shot's lane rather than be pinned.
		if (away < 0.0 and ship.x < 80.0) or (away > 0.0 and ship.x > 1200.0):
			away = -away
		return {"direction": away, "fire": false}
	var target := _pick_target(ship, enemies, shot_speed)
	if target.is_empty():
		return {"direction": 0.0, "fire": false}
	var dx: float = target.x - ship.x
	var direction := 0.0 if absf(dx) < AIM_TOLERANCE else signf(dx)
	return {"direction": direction, "fire": absf(dx) < AIM_TOLERANCE * 2.0}


func _nearest_threat(ship: Vector2, shots: Array) -> Node2D:
	var nearest: Node2D = null
	for shot: Shot in shots:
		# Its blind spot: it reads only shots that fall straight, so the boss's fan can catch it.
		if not shot.hostile or shot.velocity.x != 0.0:
			continue
		var above := ship.y - shot.position.y
		if above < -30.0 or above > DANGER_HEIGHT:
			continue
		if absf(shot.position.x - ship.x) > DANGER_HALF_WIDTH:
			continue
		if nearest == null or shot.position.y > nearest.position.y:
			nearest = shot
	return nearest


## The lowest enemy closest across, with where it will be when a shot reaches it.
func _pick_target(ship: Vector2, enemies: Array, shot_speed: float) -> Dictionary:
	var best := {}
	var best_cost := INF
	for enemy: Enemy in enemies:
		if enemy.hp <= 0 or enemy.position.y < 0.0:
			continue
		var flight := (ship.y - enemy.position.y) / shot_speed
		var x := enemy.predicted_x(flight)
		var cost := absf(x - ship.x) - enemy.position.y * 0.5
		if cost < best_cost:
			best_cost = cost
			best = {"x": x, "enemy": enemy}
	return best
