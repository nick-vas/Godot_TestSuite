class_name Rivals
extends RefCounted
## The ladder's rivals (data/rivals.json) and every deck (data/decks.json): each rival's name (a translation key), the
## light it starts with, its deck and its AI's weights. The player's deck is the deck "keeper", with KEEPER_LIGHT.

const RIVALS_PATH := "res://data/rivals.json"
const DECKS_PATH := "res://data/decks.json"
const KEEPER_DECK := "keeper"
const KEEPER_LIGHT := 20

var _rivals := {}
var _decks := {}


static func from_files(rivals_path := RIVALS_PATH, decks_path := DECKS_PATH) -> Rivals:
	var rivals := Rivals.new()
	for entry: Variant in _read(decks_path):
		if typeof(entry) == TYPE_DICTIONARY:
			var cards: Array[String] = []
			for id: Variant in entry.get("cards", []):
				cards.append(str(id))
			rivals._decks[str(entry.get("id", ""))] = cards
	for entry: Variant in _read(rivals_path):
		if typeof(entry) == TYPE_DICTIONARY:
			var id := int(entry.get("id", 0))
			rivals._rivals[id] = {
				"id": id,
				"name": str(entry.get("name", "")),
				"deck": str(entry.get("deck", "")),
				"light": int(entry.get("light", KEEPER_LIGHT)),
				"aggression": float(entry.get("aggression", 1.0)),
				"caution": float(entry.get("caution", 1.0)),
			}
	return rivals


static func _read(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Rivals: %s is not a JSON array" % path)
		return []
	return parsed


## Rivals are numbered 1 to count(), the ladder's order.
func count() -> int:
	return _rivals.size()


func has_rival(id: int) -> bool:
	return _rivals.has(id)


func rival(id: int) -> Dictionary:
	return _rivals.get(id, {})


func has_deck(id: String) -> bool:
	return _decks.has(id)


func deck(id: String) -> Array[String]:
	var cards: Array[String] = []
	cards.assign(_decks.get(id, []))
	return cards


## The AI that plays a rival, with its weights.
func ai_for(id: int) -> Ai:
	var entry := rival(id)
	return Ai.new(float(entry.get("aggression", 1.0)), float(entry.get("caution", 1.0)))


## A duel of the player's deck against a rival's.
func start_duel(catalogue: Cards, id: int, seed_value: int) -> Duel:
	var entry := rival(id)
	return Duel.start(catalogue, [deck(KEEPER_DECK), deck(str(entry.deck))], [KEEPER_LIGHT, int(entry.light)], seed_value)
