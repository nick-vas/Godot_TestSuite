class_name Cards
extends RefCounted
## The card catalogue, read from data/cards.json: every card a deck may hold. A wisp stands in a lane and strikes in the
## Clash; a rite acts once, when played, and goes to the discard pile. Read-only while a match runs.

const PATH := "res://data/cards.json"
const WISP := "wisp"
const RITE := "rite"
## What a rite does: bolt burns the other keeper's light, mend restores one's own, draw draws cards, douse wounds the
## strongest wisp across, rekindle returns the wisp that fell last to the hand.
const EFFECTS := ["bolt", "mend", "draw", "douse", "rekindle"]

var _cards := {}
var _order: Array[String] = []


static func from_file(path := PATH) -> Cards:
	var catalogue := Cards.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Cards: %s is not a JSON array" % path)
		return catalogue
	for entry: Variant in parsed:
		if typeof(entry) == TYPE_DICTIONARY:
			catalogue.add(entry)
	return catalogue


## Adds a card with every field present and numbers as ints (JSON gives floats).
func add(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	if not _cards.has(id):
		_order.append(id)
	_cards[id] = {
		"id": id,
		"name": str(entry.get("name", id)),
		"kind": str(entry.get("kind", WISP)),
		"cost": int(entry.get("cost", 0)),
		"power": int(entry.get("power", 0)),
		"guard": int(entry.get("guard", 0)),
		"effect": str(entry.get("effect", "")),
		"amount": int(entry.get("amount", 0)),
	}


func has(id: String) -> bool:
	return _cards.has(id)


func card(id: String) -> Dictionary:
	return _cards.get(id, {})


## Card ids in the file's order.
func ids() -> Array[String]:
	return _order.duplicate()
