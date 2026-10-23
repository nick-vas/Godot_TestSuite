extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus and cards included.


func after_each():
	TranslationServer.set_locale("en")


func test_hidden_french_is_loaded():
	assert_has(Array(TranslationServer.get_loaded_locales()), "fr")


func test_hidden_menu_and_cards_are_translated():
	for key in ["MENU_START", "CARD_FLARE", "RIVAL_5"]:
		TranslationServer.set_locale("en")
		var english := TranslationServer.translate(key)
		TranslationServer.set_locale("fr")
		var french := TranslationServer.translate(key)
		assert_ne(french, key, key)
		assert_ne(french, english, key)
