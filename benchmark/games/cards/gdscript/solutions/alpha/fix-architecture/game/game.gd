extends Node2D
## One duel against a rival on the table: the hand, the HUD, pause and the result panel. Main starts it with setup(); on
## its own (a flow, a test, the editor) it reads the command line and the data itself.
## The rules live in Duel; this node only paces them. Each Draw, Clash strike and End waits a few ticks so it can be
## seen, the rival's AI thinks before each play, and the player's Main phase waits for a card or End turn.

## A duel ended: Main records it on the ladder.
signal duel_over(rival: int, won: bool)
## The player's Main phase began: Main keeps this duel in the save, for Continue.
signal checkpoint(data: Dictionary)
## The run is over: victory after the last rival.
signal finished(victory: bool)
signal menu_requested

## Ticks a Draw, the end of a Main phase or an End takes on screen.
const PHASE_TICKS := 8
## Ticks between two strikes of a Clash: more than the juice window, so each strike's feedback is its own.
const STRIKE_TICKS := 9
## Ticks an AI thinks before each play.
const THINK_TICKS := 10
## The translation keys of Duel's phases, in Duel.Phase order, and of what each rite does.
const PHASE_KEYS := ["PHASE_DRAW", "PHASE_MAIN", "PHASE_CLASH", "PHASE_END", "PHASE_OVER"]
const EFFECT_KEYS := {"bolt": "EFFECT_BOLT", "mend": "EFFECT_MEND", "draw": "EFFECT_DRAW", "douse": "EFFECT_DOUSE", "rekindle": "EFFECT_REKINDLE"}

var rivals: Rivals
var cards: Cards
var options: LaunchOptions
var duel: Duel
var rival := 1
## "playing", "over" (the result is shown) or "done".
var state := "playing"
## The card of the hand the player's AI would play: the HUD marks it. -1 when there is none.
var suggested := -1
## How many times the game asked the AI for a suggestion, for the performance test.
var suggest_checks := 0
var phase: String:
	get:
		return duel.phase_name() if duel else ""
var active: int:
	get:
		return duel.active if duel else 0
var turn: int:
	get:
		return duel.turn if duel else 0

var _first_rival := 0
var _saved := {}
var _rival_ai: Ai
var _hint_ai := Ai.new()
var _duels := 0
var _ticks := 0
var _wait := 0
var _shake := 0.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()

@onready var table: Node2D = $Table
@onready var _camera: Camera2D = $Camera
@onready var _rival_label: Label = $HUD/RivalLabel
@onready var _rival_light: Label = $HUD/RivalLight
@onready var _player_light: Label = $HUD/PlayerLight
@onready var _kindling_label: Label = $HUD/KindlingLabel
@onready var _turn_label: Label = $HUD/TurnLabel
@onready var _hand: HBoxContainer = $HUD/Hand
@onready var _end_turn: Button = $HUD/EndTurnButton
@onready var _pause_button: Button = $HUD/PauseButton
@onready var _flash_rect: ColorRect = $HUD/Flash
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _result_menu: CanvasLayer = $ResultMenu
@onready var _sfx_play: AudioStreamPlayer = $SfxPlay
@onready var _sfx_hit: AudioStreamPlayer = $SfxHit
@onready var _sfx_fall: AudioStreamPlayer = $SfxFall
@onready var _sfx_win: AudioStreamPlayer = $SfxWin


## first_rival: the rival to face (the command line's --rival when 0); saved: a duel from the save to carry on instead.
func setup(game_rivals: Rivals, game_cards: Cards, game_options: LaunchOptions, first_rival := 0, saved := {}) -> void:
	rivals = game_rivals
	cards = game_cards
	options = game_options
	_first_rival = first_rival
	_saved = saved


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	if rivals == null:
		rivals = Rivals.from_files()
	if cards == null:
		cards = Cards.from_file()
	_rng.seed = options.run_seed
	_end_turn.pressed.connect(end_turn)
	_pause_button.pressed.connect(_pause_menu.open)
	_pause_menu.quit_pressed.connect(menu_requested.emit)
	_result_menu.next_pressed.connect(next_rival)
	_result_menu.rematch_pressed.connect(rematch)
	_result_menu.menu_pressed.connect(menu_requested.emit)
	_refresh_text()
	if not _saved.is_empty():
		resume(_saved)
	else:
		start_rival(_first_rival if _first_rival > 0 else options.rival)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_end_turn.text = tr("HUD_END_TURN")
	_pause_button.text = tr("HUD_PAUSE")
	_refresh()


## A new duel against a rival; seed_value -1 takes the run's next seed.
func start_rival(id: int, seed_value := -1) -> void:
	if not rivals.has_rival(id):
		push_error("There is no rival %d" % id)
		return
	rival = id
	var duel_seed := seed_value if seed_value >= 0 else _next_seed()
	print("[Run] rival %d, seed %d" % [id, duel_seed])
	_begin(rivals.start_duel(cards, id, duel_seed))


## Carries on a duel kept in the save (Duel.to_dict plus "rival").
func resume(data: Dictionary) -> void:
	rival = int(data.get("rival", 1))
	if not rivals.has_rival(rival):
		rival = 1
	_begin(Duel.from_dict(cards, data))
	if duel.phase == Duel.Phase.MAIN and duel.active == 0:
		_suggest()


func _begin(next_duel: Duel) -> void:
	duel = next_duel
	duel.phase_changed.connect(_on_phase_changed)
	duel.card_played.connect(_on_card_played)
	duel.keeper_hit.connect(_on_keeper_hit)
	duel.wisp_fell.connect(_on_wisp_fell)
	_rival_ai = rivals.ai_for(rival)
	state = "playing"
	suggested = -1
	_wait = PHASE_TICKS
	_result_menu.close()
	table.show_duel(duel, cards)
	_refresh()


## The run's seeds: from --seed, one per duel in order, so a run replays; at random without it.
func _next_seed() -> int:
	_duels += 1
	if options.run_seed > 0:
		return options.run_seed * 1009 + _duels
	return randi() % 1000000


func next_rival() -> void:
	if state != "over":
		return
	if rivals.has_rival(rival + 1):
		start_rival(rival + 1)
	else:
		print("[Run] victory")
		_finish(true)


func rematch() -> void:
	if state == "over":
		start_rival(rival)


func game_ms() -> float:
	return _ticks * 1000.0 / Engine.physics_ticks_per_second


func _is_players_main() -> bool:
	return state == "playing" and duel.phase == Duel.Phase.MAIN and duel.active == 0


## Plays a card of the player's hand; false when it is not the player's Main phase or the rules refuse it.
func play_card(index: int) -> bool:
	if not _is_players_main() or not duel.play(0, index):
		return false
	_suggest()
	_refresh()
	return true


## Ends the player's Main phase.
func end_turn() -> void:
	if _is_players_main():
		duel.end_main()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("end_turn") and _is_players_main():
		end_turn()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_ticks += 1
	_update_effects(delta)
	if state != "playing":
		return
	if _wait > 0:
		_wait -= 1
		return
	match duel.phase:
		Duel.Phase.MAIN:
			if duel.active == 1:
				_ai_turn()
		Duel.Phase.CLASH:
			duel.advance()
			_wait = STRIKE_TICKS
		Duel.Phase.OVER:
			pass
		_:
			duel.advance()
			_wait = PHASE_TICKS


## The rival's AI makes one play, or ends its Main phase.
func _ai_turn() -> void:
	var seat := duel.active
	var ai := _rival_ai
	var index := ai.choose(duel, seat)
	print("[AI] turn %d seat %d: %s -> %s" % [duel.turn, seat, ai.describe(), duel.keepers[seat].hand[index] if index >= 0 else "pass"])
	if index < 0:
		duel.end_main()
		_wait = PHASE_TICKS
		return
	duel.play(seat, index)
	_refresh()
	_wait = THINK_TICKS


func _on_phase_changed(_from: int, to: int) -> void:
	_refresh()
	if to == Duel.Phase.MAIN and duel.active == 0:
		var data := duel.to_dict()
		data.rival = rival
		checkpoint.emit(data)
		_suggest()
	elif to == Duel.Phase.OVER:
		_over()


## Asks the AI which card it would play in the player's place, once per change: the HUD marks that card.
func _suggest() -> void:
	suggest_checks += 1
	suggested = _hint_ai.choose(duel, 0) if _is_players_main() else -1
	_refresh_hand()


func _over() -> void:
	state = "over"
	var won := duel.winner == 0
	print("[Run] rival %d %s" % [rival, "won" if won else "lost"])
	if won:
		_sfx_win.play()
	duel_over.emit(rival, won)
	_result_menu.open(won, "RESULT_NEXT" if rivals.has_rival(rival + 1) else "RESULT_FINISH")


func _finish(victory: bool) -> void:
	state = "done"
	finished.emit(victory)


func _refresh() -> void:
	if duel == null or not is_node_ready():
		return
	var name_key := str(rivals.rival(rival).get("name", ""))
	_rival_label.text = tr(name_key)
	_rival_light.text = tr("HUD_LIGHT") % duel.keepers[1].light
	_player_light.text = tr("HUD_LIGHT") % duel.keepers[0].light
	_kindling_label.text = tr("HUD_KINDLING") % [duel.keepers[0].kindling, mini(duel.keepers[0].turns, Duel.MAX_KINDLING)]
	_turn_label.text = tr("HUD_TURN") % [duel.turn, tr(PHASE_KEYS[duel.phase]), tr("HUD_YOU") if duel.active == 0 else tr(name_key)]
	_end_turn.disabled = not _is_players_main()
	_refresh_hand()
	table.queue_redraw()


## One button per card of the player's hand, Card0 first; only playable ones are enabled, the suggested one marked.
func _refresh_hand() -> void:
	if duel == null:
		return
	var hand := duel.keepers[0].hand
	while _hand.get_child_count() > hand.size():
		var extra := _hand.get_child(_hand.get_child_count() - 1)
		_hand.remove_child(extra)
		extra.queue_free()
	while _hand.get_child_count() < hand.size():
		var button := Button.new()
		var index := _hand.get_child_count()
		button.name = "Card%d" % index
		button.custom_minimum_size = Vector2(150, 130)
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 17)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(play_card.bind(index))
		_hand.add_child(button)
	for index in hand.size():
		var button: Button = _hand.get_child(index)
		button.text = card_text(cards.card(hand[index]))
		button.disabled = not (_is_players_main() and duel.can_play(0, index))
		button.modulate = Color(1.0, 0.92, 0.55) if index == suggested else Color.WHITE


## A card's face as text: its name, cost, and power / guard for a wisp or what a rite does.
func card_text(card: Dictionary) -> String:
	var stats := "%d / %d" % [card.power, card.guard] if card.kind == Cards.WISP else tr(EFFECT_KEYS.get(card.effect, "")) % card.amount
	return "%s\n%s\n%s" % [tr(card.name), tr("CARD_COST") % card.cost, stats]


func _on_card_played(_seat: int, _card: Dictionary) -> void:
	_event("card_played")
	_play(_sfx_play)
	table.queue_redraw()


func _on_keeper_hit(seat: int, _amount: int) -> void:
	_event("keeper_hit")
	_flash_screen(Color(1.0, 0.3, 0.2, 0.35) if seat == 0 else Color(1.0, 0.85, 0.4, 0.3))
	_shake_camera(8.0)
	_play(_sfx_hit)
	_refresh()


func _on_wisp_fell(seat: int, lane: int) -> void:
	_event("wisp_fell")
	table.pop(seat, lane)
	_feedback("pop")
	_play(_sfx_fall)
	table.queue_redraw()


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


func _play(player: AudioStreamPlayer) -> void:
	player.play()
	_feedback("sfx")


func _update_effects(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.0, 0.0)
	_flash_rect.color.a = _flash
	_shake = maxf(_shake - delta * 40.0, 0.0)
	_camera.offset = Vector2(_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake)) if _shake > 0.0 else Vector2.ZERO
