class_name Player
extends CharacterBody3D
## The climber's body. Movement decides the velocity and move_and_slide moves it against the level; its origin is at its
## feet. The game calls advance() from its own physics step, so pausing the game stops the climber too.

const HALF_WIDTH := 0.4

var movement := Movement.new()


func advance(direction: float, jump_pressed: bool, jump_held: bool, delta: float) -> void:
	movement.step(direction, jump_pressed, jump_held, delta)
	velocity = Vector3(movement.motion.x, movement.motion.y, 0.0)
	move_and_slide()
	movement.touched(is_on_floor(), is_on_ceiling(), is_on_wall())
	position.z = 0.0


## Puts the climber down at a place, standing still, without the slide an interpolated jump would draw.
func place(at: Vector3) -> void:
	position = at
	movement.launch(Vector2.ZERO)
	reset_physics_interpolation()
