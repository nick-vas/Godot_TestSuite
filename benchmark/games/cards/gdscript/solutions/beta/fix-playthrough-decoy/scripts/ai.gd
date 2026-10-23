class_name Ai
extends RefCounted
## The utility AI that plays a keeper. In its Main phase it scores every card the rules let it play: how well the card
## spends the turn's kindling, times what the card is worth now (each from 0 to 1, so a worth of 0 vetoes a card). It
## plays the best, or ends its Main phase when nothing beats PASS_SCORE. Rivals differ only in their weights: aggression
## raises attacks, caution raises mending and guard. last_scores keeps the numbers behind the last choice, so "why did it
## do that" is answered from the log.

const PASS_SCORE := 0.1
const WINNING_WEIGHT := 2.0

var aggression := 1.0
var caution := 1.0
## Card id -> score, for the cards the last choice weighed.
var last_scores := {}


func _init(aggression_weight := 1.0, caution_weight := 1.0) -> void:
	aggression = aggression_weight
	caution = caution_weight


## The index in the hand of the card to play, or -1 to end the Main phase.
func choose(duel: Duel, seat: int) -> int:
	last_scores.clear()
	var best := -1
	var best_score := PASS_SCORE
	var hand := duel.keepers[seat].hand
	for i in hand.size():
		if duel.cards.card(hand[i]).cost > duel.keepers[seat].kindling:
			continue
		var value := score(duel, seat, i)
		last_scores[hand[i]] = value
		if value > best_score:
			best = i
			best_score = value
	return best


## The utility of playing a card of the hand now.
func score(duel: Duel, seat: int, index: int) -> float:
	var me := duel.keepers[seat]
	var card := duel.cards.card(me.hand[index])
	# Spending: a card that uses more of the turn's kindling wastes less of it.
	var spend := 0.5 + 0.5 * float(card.cost) / float(maxi(me.kindling, 1))
	var value := spend * worth(duel, seat, card)
	# Weight groups: a play that wins the duel now outranks every other.
	if card.effect == "bolt" and duel.keepers[1 - seat].light <= card.amount:
		value *= WINNING_WEIGHT
	return value


## What a card is worth to a keeper in this position, from 0 (never) to 1 (now).
func worth(duel: Duel, seat: int, card: Dictionary) -> float:
	var me := duel.keepers[seat]
	var foe := duel.keepers[1 - seat]
	if card.kind == Cards.WISP:
		var value := clampf((card.power * aggression + card.guard * caution * 0.5) / 8.0, 0.0, 1.0)
		# A wisp the strongest wisp across would put out at once is worth less.
		var threat := duel.strongest_lane(1 - seat)
		if threat >= 0 and foe.row[threat].power >= card.guard:
			value *= 0.6
		return value
	match card.effect:
		"bolt":
			if foe.light <= card.amount:
				return 1.0
			return clampf(0.3 * aggression, 0.0, 1.0)
		"mend":
			var missing := me.max_light - me.light
			if missing <= 0:
				return 0.0
			var danger := 1.0 - float(me.light) / float(me.max_light)
			return clampf(float(mini(missing, card.amount)) / float(card.amount) * (0.2 + 0.8 * danger) * caution, 0.0, 1.0)
		"draw":
			if me.deck.size() < card.amount or me.hand.size() - 1 + card.amount > Duel.HAND_MAX:
				return 0.0
			return 0.45
		"douse":
			var lane := duel.strongest_lane(1 - seat)
			if lane < 0:
				return 0.0
			var target: Dictionary = foe.row[lane]
			var kill := 1.0 if target.guard <= card.amount else 0.5
			return clampf(target.power / 5.0 * kill * aggression, 0.0, 1.0)
		"rekindle":
			return 0.4 if duel.last_fallen(seat) >= 0 else 0.0
	return 0.0


## The last choice's scores as one log line, best first: "flare 0.62, reed_hound 0.41, pass 0.10".
func describe() -> String:
	var parts := PackedStringArray()
	var ids := last_scores.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return last_scores[a] > last_scores[b] or (last_scores[a] == last_scores[b] and a < b))
	for id: String in ids:
		parts.append("%s %.2f" % [id, last_scores[id]])
	parts.append("pass %.2f" % PASS_SCORE)
	return ", ".join(parts)


## Plays a duel to its end with an AI in each seat, without the game: for tests and balance checks. Returns the winner,
## or -1 when it did not end within max_steps. A play the rules refuse ends that Main phase.
static func play_out(duel: Duel, ais: Array, max_steps := 5000) -> int:
	for step in max_steps:
		if duel.phase == Duel.Phase.OVER:
			return duel.winner
		if duel.phase != Duel.Phase.MAIN:
			duel.advance()
			continue
		var index: int = ais[duel.active].choose(duel, duel.active)
		if index < 0 or not duel.play(duel.active, index):
			duel.end_main()
	return -1 if duel.phase != Duel.Phase.OVER else duel.winner
