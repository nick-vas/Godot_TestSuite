The failing test is `One_hit_costs_one_life` in `test/RulesTest.cs`, at line 21:
`AssertThat(rules.Lives).IsEqual(2)`.

It expected 2 lives and got 3. The test starts the game with `new Rules(4)`, four lives, so one hit
leaves 3. The game is right: `Rules.ShipHit()` takes exactly one life. The test is wrong: it should
start from 3 lives (`new Rules(3)`, the game's default) or expect 3.
