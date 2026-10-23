extends Node3D
## One run of the game: the climber, the level, what touches what, the camera, the HUD and pause. Main starts it with
## setup(); on its own (a flow, a test, the editor) it reads the command line and the data files itself. Everything
## happens in _physics_process at the fixed tick rate, and every random choice comes from one seeded generator, so a
## seed replays a run.

signal finished(victory: bool, score: int)
signal level_started(number: int)
signal quit_requested

const STOMP_BOUNCE := 8.0
## A hurt throws the climber back, away from the way it faces, and up.
const KNOCKBACK := Vector2(5.0, 6.0)
const MOSS_RADIUS := 0.3
const CHECKPOINT_SIZE := Vector2(1.2, 2.0)
const BEACON_SIZE := Vector2(1.6, 3.2)
const DUST_EVERY := 0.1
const DUST_LIFE := 0.4

var levels: Levels
var options: LaunchOptions
var rules := Rules.new()
var level := 1
var state := "playing"
## The level being played: a Level scene, the child named Level.
var current: Level

var _rng := RandomNumberGenerator.new()
var _ticks := 0
var _dust_in := 0.0
var _shake := 0.0
var _flash := 0.0
var _pop := 0.0
var _dust_mesh := SphereMesh.new()

@onready var player: Player = $Player
@onready var camera: CameraRig = $Camera
@onready var effects: Node3D = $Effects
@onready var _level_label: Label = $HUD/LevelLabel
@onready var _moss_label: Label = $HUD/MossLabel
@onready var _hearts_label: Label = $HUD/HeartsLabel
@onready var _pause_button: Button = $HUD/PauseButton
@onready var _flash_rect: ColorRect = $HUD/Flash
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _sfx_jump: AudioStreamPlayer = $SfxJump
@onready var _sfx_moss: AudioStreamPlayer = $SfxMoss
@onready var _sfx_stomp: AudioStreamPlayer = $SfxStomp
@onready var _sfx_hurt: AudioStreamPlayer = $SfxHurt


func setup(game_levels: Levels, game_options: LaunchOptions) -> void:
	levels = game_levels
	options = game_options


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	if levels == null:
		levels = Levels.from_files()
	_rng.seed = options.run_seed
	_dust_mesh.radius = 0.12
	_dust_mesh.height = 0.24
	_dust_mesh.material = Level.flat_material(Color("#d9cfb0"))
	_pause_button.pressed.connect(_pause_menu.open)
	_pause_menu.quit_pressed.connect(quit_requested.emit)
	_refresh_text()
	start_level(options.level)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_pause_button.text = tr("HUD_PAUSE")
	_update_hud()


func _update_hud() -> void:
	var row := levels.level(level)
	_level_label.text = tr("HUD_LEVEL") % [level, tr(str(row.get("name", "")))]
	_moss_label.text = tr("HUD_MOSS") % rules.moss
	_hearts_label.text = tr("HUD_HEARTS") % rules.hearts


func start_level(number: int) -> void:
	var row := levels.level(number)
	if row.is_empty():
		push_error("There is no level %d" % number)
		return
	level = number
	if current != null:
		remove_child(current)
		current.queue_free()
	current = (load(str(row.scene)) as PackedScene).instantiate()
	current.name = "Level"
	add_child(current)
	for beetle: Beetle in current.beetles.get_children():
		beetle.setup(levels.beetle(beetle.kind))
	var start := current.start_position()
	rules.start_level(start)
	player.place(start)
	camera.reset_to(start, current.bounds())
	_clear(effects)
	_update_hud()
	level_started.emit(number)


func game_ms() -> float:
	return _ticks * 1000.0 / Engine.physics_ticks_per_second


func _physics_process(delta: float) -> void:
	if state != "playing":
		return
	_ticks += 1
	rules.tick(delta)
	_move_player(delta)
	_touch_things()
	if state == "playing" and player.position.y < current.fall_height():
		_fell()
	camera.follow(player.position, player.movement.on_floor, player.movement.facing, delta)
	_update_effects(delta)


func _move_player(delta: float) -> void:
	player.advance(Input.get_axis("move_left", "move_right"), Input.is_action_just_pressed("jump"), Input.is_action_pressed("jump"), delta)
	if player.movement.jumped:
		_sfx_jump.play()
	player.visible = not rules.is_invulnerable() or (_ticks * 10 / Engine.physics_ticks_per_second) % 2 == 0
	_dust_in -= delta
	if player.movement.on_floor and absf(player.movement.velocity.x) > 1.0 and _dust_in <= 0.0:
		_dust_in = DUST_EVERY
		spawn_dust(player.position)


func _touch_things() -> void:
	var feet := player.position
	for tuft: Node3D in current.moss.get_children():
		if _touches(feet, tuft.position - Vector3(0, MOSS_RADIUS, 0), Vector2(MOSS_RADIUS * 2.0, MOSS_RADIUS * 2.0)):
			_collect(tuft)
	for beetle: Beetle in current.beetles.get_children():
		if _touches(feet, beetle.position, Vector2(Beetle.SIZE.x, Beetle.SIZE.y)):
			# The outcome good for the player first: falling onto its back is a stomp, anything else hurts.
			if player.movement.velocity.y < 0.0 and feet.y > beetle.position.y + Beetle.SIZE.y * 0.4:
				_stomp(beetle)
			else:
				_hurt()
	for patch: Thorns in current.thorns.get_children():
		if _touches(feet, patch.position, Vector2(patch.size.x, patch.size.y)):
			_hurt()
	for post: Node3D in current.checkpoints.get_children():
		if _touches(feet, post.position, CHECKPOINT_SIZE) and rules.reach_checkpoint(post.position):
			(post.get_node("Lantern") as MeshInstance3D).material_override = Level.flat_material(Color("#ffd166"))
	if state == "playing" and _touches(feet, current.beacon.position, BEACON_SIZE):
		_level_done()


## Whether the climber's box (its feet at feet) overlaps a box standing at foot with the given width and height.
func _touches(feet: Vector3, foot: Vector3, box: Vector2) -> bool:
	return absf(feet.x - foot.x) < Player.HALF_WIDTH + box.x / 2.0 \
		and feet.y < foot.y + box.y and foot.y < feet.y + Movement.BODY_HEIGHT


func _collect(tuft: Node3D) -> void:
	rules.collect_moss()
	_event("moss_collected")
	_play(_sfx_moss)
	_pop_label()
	current.moss.remove_child(tuft)
	tuft.queue_free()
	_update_hud()


func _stomp(beetle: Beetle) -> void:
	rules.stomp(beetle)
	player.movement.launch(Vector2(player.movement.velocity.x, STOMP_BOUNCE))
	_event("beetle_stomped")
	_shake_camera(0.25)
	_play(_sfx_stomp)
	current.beetles.remove_child(beetle)
	beetle.queue_free()


func _hurt() -> void:
	if state != "playing" or not rules.hurt():
		return
	player.movement.launch(Vector2(-player.movement.facing * KNOCKBACK.x, KNOCKBACK.y))
	_hurt_feedback()


func _fell() -> void:
	rules.fell()
	_hurt_feedback()
	if state == "playing":
		player.place(rules.respawn_point())
		camera.reset_to(player.position, current.bounds())


func _hurt_feedback() -> void:
	_event("player_hurt")
	_flash_screen(Color(1, 0.2, 0.2, 0.45))
	_shake_camera(0.4)
	_play(_sfx_hurt)
	_update_hud()
	if rules.is_game_over():
		_finish(false)


func _level_done() -> void:
	print("[Run] level %d done" % level)
	if level >= levels.count():
		print("[Run] victory")
		_finish(true)
	else:
		start_level(level + 1)


func spawn_dust(at: Vector3) -> Dust:
	var puff := Dust.new()
	puff.mesh = _dust_mesh
	puff.position = at + Vector3(_rng.randf_range(-0.2, 0.2), 0.1, 0.4)
	effects.add_child(puff)
	return puff


func _finish(victory: bool) -> void:
	state = "won" if victory else "lost"
	if not victory:
		print("[Run] game over")
	finished.emit(victory, rules.score)
	# On its own (the prototype, or a flow) nobody listens; a bot run then ends here.
	if options.autoplay and finished.get_connections().is_empty():
		get_tree().quit()


# Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
func _event(event_name: String) -> void:
	print("[juice] event %s %.1f" % [event_name, game_ms()])


func _feedback(kind: String) -> void:
	print("[juice] feedback %s %.1f" % [kind, game_ms()])


func _flash_screen(color: Color) -> void:
	_flash = color.a
	_flash_rect.color = color
	_feedback("flash")


func _shake_camera(amount: float) -> void:
	_shake = amount
	_feedback("shake")


func _pop_label() -> void:
	_pop = 0.4
	_feedback("pop")


func _play(sound: AudioStreamPlayer) -> void:
	sound.play()
	_feedback("sfx")


func _update_effects(delta: float) -> void:
	for puff: Dust in effects.get_children():
		puff.age += delta
		puff.scale = Vector3.ONE * (1.0 + puff.age * 2.5)
		if puff.age >= DUST_LIFE:
			effects.remove_child(puff)
			puff.queue_free()
	_flash = maxf(_flash - delta * 2.0, 0.0)
	_flash_rect.color.a = _flash
	_pop = maxf(_pop - delta * 2.0, 0.0)
	_moss_label.scale = Vector2.ONE * (1.0 + _pop)
	_shake = maxf(_shake - delta * 1.5, 0.0)
	camera.h_offset = _rng.randf_range(-_shake, _shake) if _shake > 0.0 else 0.0
	camera.v_offset = _rng.randf_range(-_shake, _shake) if _shake > 0.0 else 0.0


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
