extends Node2D
## One run of the game: the ship, the waves, the shots and what they hit, the HUD and pause. Main starts it with setup();
## on its own (a flow, a test, the editor) it reads the command line and the data files itself. Everything happens in
## _physics_process at a fixed 60 ticks, and every random choice comes from one seeded generator, so a seed replays a run.

signal finished(victory: bool, points: int)
signal quit_requested

const SHIP_Y := 650.0
const SHIP_SPEED := 420.0
const SHIP_SIZE := Vector2(48, 32)
const SHIP_MIN_X := 40.0
const SHIP_MAX_X := 1240.0
const SHOT_SPEED := 720.0
const ENEMY_SHOT_SPEED := 260.0
const FIRE_COOLDOWN := 0.18
const WAVE_DELAY := 1.0
const SCREEN_BOTTOM := 740.0
const COLUMN_WIDTH := 80.0
const COLUMNS := 17
## Enemies are filed under every column they reach plus this margin, so a shot on a column's edge still finds them.
const COLUMN_MARGIN := 6.0

const SHOT_TEXTURE := preload("res://art/shot.png")
const ENEMY_SHOT_TEXTURE := preload("res://art/enemy_shot.png")
const ENEMY_TEXTURE := preload("res://art/enemy.png")
const BOSS_TEXTURE := preload("res://art/boss.png")

var score := Score.new()
var rules := Rules.new()
var waves: Waves
var options: LaunchOptions
var level := 1
var wave_index := 0
## How many shot-against-enemy tests the collision pass has made, for the performance test.
var collision_checks := 0
var state := "playing"

var _rng := RandomNumberGenerator.new()
var _ticks := 0
var _cooldown := 0.0
var _next_wave_in := -1.0
var _spawned := 0
## The enemies in each column of the screen, refilled every tick; kept so the pass allocates nothing.
var _columns: Array[Array] = []

@onready var ship: Sprite2D = $Ship
@onready var enemies: Node2D = $Enemies
@onready var shots: Node2D = $Shots
@onready var _score_label: Label = $HUD/ScoreLabel
@onready var _lives_label: Label = $HUD/LivesLabel
@onready var _pause_button: Button = $HUD/PauseButton
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _sfx_laser: AudioStreamPlayer = $SfxLaser


func setup(game_waves: Waves, game_options: LaunchOptions, best := 0) -> void:
	waves = game_waves
	options = game_options
	score.best = best


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	if waves == null:
		waves = Waves.from_files()
	_rng.seed = options.run_seed
	for i in COLUMNS:
		_columns.append([])
	score.changed.connect(_update_hud)
	_pause_button.pressed.connect(_pause_menu.open)
	_pause_menu.quit_pressed.connect(quit_requested.emit)
	ship.position = Vector2(640, SHIP_Y)
	_refresh_text()
	start_level(options.level)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_pause_button.text = tr("HUD_PAUSE")
	_update_hud()


func _update_hud() -> void:
	_score_label.text = tr("HUD_SCORE") % score.points
	_lives_label.text = tr("HUD_LIVES") % rules.lives


func start_level(number: int) -> void:
	level = number
	wave_index = 0
	_spawned = 0
	_next_wave_in = -1.0
	_clear(enemies)
	_clear(shots)
	_spawn_wave()


func game_ms() -> float:
	return _ticks * 1000.0 / Engine.physics_ticks_per_second


func _physics_process(delta: float) -> void:
	if state != "playing":
		return
	_ticks += 1
	rules.tick(delta)
	_move_ship(delta)
	_enemies_fire(delta)
	resolve_shot_hits()
	_resolve_ship_hits()
	_remove_spent_shots()
	_advance_waves(delta)


func _move_ship(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	var firing := Input.is_action_pressed("fire")
	ship.position.x = clampf(ship.position.x + direction * SHIP_SPEED * delta, SHIP_MIN_X, SHIP_MAX_X)
	ship.visible = not rules.is_invulnerable() or (_ticks / 6) % 2 == 0
	_cooldown -= delta
	if firing and _cooldown <= 0.0 and state == "playing":
		_cooldown = FIRE_COOLDOWN
		spawn_shot(ship.position + Vector2(0, -24), Vector2(0, -SHOT_SPEED), false)
		_sfx_laser.play()


func _enemies_fire(delta: float) -> void:
	for enemy: Enemy in enemies.get_children():
		if enemy.fire <= 0.0:
			continue
		enemy.fire_timer -= delta
		if enemy.fire_timer <= 0.0:
			enemy.fire_timer = enemy.fire * _rng.randf_range(0.7, 1.3)
			spawn_shot(enemy.position + Vector2(0, enemy.size.y / 2.0), Vector2(0, ENEMY_SHOT_SPEED), true)


## Tests the ship's shots against the enemies in their own column of the screen only: with a full wave and a stream of
## shots, testing every shot against every enemy is most of a frame.
func resolve_shot_hits() -> void:
	for column: Array in _columns:
		column.clear()
	for enemy: Enemy in enemies.get_children():
		var half := enemy.size.x / 2.0 + COLUMN_MARGIN
		for c in range(_column_of(enemy.position.x - half), _column_of(enemy.position.x + half) + 1):
			_columns[c].append(enemy)
	for shot: Shot in shots.get_children():
		if shot.hostile or shot.spent:
			continue
		for enemy: Enemy in _columns[_column_of(shot.position.x)]:
			collision_checks += 1
			if enemy.hp > 0 and _overlaps(shot.position, shot.size, enemy.position, enemy.size):
				_shot_hit_enemy(shot, enemy)
				break


func _column_of(x: float) -> int:
	return clampi(int(x / COLUMN_WIDTH), 0, COLUMNS - 1)


func _overlaps(a: Vector2, a_size: Vector2, b: Vector2, b_size: Vector2) -> bool:
	return absf(a.x - b.x) * 2.0 < a_size.x + b_size.x and absf(a.y - b.y) * 2.0 < a_size.y + b_size.y


func _shot_hit_enemy(shot: Shot, enemy: Enemy) -> void:
	shot.spent = true
	var gained := rules.hit_enemy(enemy)
	if enemy.hp <= 0:
		score.hit(gained)
		_enemy_destroyed(enemy)


func _enemy_destroyed(enemy: Enemy) -> void:
	enemies.remove_child(enemy)
	enemy.queue_free()


func _resolve_ship_hits() -> void:
	for shot: Shot in shots.get_children():
		if shot.hostile and not shot.spent and _overlaps(shot.position, shot.size, ship.position, SHIP_SIZE):
			shot.spent = true
			_ship_hit()
	for enemy: Enemy in enemies.get_children():
		if _overlaps(enemy.position, enemy.size, ship.position, SHIP_SIZE) and _ship_hit() and not enemy.boss:
			enemies.remove_child(enemy)
			enemy.queue_free()


## True when the hit cost a life (not while invulnerable).
func _ship_hit() -> bool:
	if state != "playing" or not rules.ship_hit():
		return false
	score.miss()
	_update_hud()
	if rules.is_game_over():
		_finish(false)
	return true


func _remove_spent_shots() -> void:
	for shot: Shot in shots.get_children():
		var gone := shot.position.y < -20.0 or shot.position.y > SCREEN_BOTTOM
		if gone and not shot.hostile and not shot.spent:
			score.miss()
		if gone or shot.spent:
			shots.remove_child(shot)
			shot.queue_free()


func _advance_waves(delta: float) -> void:
	if state != "playing" or enemies.get_child_count() > 0:
		return
	if _next_wave_in < 0.0:
		_next_wave_in = WAVE_DELAY
		return
	_next_wave_in -= delta
	if _next_wave_in > 0.0:
		return
	_next_wave_in = -1.0
	wave_index += 1
	_spawn_wave()


func _spawn_wave() -> void:
	var rows := waves.waves(level)
	if wave_index >= rows.size():
		_level_done()
		return
	var row: Dictionary = rows[wave_index]
	var enemy_row := waves.enemy(str(row.enemy))
	if enemy_row.is_empty():
		push_error("Level %d names an unknown enemy '%s'" % [level, row.enemy])
		return
	for at in _formation(str(row.formation), int(row.count)):
		spawn_enemy(enemy_row, float(row.speed), at)


func _level_done() -> void:
	print("[Run] level %d done" % level)
	if level >= waves.level_count():
		print("[Run] victory")
		_finish(true)
	else:
		start_level(level + 1)


func _formation(kind: String, count: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var columns := mini(count, 6) if kind == "grid" else count
	var spacing := minf(110.0, 1100.0 / maxf(columns, 1))
	for i in count:
		var column := i % columns
		var x := 640.0 + (column - (columns - 1) / 2.0) * spacing
		var y := 100.0
		if kind == "v":
			y += absf(i - (count - 1) / 2.0) * 30.0
		elif kind == "grid":
			y += (i / columns) * 60.0
		points.append(Vector2(x, y))
	return points


func spawn_enemy(row: Dictionary, speed: float, at: Vector2) -> Enemy:
	var enemy := Enemy.new()
	_spawned += 1
	enemy.name = "Enemy%d" % _spawned
	enemy.texture = BOSS_TEXTURE if row.get("boss", false) else ENEMY_TEXTURE
	enemy.setup(row, speed, at)
	enemy.fire_timer = enemy.fire * _rng.randf_range(0.5, 1.5)
	enemies.add_child(enemy)
	return enemy


func spawn_shot(at: Vector2, velocity: Vector2, hostile: bool) -> Shot:
	var shot := Shot.new()
	shot.texture = ENEMY_SHOT_TEXTURE if hostile else SHOT_TEXTURE
	shot.hostile = hostile
	shot.size = Vector2(8, 14) if hostile else Vector2(6, 16)
	shot.position = at
	shot.velocity = velocity
	shots.add_child(shot)
	return shot


func _finish(victory: bool) -> void:
	state = "won" if victory else "lost"
	if not victory:
		print("[Run] game over")
	finished.emit(victory, score.points)
	# On its own (the prototype, or a flow) nobody listens; a bot run then ends here.
	if options.autoplay and finished.get_connections().is_empty():
		get_tree().quit()


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
