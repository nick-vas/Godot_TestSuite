extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus included, and has five levels.


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


func test_hidden_five_levels():
	assert_true(Levels.from_files().count() >= 5)
