extends GutTest
## Hidden acceptance for the alpha milestone: six levels load, each solvable in exactly its par.


func test_hidden_six_levels_each_solvable_in_its_par():
	var levels := Levels.from_file()
	assert_gte(levels.level_count(), 6)
	var solver := Solver.new()
	for id in range(1, 7):
		assert_true(levels.has_level(id), "level %d" % id)
		assert_eq(solver.min_moves(levels.board(id)), levels.par(id), "level %d" % id)


func test_hidden_the_save_keeps_solved_levels():
	var path := "user://test_hidden_six_levels.json"
	var store := SaveStore.new(path)
	var data := store.read()
	data.solved["1"] = 3
	data.solved["2"] = 6
	assert_true(store.write(data))
	var back := SaveStore.new(path).read()
	assert_eq(int(back.solved["2"]), 6)
	DirAccess.remove_absolute(path)
