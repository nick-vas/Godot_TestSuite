extends Node2D
## Draws the table: the rival's row of three lanes above the player's, each wisp as a card with its name, power and
## guard, and a ring that spreads where a wisp falls. It reads the duel; it never changes it.

const CARD_SIZE := Vector2(150, 110)
const LANE_X := [440.0, 640.0, 840.0]
## The rows' centres: the rival's (seat 1) above, the player's (seat 0) below.
const ROW_Y := [385.0, 205.0]
const SEAT_COLORS := [Color(0.2, 0.55, 0.5), Color(0.45, 0.3, 0.6)]
const LANE_COLOR := Color(1, 1, 1, 0.12)
const POP_SECONDS := 0.4

var duel: Duel
var cards: Cards
## Rings where wisps fell: { "at": Vector2, "age": seconds }.
var _pops: Array[Dictionary] = []


func show_duel(shown: Duel, catalogue: Cards) -> void:
	duel = shown
	cards = catalogue
	_pops.clear()
	queue_redraw()


func lane_center(seat: int, lane: int) -> Vector2:
	return Vector2(LANE_X[lane], ROW_Y[seat])


## A ring where a wisp fell.
func pop(seat: int, lane: int) -> void:
	_pops.append({"at": lane_center(seat, lane), "age": 0.0})
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _pops.is_empty():
		return
	for ring in _pops:
		ring.age += delta
	_pops = _pops.filter(func(ring: Dictionary) -> bool: return ring.age < POP_SECONDS)
	queue_redraw()


func _draw() -> void:
	if duel == null:
		return
	var font := ThemeDB.fallback_font
	for seat in 2:
		for lane in Keeper.LANES:
			var rect := Rect2(lane_center(seat, lane) - CARD_SIZE / 2.0, CARD_SIZE)
			var wisp: Variant = duel.keepers[seat].row[lane]
			if wisp == null:
				draw_rect(rect, LANE_COLOR, false, 2.0)
				continue
			draw_rect(rect, SEAT_COLORS[seat])
			draw_rect(rect, SEAT_COLORS[seat].lightened(0.4), false, 2.0)
			var name_text := tr(str(cards.card(wisp.id).get("name", wisp.id)))
			draw_string(font, rect.position + Vector2(0, 30), name_text, HORIZONTAL_ALIGNMENT_CENTER, CARD_SIZE.x, 16)
			draw_string(font, rect.position + Vector2(0, 84), "%d / %d" % [wisp.power, wisp.guard], HORIZONTAL_ALIGNMENT_CENTER, CARD_SIZE.x, 30)
	for ring in _pops:
		var t: float = ring.age / POP_SECONDS
		draw_arc(ring.at, 30.0 + 60.0 * t, 0.0, TAU, 32, Color(1.0, 0.8, 0.4, 1.0 - t), 4.0)
