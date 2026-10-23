extends Node2D
## One duel against the first rival on the table, with the player's hand and End turn.
## The rules live in Duel; this node only paces them. Each Draw, Clash strike and End waits a few ticks so it can be
## seen, the rival's AI thinks before each play, and the player's Main phase waits for a card or End turn.

## Ticks a Draw, the end of a Main phase or an End takes on screen.
const PHASE_TICKS := 8
## Ticks between two strikes of a Clash.
const STRIKE_TICKS := 9
## Ticks the rival's AI thinks before each play.
const THINK_TICKS := 10
const PHASE_NAMES := ["Draw", "Main", "Clash", "End", "Over"]

var rivals: Rivals
var cards: Cards
var duel: Duel
var rival := 1
## "playing" or "over".
var state := "playing"
var phase: String:
	get:
		return duel.phase_name() if duel else ""
var active: int:
	get:
		return duel.active if duel else 0
var turn: int:
	get:
		return duel.turn if duel else 0

var _rival_ai: Ai
var _wait := 0

@onready var table: Node2D = $Table
@onready var _rival_label: Label = $HUD/RivalLabel
@onready var _rival_light: Label = $HUD/RivalLight
@onready var _player_light: Label = $HUD/PlayerLight
@onready var _kindling_label: Label = $HUD/KindlingLabel
@onready var _turn_label: Label = $HUD/TurnLabel
@onready var _hand: HBoxContainer = $HUD/Hand
@onready var _end_turn: Button = $HUD/EndTurnButton


func _ready() -> void:
	rivals = Rivals.from_files()
	cards = Cards.from_file()
	_end_turn.pressed.connect(end_turn)
	start_rival(1)


## A new duel against a rival; seed_value -1 shuffles at random.
func start_rival(id: int, seed_value := -1) -> void:
	rival = id
	duel = rivals.start_duel(cards, id, seed_value if seed_value >= 0 else randi() % 1000000)
	duel.phase_changed.connect(_on_phase_changed)
	_rival_ai = rivals.ai_for(id)
	state = "playing"
	_wait = PHASE_TICKS
	table.show_duel(duel, cards)
	_refresh()


func _is_players_main() -> bool:
	return state == "playing" and duel.phase == Duel.Phase.MAIN and duel.active == 0


## Plays a card of the player's hand; false when it is not the player's Main phase or the rules refuse it.
func play_card(index: int) -> bool:
	if not _is_players_main() or not duel.play(0, index):
		return false
	_refresh()
	return true


func end_turn() -> void:
	if _is_players_main():
		duel.end_main()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("end_turn") and _is_players_main():
		end_turn()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
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


## The rival makes one play, or ends its Main phase.
func _ai_turn() -> void:
	var index := _rival_ai.choose(duel, 1)
	if index < 0:
		duel.end_main()
		_wait = PHASE_TICKS
		return
	duel.play(1, index)
	_refresh()
	_wait = THINK_TICKS


func _on_phase_changed(_from: int, to: int) -> void:
	if to == Duel.Phase.OVER:
		state = "over"
	_refresh()


func _refresh() -> void:
	if duel == null or not is_node_ready():
		return
	_rival_label.text = "Rival %d" % rival
	_rival_light.text = "Light: %d" % duel.keepers[1].light
	_player_light.text = "Light: %d" % duel.keepers[0].light
	_kindling_label.text = "Kindling: %d / %d" % [duel.keepers[0].kindling, mini(duel.keepers[0].turns, Duel.MAX_KINDLING)]
	if state == "over":
		_turn_label.text = "You won" if duel.winner == 0 else "You lost"
	else:
		_turn_label.text = "Turn %d: %s (%s)" % [duel.turn, PHASE_NAMES[duel.phase], "you" if duel.active == 0 else "rival"]
	_end_turn.disabled = not _is_players_main()
	_refresh_hand()
	table.queue_redraw()


## One button per card of the player's hand, Card0 first; only playable ones are enabled.
func _refresh_hand() -> void:
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
		button.add_theme_font_size_override("font_size", 17)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(play_card.bind(index))
		_hand.add_child(button)
	for index in hand.size():
		var button: Button = _hand.get_child(index)
		var card := cards.card(hand[index])
		var stats := "%d / %d" % [card.power, card.guard] if card.kind == Cards.WISP else "%s %d" % [str(card.effect).capitalize(), card.amount]
		button.text = "%s\nCost %d\n%s" % [str(card.id).capitalize(), card.cost, stats]
		button.disabled = not (_is_players_main() and duel.can_play(0, index))
