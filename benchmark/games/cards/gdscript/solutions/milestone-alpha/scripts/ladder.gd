class_name Ladder
extends RefCounted
## What a save says about the rivals: each one's wins and losses, and which are open. Rival 1 is always open; the next
## opens once the one before it is beaten.


## Records a finished duel against a rival.
static func record(save: Dictionary, rival: int, won: bool) -> void:
	var record: Dictionary = save.record
	var key := str(rival)
	var entry: Dictionary = record.get(key, {"wins": 0, "losses": 0})
	if won:
		entry.wins = int(entry.wins) + 1
	else:
		entry.losses = int(entry.losses) + 1
	record[key] = entry


static func wins(save: Dictionary, rival: int) -> int:
	return int(save.record.get(str(rival), {}).get("wins", 0))


static func losses(save: Dictionary, rival: int) -> int:
	return int(save.record.get(str(rival), {}).get("losses", 0))


static func is_beaten(save: Dictionary, rival: int) -> bool:
	return wins(save, rival) > 0


static func is_unlocked(save: Dictionary, rival: int) -> bool:
	return rival <= 1 or is_beaten(save, rival - 1)


## Every win against every rival, for the victory screen.
static func total_wins(save: Dictionary) -> int:
	var total := 0
	for key: String in save.record:
		total += int(save.record[key].get("wins", 0))
	return total
