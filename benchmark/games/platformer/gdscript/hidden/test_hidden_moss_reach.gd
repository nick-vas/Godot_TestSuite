extends GutTest
## Hidden check for the beta's fix-bug: every tuft of glowmoss in Beacon Crest is within the climber's reach of the
## ground below it, none was removed, and none is merely excused from the placement check.


func test_hidden_all_glowmoss_of_level_five_is_within_reach():
	var level: Level = load(str(Levels.from_files().level(5).scene)).instantiate()
	add_child_autofree(level)
	assert_eq(level.moss.get_child_count(), 10, "Beacon Crest keeps its ten tufts")
	var boxes := level.platform_boxes()
	for tuft: Node3D in level.moss.get_children():
		assert_false(tuft.has_meta("placement_skip"), "%s is not excused from the check" % tuft.name)
		var ground := -INF
		for box in boxes:
			if box.position.x <= tuft.position.x and tuft.position.x <= box.end.x and box.end.y <= tuft.position.y:
				ground = maxf(ground, box.end.y)
		assert_true(tuft.position.y - ground <= Movement.REACH, "%s is %.2f m above the ground (reach %.2f)" % [tuft.name, tuft.position.y - ground, Movement.REACH])
