extends Node2D
## The prototype: the ship, its shots and one wave of six grunts. Everything happens in _physics_process at a fixed
## 60 ticks; the score and the lives live in Score and Rules, which the tests cover.

signal finished(victory: bool, points: int)

const SHIP_Y := 650.0
const SHIP_SPEED := 420.0
const SHIP_SIZE := Vector2(48, 32)
const SHIP_MIN_X := 40.0
const SHIP_MAX_X := 1240.0
const SHOT_SPEED := 720.0
const FIRE_COOLDOWN := 0.18
const SCREEN_BOTTOM := 740.0
## The one wave of the prototype.
const GRUNT := {"id": "grunt", "hp": 1, "points": 100, "drift": 0, "fire": 0, "color": "#e05050", "boss": false}
const WAVE_SIZE := 6
const WAVE_SPEED := 40.0

const SHOT_TEXTURE := preload("res://art/shot.png")
const ENEMY_TEXTURE := preload("res://art/enemy.png")

var score := Score.new()
var rules := Rules.new()
var state := "playing"

var _ticks := 0
var _cooldown := 0.0
var _spawned := 0

@onready var ship: Sprite2D = $Ship
@onready var enemies: Node2D = $Enemies
@onready var shots: Node2D = $Shots
@onready var _score_label: Label = $HUD/ScoreLabel
@onready var _lives_label: Label = $HUD/LivesLabel


func _ready() -> void:
	score.changed.connect(_update_hud)
	ship.position = Vector2(640, SHIP_Y)
	_update_hud()
	for i in WAVE_SIZE:
		var spacing := 110.0
		spawn_enemy(GRUNT, WAVE_SPEED, Vector2(640.0 + (i - (WAVE_SIZE - 1) / 2.0) * spacing, 100.0))


func _update_hud() -> void:
	_score_label.text = "Score: %d" % score.points
	_lives_label.text = "Lives: %d" % rules.lives


func _physics_process(delta: float) -> void:
	if state != "playing":
		return
	_ticks += 1
	rules.tick(delta)
	_move_ship(delta)
	_resolve_shot_hits()
	_resolve_ship_hits()
	_remove_spent_shots()
	if enemies.get_child_count() == 0:
		print("[Run] level 1 done")
		_finish(true)


func _move_ship(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	ship.position.x = clampf(ship.position.x + direction * SHIP_SPEED * delta, SHIP_MIN_X, SHIP_MAX_X)
	ship.visible = not rules.is_invulnerable() or (_ticks / 6) % 2 == 0
	_cooldown -= delta
	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_cooldown = FIRE_COOLDOWN
		spawn_shot(ship.position + Vector2(0, -24), Vector2(0, -SHOT_SPEED))


func _resolve_shot_hits() -> void:
	for shot: Shot in shots.get_children():
		if shot.spent:
			continue
		for enemy: Enemy in enemies.get_children():
			if enemy.hp > 0 and _overlaps(shot.position, shot.size, enemy.position, enemy.size):
				shot.spent = true
				var gained := rules.hit_enemy(enemy)
				if enemy.hp <= 0:
					score.hit(gained)
					enemies.remove_child(enemy)
					enemy.queue_free()
				break


func _resolve_ship_hits() -> void:
	for enemy: Enemy in enemies.get_children():
		if _overlaps(enemy.position, enemy.size, ship.position, SHIP_SIZE) and rules.ship_hit():
			score.miss()
			_update_hud()
			enemies.remove_child(enemy)
			enemy.queue_free()
			if rules.is_game_over():
				print("[Run] game over")
				_finish(false)


func _remove_spent_shots() -> void:
	for shot: Shot in shots.get_children():
		var gone := shot.position.y < -20.0 or shot.position.y > SCREEN_BOTTOM
		if gone and not shot.spent:
			score.miss()
		if gone or shot.spent:
			shots.remove_child(shot)
			shot.queue_free()


func _overlaps(a: Vector2, a_size: Vector2, b: Vector2, b_size: Vector2) -> bool:
	return absf(a.x - b.x) * 2.0 < a_size.x + b_size.x and absf(a.y - b.y) * 2.0 < a_size.y + b_size.y


func spawn_enemy(row: Dictionary, speed: float, at: Vector2) -> Enemy:
	var enemy := Enemy.new()
	_spawned += 1
	enemy.name = "Enemy%d" % _spawned
	enemy.texture = ENEMY_TEXTURE
	enemy.setup(row, speed, at)
	enemies.add_child(enemy)
	return enemy


func spawn_shot(at: Vector2, velocity: Vector2) -> Shot:
	var shot := Shot.new()
	shot.texture = SHOT_TEXTURE
	shot.position = at
	shot.velocity = velocity
	shots.add_child(shot)
	return shot


func _finish(victory: bool) -> void:
	state = "won" if victory else "lost"
	finished.emit(victory, score.points)
