extends GutTest
## Movement: running and the jump, a tick at a time at 60 ticks a second, on a flat floor at height 0.

const TICK := 1.0 / 60.0


func test_running_reaches_full_speed():
	var movement := Movement.new()
	movement.on_floor = true
	for i in 30:
		movement.step(1.0, false, false, TICK)
	assert_almost_eq(movement.velocity.x, Movement.RUN_SPEED, 0.001)


func test_a_jump_from_the_floor_rises():
	var movement := Movement.new()
	movement.on_floor = true
	movement.step(0.0, true, true, TICK)
	assert_true(movement.jumped)
	assert_gt(movement.motion.y, 0.0)


func test_a_full_jump_reaches_its_designed_height():
	var movement := Movement.new()
	movement.on_floor = true
	var y := 0.0
	var top := 0.0
	for i in 60:
		movement.step(0.0, i == 0, true, TICK)
		y += movement.motion.y * TICK
		top = maxf(top, y)
		movement.touched(y <= 0.0, false, false)
		y = maxf(y, 0.0)
	var designed := Movement.JUMP_VELOCITY * Movement.JUMP_VELOCITY / (2.0 * Movement.GRAVITY)
	assert_almost_eq(top, designed, 0.02)
