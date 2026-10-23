extends CharacterBody2D
# Moved once per physics tick with physics_interpolation off and no frame cap: doctor warns that it judders on screens
# faster than 60 Hz.

const SPEED := 200.0

func _physics_process(_delta: float) -> void:
	velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * SPEED
	move_and_slide()
