class_name Enemy
extends Sprite2D
## One enemy of a wave. It moves itself, so pausing the tree stops it; the game decides when it fires and what hits it.

## How far down a formation comes before it turns back up, and where it turns down again.
const FLOOR_Y := 460.0
const CEILING_Y := 70.0
const BOSS_STOP_Y := 150.0
const DRIFT_RATE := 1.5

var id := ""
var hp := 1
var points := 0
var speed := 40.0
var drift := 0.0
var fire := 0.0
var boss := false
var size := Vector2(40, 32)
## Seconds until the next shot; the game counts it down.
var fire_timer := 0.0

var _base_x := 0.0
var _t := 0.0
var _direction := 1.0


func setup(row: Dictionary, wave_speed: float, at: Vector2) -> void:
	id = str(row.id)
	hp = int(row.hp)
	points = int(row.points)
	drift = float(row.get("drift", 0))
	fire = float(row.get("fire", 0))
	boss = bool(row.get("boss", false))
	speed = wave_speed
	modulate = Color.html(str(row.get("color", "#ffffff")))
	if boss:
		size = Vector2(160, 80)
	position = at
	_base_x = at.x


func _physics_process(delta: float) -> void:
	_t += delta
	if boss:
		position.y = minf(position.y + speed * delta, BOSS_STOP_Y)
	else:
		position.y += speed * _direction * delta
		if position.y > FLOOR_Y:
			_direction = -1.0
		elif position.y < CEILING_Y:
			_direction = 1.0
	position.x = predicted_x(0.0)


## Where it will be across the screen after the given seconds, for a bot that leads its shots.
func predicted_x(seconds: float) -> float:
	return _base_x + sin((_t + seconds) * DRIFT_RATE) * drift
