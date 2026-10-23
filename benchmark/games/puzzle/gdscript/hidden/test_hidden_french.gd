extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus included, and has eight levels.


func after_each():
	TranslationServer.set_locale("en")


func test_hidden_french_is_loaded():
	assert_has(Array(TranslationServer.get_loaded_locales()), "fr")


func test_hidden_menu_is_translated():
	TranslationServer.set_locale("en")
	var english := TranslationServer.translate("MENU_START")
	TranslationServer.set_locale("fr")
	var french := TranslationServer.translate("MENU_START")
	assert_ne(french, "MENU_START")
	assert_ne(french, english)


func test_hidden_eight_levels_each_solvable_in_its_par():
	var levels := Levels.from_file()
	assert_gte(levels.level_count(), 8)
	var solver := Solver.new()
	for id in range(1, 9):
		assert_eq(solver.min_moves(levels.board(id)), levels.par(id), "level %d" % id)
