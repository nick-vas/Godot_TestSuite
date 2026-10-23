extends GutTest
## Hidden check for the prototype's fix-bug: a jump pressed just after running off a ledge still jumps (coyote time),
## a late one does not, and one press is still one jump.

const TICK := 1.0 / 60.0


## The highest point of a body that stands on a ledge for the first ledge_ticks ticks, then has no floor, and presses
## jump on the given ticks (held from then on).
func _top(ledge_ticks: int, presses: Array) -> float:
	var movement := Movement.new()
	movement.on_floor = true
	var y := 0.0
	var top := 0.0
	var held := false
	for i in 90:
		held = held or i in presses
		movement.step(1.0, i in presses, held, TICK)
		y += movement.motion.y * TICK
		var landed := i < ledge_ticks and y <= 0.0
		if landed:
			y = 0.0
		movement.touched(landed, false, false)
		top = maxf(top, y)
	return top


func test_hidden_a_press_0_05_s_after_the_ledge_jumps():
	assert_gt(_top(10, [13]), 1.0)


func test_hidden_a_press_0_08_s_after_the_ledge_jumps():
	assert_gt(_top(10, [15]), 1.0)


func test_hidden_a_press_0_2_s_after_the_ledge_does_not():
	assert_lt(_top(10, [22]), 0.01)


func test_hidden_a_jump_from_the_floor_still_works():
	assert_gt(_top(1000, [0]), 1.5)


func test_hidden_no_second_jump_in_the_air():
	assert_almost_eq(_top(1000, [0, 3]), _top(1000, [0]), 0.01)
