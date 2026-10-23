class_name Duel
extends RefCounted
## One duel as plain rules: two keepers, whose turn it is and the turn's phase. A turn runs Draw -> Main -> Clash -> End,
## then the other keeper's Draw. Clash is skipped when the active keeper has no wisp to strike with, and any phase ends in
## Over once a keeper's light is gone. Every transition is logged ([Turn] 3 Main -> Clash) and signalled: nodes animate
## a phase change but never decide one.

signal phase_changed(from: int, to: int)
signal card_played(seat: int, card: Dictionary)
signal wisp_fell(seat: int, lane: int)
signal keeper_hit(seat: int, amount: int)

enum Phase { DRAW, MAIN, CLASH, END, OVER }
const PHASE_NAMES := ["Draw", "Main", "Clash", "End", "Over"]
const HAND_START := 4
const HAND_MAX := 7
const MAX_KINDLING := 6

var cards: Cards
var keepers: Array[Keeper] = []
var phase := Phase.DRAW
## Counts both keepers' turns: turn 1 is seat 0's first, turn 2 seat 1's first.
var turn := 1
var active := 0
## The seat that won; -1 while the duel goes on.
var winner := -1
## The lane the Clash strikes from next.
var clash_lane := 0
var duel_seed := 0
var rng := RandomNumberGenerator.new()


## A new duel: each deck shuffled by the duel's own generator, seeded, then the opening hands dealt. Seat 0 begins.
static func start(catalogue: Cards, decks: Array, lights: Array, seed_value: int) -> Duel:
	var duel := Duel.new()
	duel.cards = catalogue
	duel.duel_seed = seed_value
	duel.rng.seed = seed_value
	for seat in 2:
		var keeper := Keeper.new()
		keeper.light = int(lights[seat])
		keeper.max_light = keeper.light
		keeper.deck = Deck.shuffled(decks[seat], duel.rng)
		duel.keepers.append(keeper)
	for seat in 2:
		for i in HAND_START:
			duel.draw_card(seat)
	return duel


func phase_name() -> String:
	return PHASE_NAMES[phase]


## Draws the top card. A card drawn into a full hand goes to the discard pile; an empty deck gives nothing.
func draw_card(seat: int) -> bool:
	var keeper := keepers[seat]
	if keeper.deck.is_empty():
		return false
	var id: String = keeper.deck.pop_front()
	if keeper.hand.size() >= HAND_MAX:
		keeper.discard.append(id)
		return false
	keeper.hand.append(id)
	return true


## Moves the duel on by one step: Draw draws and opens Main, Main ends (as end_main), each Clash step strikes one lane,
## End passes the turn. Main waits for plays; Over does nothing.
func advance() -> void:
	match phase:
		Phase.DRAW:
			var keeper := keepers[active]
			keeper.turns += 1
			keeper.kindling = mini(keeper.turns, MAX_KINDLING)
			draw_card(active)
			if phase == Phase.DRAW:
				_go(Phase.MAIN)
		Phase.MAIN:
			end_main()
		Phase.CLASH:
			_strike_next()
		Phase.END:
			active = 1 - active
			turn += 1
			_go(Phase.DRAW)


## Main -> Clash when the active keeper has a wisp to strike with; a phase with nothing to do is skipped.
func end_main() -> void:
	if phase != Phase.MAIN:
		return
	clash_lane = 0
	_go(Phase.CLASH if keepers[active].wisp_count() > 0 or keepers[1 - active].wisp_count() > 0 else Phase.END)


## Whether the active keeper may play this card of its hand now: its Main phase, the kindling for it, a free lane for a
## wisp, and something to act on for a rite that needs it.
func can_play(seat: int, index: int) -> bool:
	if phase != Phase.MAIN or seat != active or index < 0 or index >= keepers[seat].hand.size():
		return false
	var keeper := keepers[seat]
	var card := cards.card(keeper.hand[index])
	if card.cost > keeper.kindling:
		return false
	if card.kind == Cards.WISP:
		return keeper.free_lane() >= 0
	match card.effect:
		"douse":
			return strongest_lane(1 - seat) >= 0
		"rekindle":
			return last_fallen(seat) >= 0
	return true


## Plays a card of the active keeper's hand: a wisp to the first free lane, a rite resolved once and discarded.
func play(seat: int, index: int) -> bool:
	if not can_play(seat, index):
		return false
	var keeper := keepers[seat]
	var id: String = keeper.hand[index]
	var card := cards.card(id)
	keeper.hand.remove_at(index)
	keeper.kindling -= card.cost
	card_played.emit(seat, card)
	if card.kind == Cards.WISP:
		keeper.row[keeper.free_lane()] = {"id": id, "power": card.power, "guard": card.guard}
	else:
		keeper.discard.append(id)
		_resolve(seat, card)
	return true


func _resolve(seat: int, card: Dictionary) -> void:
	var keeper := keepers[seat]
	var amount: int = card.amount
	match card.effect:
		"bolt":
			_burn(1 - seat, amount)
		"mend":
			keeper.light = mini(keeper.light + amount, keeper.max_light)
		"draw":
			for i in amount:
				draw_card(seat)
		"douse":
			_wound(1 - seat, strongest_lane(1 - seat), amount)
		"rekindle":
			var at := last_fallen(seat)
			keeper.hand.append(keeper.discard[at])
			keeper.discard.remove_at(at)


## The lane of a keeper's strongest wisp (most power, then the first lane); -1 when its row is empty.
func strongest_lane(seat: int) -> int:
	var best := -1
	for lane in Keeper.LANES:
		var wisp: Variant = keepers[seat].row[lane]
		if wisp != null and (best < 0 or wisp.power > keepers[seat].row[best].power):
			best = lane
	return best


## Where in a keeper's discard pile the newest wisp lies; -1 when there is none.
func last_fallen(seat: int) -> int:
	var pile := keepers[seat].discard
	for at in range(pile.size() - 1, -1, -1):
		if cards.card(pile[at]).kind == Cards.WISP:
			return at
	return -1


## One lane of the Clash: the active keeper's next wisp strikes the wisp across, each taking the other's power, or the
## other keeper's light when the lane across is empty. Clash -> End once no wisp is left to strike.
func _strike_next() -> void:
	var me := keepers[active]
	var foe := keepers[1 - active]
	while clash_lane < Keeper.LANES and me.row[clash_lane] == null:
		clash_lane += 1
	if clash_lane >= Keeper.LANES:
		_go(Phase.END)
		return
	var lane := clash_lane
	clash_lane += 1
	var wisp: Dictionary = me.row[lane]
	if foe.row[lane] == null:
		_burn(1 - active, wisp.power)
		return
	var taken: int = foe.row[lane].power
	_wound(1 - active, lane, wisp.power)
	_wound(active, lane, taken)


func _wound(seat: int, lane: int, amount: int) -> void:
	var wisp: Dictionary = keepers[seat].row[lane]
	wisp.guard -= amount
	if wisp.guard <= 0:
		keepers[seat].row[lane] = null
		keepers[seat].discard.append(wisp.id)
		wisp_fell.emit(seat, lane)


## Takes light from a keeper; at 0 the duel is over and the other keeper has won.
func _burn(seat: int, amount: int) -> void:
	keepers[seat].light -= amount
	keeper_hit.emit(seat, amount)
	if keepers[seat].light <= 0 and winner < 0:
		winner = 1 - seat
		_go(Phase.OVER)


func _go(to: int) -> void:
	var from := phase
	phase = to as Phase
	print("[Turn] %d %s -> %s" % [turn, PHASE_NAMES[from], PHASE_NAMES[to]])
	phase_changed.emit(from, to)


## Everything needed to carry on later from where the duel stands.
func to_dict() -> Dictionary:
	return {
		"seed": duel_seed,
		"turn": turn,
		"active": active,
		"phase": PHASE_NAMES[phase],
		"clash_lane": clash_lane,
		"winner": winner,
		"keepers": [keepers[0].to_dict(), keepers[1].to_dict()],
	}


static func from_dict(catalogue: Cards, data: Dictionary) -> Duel:
	var duel := Duel.new()
	duel.cards = catalogue
	duel.duel_seed = int(data.get("seed", 0))
	duel.rng.seed = duel.duel_seed
	duel.turn = int(data.get("turn", 1))
	duel.active = clampi(int(data.get("active", 0)), 0, 1)
	duel.phase = maxi(PHASE_NAMES.find(str(data.get("phase", "Main"))), 0) as Phase
	duel.clash_lane = int(data.get("clash_lane", 0))
	duel.winner = int(data.get("winner", -1))
	var sides: Variant = data.get("keepers", [])
	for seat in 2:
		var side: Variant = sides[seat] if typeof(sides) == TYPE_ARRAY and seat < sides.size() else {}
		duel.keepers.append(Keeper.from_dict(side if typeof(side) == TYPE_DICTIONARY else {}))
	return duel
