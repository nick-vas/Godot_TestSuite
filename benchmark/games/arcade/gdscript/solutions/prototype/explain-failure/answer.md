The failing test is `test_one_hit_costs_one_life` in `test/unit/test_rules.gd`, line 13
(`assert_eq(rules.lives, 2)`). It expected 2 lives and got 3.

The test is wrong, not the game: it starts the ship with `Rules.new(4)`, four lives, so one hit leaves 3. Rules
takes one life per hit as it should; a new game has 3 lives (`START_LIVES`), and from 3 one hit leaves the 2 the test
expects. The test's setup should be `Rules.new(3)`.
