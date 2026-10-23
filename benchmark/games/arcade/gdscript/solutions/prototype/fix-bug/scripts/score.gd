class_name Score
extends RefCounted
## Points and the combo multiplier, kept free of the engine so the tests need no scene.

signal changed

var points := 0
var combo := 0


## A destroyed enemy worth value: every fifth hit in a row raises the multiplier by one.
func hit(value: int) -> int:
	combo += 1
	var gained := value * (1 + combo / 5)
	points += gained
	changed.emit()
	return gained


## A shot left the screen, or the ship was hit: the combo starts again.
func miss() -> void:
	combo = 0


## A new game.
func reset() -> void:
	points = 0
	combo = 0
	changed.emit()
