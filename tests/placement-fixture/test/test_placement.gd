# Every placed object in every level against the limits in the game's code. tests/Test-Placement.ps1 copies
# ci/godot/templates/placement_check.gd next to this file before it runs the fixture.
extends GutTest

const PlacementCheck := preload("res://test/placement_check.gd")
const Player := preload("res://player.gd")
const ZipLine := preload("res://zipline.gd")


func _new_check() -> PlacementCheck:
	var check := PlacementCheck.new()
	check.reach = Player.REACH
	check.zipline_max_angle = ZipLine.MAX_ANGLE_DEGREES
	return check


# The levels: one ai_point 2 m above the navmesh, one torch out of reach and one zip line through a crate.
func test_every_level() -> void:
	var check := _new_check()
	check.counts_file = "res://.godot/placement-counts.json"
	var findings: Array[String] = await check.check_scenes(self, PlacementCheck.scenes_in("res://levels"))
	gut.p(check.summary())
	assert_true(findings.is_empty(), check.report())


# The other rules, each broken once: a link to a navmesh island, a steep zip line, an exemption without a reason, a
# landmark that is a moving body. The one-way slide is never walked back, so it needs nothing ahead that way.
func test_rule_cases() -> void:
	var check := _new_check()
	var findings: Array[String] = await check.check_scenes(self, PlacementCheck.scenes_in("res://rule_cases"))
	gut.p(check.summary())
	assert_true(findings.is_empty(), check.report())


# Wayfinding: a drifting balloon, a tower seen from one stretch of the trail, and nothing ahead on the way back.
func test_wayfinding() -> void:
	var check := _new_check()
	var findings: Array[String] = await check.check_scenes(self, PlacementCheck.scenes_in("res://wayfinding"))
	gut.p(check.summary())
	assert_true(findings.is_empty(), check.report())
