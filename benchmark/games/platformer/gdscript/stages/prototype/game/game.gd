extends Node3D
## The prototype: the climber, one level, glowmoss, hearts, beetles and the camera. Everything happens in
## _physics_process at a fixed 60 ticks; hearts and glowmoss live in Rules and the jump in Movement, which the tests
## cover.

signal finished(victory: bool, score: int)

const LEVEL := preload("res://levels/level_1.tscn")
## The one kind of beetle of the prototype.
const CRAWLER := {"id": "crawler", "speed": 1.5, "points": 50, "color": "#a0522d"}
const STOMP_BOUNCE := 8.0
## A hurt throws the climber back, away from the way it faces, and up.
const KNOCKBACK := Vector2(5.0, 6.0)
const MOSS_RADIUS := 0.3
const BEACON_SIZE := Vector2(1.6, 3.2)

var rules := Rules.new()
var level := 1
var state := "playing"
var current: Level

@onready var player: Player = $Player
@onready var camera: CameraRig = $Camera
@onready var _moss_label: Label = $HUD/MossLabel
@onready var _hearts_label: Label = $HUD/HeartsLabel


func _ready() -> void:
	current = LEVEL.instantiate()
	current.name = "Level"
	add_child(current)
	for beetle: Beetle in current.beetles.get_children():
		beetle.setup(CRAWLER)
	var start := current.start_position()
	rules.start_level(start)
	player.place(start)
	camera.reset_to(start, current.bounds())
	_update_hud()


func _update_hud() -> void:
	_moss_label.text = "Glowmoss: %d" % rules.moss
	_hearts_label.text = "Hearts: %d" % rules.hearts


func _physics_process(delta: float) -> void:
	if state != "playing":
		return
	rules.tick(delta)
	player.advance(Input.get_axis("move_left", "move_right"), Input.is_action_just_pressed("jump"), Input.is_action_pressed("jump"), delta)
	player.visible = not rules.is_invulnerable() or Engine.get_physics_frames() / 6 % 2 == 0
	_touch_things()
	if state == "playing" and player.position.y < current.fall_height():
		rules.fell()
		_lost_heart()
		player.place(current.start_position())
	camera.follow(player.position, player.movement.on_floor, player.movement.facing, delta)


func _touch_things() -> void:
	var feet := player.position
	for tuft: Node3D in current.moss.get_children():
		if _touches(feet, tuft.position - Vector3(0, MOSS_RADIUS, 0), Vector2(MOSS_RADIUS * 2.0, MOSS_RADIUS * 2.0)):
			rules.collect_moss()
			current.moss.remove_child(tuft)
			tuft.queue_free()
			_update_hud()
	for beetle: Beetle in current.beetles.get_children():
		if _touches(feet, beetle.position, Vector2(Beetle.SIZE.x, Beetle.SIZE.y)):
			if player.movement.velocity.y < 0.0 and feet.y > beetle.position.y + Beetle.SIZE.y * 0.4:
				rules.stomp(beetle)
				player.movement.launch(Vector2(player.movement.velocity.x, STOMP_BOUNCE))
				current.beetles.remove_child(beetle)
				beetle.queue_free()
			elif rules.hurt():
				player.movement.launch(Vector2(-player.movement.facing * KNOCKBACK.x, KNOCKBACK.y))
				_lost_heart()
	if state == "playing" and _touches(feet, current.beacon.position, BEACON_SIZE):
		print("[Run] level 1 done")
		_finish(true)


func _touches(feet: Vector3, foot: Vector3, box: Vector2) -> bool:
	return absf(feet.x - foot.x) < Player.HALF_WIDTH + box.x / 2.0 \
		and feet.y < foot.y + box.y and foot.y < feet.y + Movement.BODY_HEIGHT


func _lost_heart() -> void:
	_update_hud()
	if rules.is_game_over():
		print("[Run] game over")
		_finish(false)


func _finish(victory: bool) -> void:
	state = "won" if victory else "lost"
	finished.emit(victory, rules.score)
