extends GutTest
# Three tests for tests/Test-Flaky.ps1: one that fails only on the first run after the self-test removes its marker file
# (an intermittent failure it can reproduce), one that always fails, and one that always passes.


func test_sometimes() -> void:
	var marker := OS.get_environment("FLAKY_FIXTURE_MARKER")
	if marker.is_empty():
		pass_test("no marker file named: nothing to be flaky about")
		return
	var first_run := not FileAccess.file_exists(marker)
	if first_run:
		var file := FileAccess.open(marker, FileAccess.WRITE)
		file.store_string("ran once")
		file.close()
	assert_false(first_run, "the first run fails, as an intermittent failure would")


func test_always() -> void:
	assert_eq(1 + 1, 3, "this test is broken for good")


func test_fine() -> void:
	assert_true(true)
