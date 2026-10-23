extends GutTest
## Hidden check for the beta's fix-playthrough: a held jump peaks at its designed height at 30, 60, 120 and 144 ticks a
## second, so raising the tick rate changes nothing a level depends on.


func _apex(rate: int) -> float:
	var movement := Movement.new()
	movement.on_floor = true
	var dt := 1.0 / rate
	var y := 0.0
	var top := 0.0
	for i in rate * 2:
		movement.step(0.0, i == 0, true, dt)
		y += movement.motion.y * dt
		var landed := y <= 0.0
		if landed:
			y = 0.0
		movement.touched(landed, false, false)
		top = maxf(top, y)
	return top


func test_hidden_the_jump_is_the_same_at_every_tick_rate():
	var designed := Movement.JUMP_VELOCITY * Movement.JUMP_VELOCITY / (2.0 * Movement.GRAVITY)
	for rate in [30, 60, 120, 144]:
		assert_almost_eq(_apex(rate), designed, 0.03, "%d ticks a second" % rate)


func test_hidden_the_jump_still_clears_the_steps():
	assert_true(_apex(120) > 1.6, "the climb's 1.2 m steps need more than 1.6 m")
	assert_true(_apex(120) < 2.2, "not trivial: no higher than designed")
