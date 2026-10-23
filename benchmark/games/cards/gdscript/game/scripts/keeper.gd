class_name Keeper
extends RefCounted
## One side of a duel: its light (lose it all and the duel is lost), the kindling it can spend this turn, and its cards:
## the deck it draws from (the first card is the top), the hand, the discard pile (the last card is the newest) and the
## row of three lanes where its wisps stand.

const LANES := 3

var light := 20
## The light it started with; mending never goes above it.
var max_light := 20
var kindling := 0
## How many turns it has begun: its kindling each turn is that, up to Duel.MAX_KINDLING.
var turns := 0
## How many times it drew from an empty deck; the nth such draw costs n light.
var fatigue := 0
var deck: Array[String] = []
var hand: Array[String] = []
var discard: Array[String] = []
## A wisp per lane, or null: { "id", "power", "guard" }, guard being what it has left.
var row: Array = [null, null, null]


func wisp_count() -> int:
	var count := 0
	for wisp: Variant in row:
		if wisp != null:
			count += 1
	return count


## The first empty lane, -1 when the row is full.
func free_lane() -> int:
	for lane in LANES:
		if row[lane] == null:
			return lane
	return -1


## Everything a saved duel needs to put this keeper back as it was.
func to_dict() -> Dictionary:
	return {
		"light": light,
		"max_light": max_light,
		"kindling": kindling,
		"turns": turns,
		"fatigue": fatigue,
		"deck": deck.duplicate(),
		"hand": hand.duplicate(),
		"discard": discard.duplicate(),
		"row": row.duplicate(true),
	}


static func from_dict(data: Dictionary) -> Keeper:
	var keeper := Keeper.new()
	keeper.light = int(data.get("light", 20))
	keeper.max_light = int(data.get("max_light", keeper.light))
	keeper.kindling = int(data.get("kindling", 0))
	keeper.turns = int(data.get("turns", 0))
	keeper.fatigue = int(data.get("fatigue", 0))
	keeper.deck.assign(_ids(data.get("deck", [])))
	keeper.hand.assign(_ids(data.get("hand", [])))
	keeper.discard.assign(_ids(data.get("discard", [])))
	var lanes: Variant = data.get("row", [])
	for lane in LANES:
		if typeof(lanes) == TYPE_ARRAY and lane < lanes.size() and typeof(lanes[lane]) == TYPE_DICTIONARY:
			var wisp: Dictionary = lanes[lane]
			keeper.row[lane] = {"id": str(wisp.get("id", "")), "power": int(wisp.get("power", 0)), "guard": int(wisp.get("guard", 1))}
	return keeper


static func _ids(list: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(list) == TYPE_ARRAY:
		for id: Variant in list:
			out.append(str(id))
	return out
