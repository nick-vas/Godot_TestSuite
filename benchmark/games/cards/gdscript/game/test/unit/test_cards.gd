extends GutTest
## Cards: every card has what its kind needs.

var cards := Cards.from_file()


func test_every_card_has_what_its_kind_needs():
	assert_gt(cards.ids().size(), 0)
	for id in cards.ids():
		var card := cards.card(id)
		if card.kind == Cards.WISP:
			assert_gt(card.guard, 0, "%s has a guard" % id)
			assert_eq(card.effect, "", "%s is a wisp with an effect" % id)
		else:
			assert_eq(card.kind, Cards.RITE, id)
			assert_has(Cards.EFFECTS, card.effect, "%s does something" % id)
			assert_gt(card.amount, 0, "%s has an amount" % id)


func test_every_card_name_is_translated():
	TranslationServer.set_locale("en")
	for id in cards.ids():
		var key: String = cards.card(id).name
		assert_ne(tr(key), key, id)
