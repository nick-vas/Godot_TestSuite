extends GutTest
## Hidden check for the beta's fix-playthrough: the boss is beatable but not trivial.


func test_hidden_boss_hp_is_fair():
	var boss := Waves.from_files().boss(5)
	assert_false(boss.is_empty(), "level 5 still has a boss")
	var hp := int(boss.get("hp", 0))
	assert_between(hp, 30, 80, "the boss's hp")


func test_hidden_other_enemies_unchanged():
	var waves := Waves.from_files()
	assert_eq(int(waves.enemy("grunt").hp), 1)
	assert_eq(int(waves.enemy("tank").hp), 4)
