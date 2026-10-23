extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus included.


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


func test_hidden_level_five_has_the_boss():
	var waves := Waves.from_files()
	assert_true(waves.level_count() >= 5)
	assert_false(waves.boss(5).is_empty())
