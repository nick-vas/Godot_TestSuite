The failing test is `test_each_moss_is_worth_ten_points` in `test/unit/test_rules.gd`, line 23
(`assert_eq(rules.score, 30)`). It expected a score of 30 and got 40; the next line fails the same way (3 tufts
expected, 4 counted).

The test is wrong, not the game: its loop gathers glowmoss four times (`for i in 4:`), and each tuft is worth
`Rules.MOSS_POINTS`, 10, so 40 is right for four. Rules scores as it should. The loop should run three times, which
is what the expected 30 and 3 describe.
