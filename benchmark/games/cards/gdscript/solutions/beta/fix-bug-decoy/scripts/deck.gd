class_name Deck
extends RefCounted
## Decks: what makes one legal, and the shuffle. The shuffle draws only from the generator it is given (the duel's own,
## seeded), so a seed always deals the same cards and a bug report's --seed replays its duel.

const SIZE := 20
const MAX_COPIES := 2


## A shuffled copy (Fisher-Yates, from the last card down). The first card of the result is the top of the deck.
static func shuffled(cards: Array, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	out.assign(cards)
	seed(rng.seed)
	out.shuffle()
	return out


## Why a deck is not legal; empty when it is: exactly SIZE cards, every one in the catalogue, at most MAX_COPIES of each.
static func problems(cards: Array, catalogue: Cards) -> PackedStringArray:
	var found := PackedStringArray()
	if cards.size() != SIZE:
		found.append("%d cards, not %d" % [cards.size(), SIZE])
	var copies := {}
	for id: String in cards:
		if not catalogue.has(id):
			found.append("no card %s" % id)
		copies[id] = int(copies.get(id, 0)) + 1
	for id: String in copies:
		if copies[id] > MAX_COPIES:
			found.append("%d copies of %s" % [copies[id], id])
	return found
