extends GutTest
## Movement's forgiveness and its tick rate: coyote time, the jump buffer, one press per jump, the short hop, and a jump
## that peaks at the same height however many ticks a second the physics runs.

const TICK := 1.0 / 60.0


## Runs a body on a floor at height 0 (or none, with no_floor_after: the ledge ends after that many ticks). presses:
## the ticks a press starts on; held_for: ticks the button stays down after each press. Returns the heights per tick.
func _run(ticks: int, presses: Array, held_for := 1000, rate := 60, no_floor_after := -1, start_y := 0.0) -> Array[float]:
	var movement := Movement.new()
	var dt := 1.0 / rate
	var y := start_y
	movement.on_floor = y <= 0.0
	var heights: Array[float] = []
	var last_press := -100000
	for i in ticks:
		if i in presses:
			last_press = i
		movement.step(0.0, i in presses, i - last_press < held_for, dt)
		y += movement.motion.y * dt
		var has_floor := no_floor_after < 0 or i < no_floor_after
		var landed := has_floor and y <= 0.0
		if landed:
			y = 0.0
		movement.touched(landed, false, false)
		heights.append(y)
	return heights


func _top(heights: Array[float]) -> float:
	var top := -INF
	for h in heights:
		top = maxf(top, h)
	return top


func test_a_jump_just_after_running_off_a_ledge_still_jumps():
	# The floor is gone after tick 10; the press comes 3 ticks (0.05 s) later.
	assert_gt(_top(_run(60, [13], 1000, 60, 10)), 1.0)


func test_a_jump_long_after_leaving_the_ledge_does_nothing():
	# 12 ticks (0.2 s) after the ledge ended: too late.
	assert_lt(_top(_run(60, [22], 1000, 60, 10)), 0.01)


func test_a_press_just_before_landing_jumps_on_landing():
	# Falling from 3 m lands after about 27 ticks; a press 6 ticks (0.1 s) earlier jumps on landing.
	var heights := _run(90, [21], 1000, 60, -1, 3.0)
	assert_gt(_top(heights.slice(30)), 1.0, "it jumped again after landing")


func test_a_press_long_before_landing_is_forgotten():
	var heights := _run(90, [5], 1000, 60, -1, 3.0)
	assert_lt(_top(heights.slice(30)), 0.01)


func test_one_press_is_one_jump():
	# A second press right after the jump must not jump again in mid-air.
	var once := _top(_run(60, [0]))
	var twice := _top(_run(60, [0, 2]))
	assert_almost_eq(twice, once, 0.01)


func test_letting_go_early_is_a_short_hop():
	var full := _top(_run(60, [0]))
	var hop := _top(_run(60, [0], 4))
	assert_lt(hop, full * 0.7)


func test_the_jump_peaks_at_the_same_height_at_any_tick_rate():
	var at_60 := _top(_run(60, [0], 1000, 60))
	assert_almost_eq(_top(_run(30, [0], 1000, 30)), at_60, 0.03)
	assert_almost_eq(_top(_run(120, [0], 1000, 120)), at_60, 0.03)
