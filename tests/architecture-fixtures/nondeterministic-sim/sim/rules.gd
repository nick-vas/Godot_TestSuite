extends RefCounted
# Lockstep rules in GDScript.

var rng := RandomNumberGenerator.new()

func step(angle: float) -> float:
	var a := sin(angle)
	var b := randf()
	var c := rng.randf()
	var t := Time.get_ticks_msec()
	return a + b + c + t + sqrt(angle)
