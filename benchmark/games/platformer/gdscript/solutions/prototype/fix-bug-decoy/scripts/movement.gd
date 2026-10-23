class_name Movement
extends RefCounted
## How the climber runs and jumps, kept free of the engine so the tests can drive it tick by tick. Units are metres and
## seconds, y is up. Each tick the body moves by `motion` and reports back with touched() what it stands on or hit.

const RUN_SPEED := 6.0
const ACCELERATION := 40.0
const AIR_ACCELERATION := 24.0
const GRAVITY := 30.0
const JUMP_VELOCITY := 10.5
## Releasing jump while rising keeps this share of the speed, so a tap is a hop and a hold is a full jump.
const JUMP_CUT := 0.45
const MAX_FALL_SPEED := 18.0
## A jump pressed this long after running off a ledge still counts (coyote time) ...
const COYOTE_TIME := 0.1
## ... and one pressed this long before landing happens on landing (the jump buffer).
const JUMP_BUFFER := 0.2
const BODY_HEIGHT := 1.0
## How high above the ground the climber's body reaches at the top of a full jump: what a level may ask of it. The
## placement check reads it, so a glowmoss tuft hung higher is caught before a player finds it.
const REACH := JUMP_VELOCITY * JUMP_VELOCITY / (2.0 * GRAVITY) + BODY_HEIGHT

var velocity := Vector2.ZERO
## What to move by this tick: the average velocity over the tick, so a jump's arc is the same at any tick rate.
var motion := Vector2.ZERO
var on_floor := false
var facing := 1.0
## True on the tick a jump started.
var jumped := false

var _coyote := 0.0
var _buffer := 0.0
var _rising := false


## One fixed tick: direction -1 to 1, jump_pressed only on the tick the button went down, jump_held while it is down.
func step(direction: float, jump_pressed: bool, jump_held: bool, delta: float) -> void:
	var acceleration := ACCELERATION if on_floor else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, clampf(direction, -1.0, 1.0) * RUN_SPEED, acceleration * delta)
	if direction != 0.0:
		facing = signf(direction)
	if on_floor:
		_coyote = COYOTE_TIME
		_rising = false
	if jump_pressed:
		_buffer = JUMP_BUFFER
	jumped = false
	if _buffer > 0.0 and (on_floor or _coyote >= 0.0):
		# One press is one jump: it spends both the buffered press and the coyote window.
		velocity.y = JUMP_VELOCITY
		_coyote = 0.0
		_buffer = 0.0
		_rising = true
		jumped = true
	elif _rising and not jump_held and velocity.y > 0.0:
		velocity.y *= JUMP_CUT
		_rising = false
	var start_y := velocity.y
	if not on_floor or jumped:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL_SPEED)
	motion = Vector2(velocity.x, (start_y + velocity.y) / 2.0)
	_coyote = maxf(_coyote - delta, 0.0)
	_buffer = maxf(_buffer - delta, 0.0)


## What the move ran into: a floor or a ceiling stops the fall or the rise, a wall stops the run.
func touched(floor_below: bool, ceiling: bool, wall: bool) -> void:
	on_floor = floor_below
	if floor_below and velocity.y < 0.0:
		velocity.y = 0.0
	if ceiling and velocity.y > 0.0:
		velocity.y = 0.0
		_rising = false
	if wall:
		velocity.x = 0.0


## Thrown by a hit or a bounce: the new velocity, with no jump to cut short.
func launch(new_velocity: Vector2) -> void:
	velocity = new_velocity
	on_floor = false
	_rising = false
	_coyote = 0.0
