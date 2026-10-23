class_name Score
extends RefCounted
## Combo scoring, kept engine-light so it is easy to unit test with GUT.

var points := 0
var combo := 0
var best := 0

func hit(value: int) -> int:
	combo += 1
	var gained := value * (1 + combo / 5)
	points += gained
	best = maxi(best, points)
	return gained

func miss() -> void:
	combo = 0

func reset() -> void:
	points = 0
	combo = 0
