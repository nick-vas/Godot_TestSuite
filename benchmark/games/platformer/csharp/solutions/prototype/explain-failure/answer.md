The failing test is `Each_moss_is_worth_ten_points` in `test/RulesTest.cs`, line 35
(`AssertThat(rules.Score).IsEqual(30);`). It expected a score of 30 and got 40; the next line would fail the same way
(3 tufts expected, 4 counted).

The test is wrong, not the game: its loop gathers glowmoss four times (`for (int i = 0; i < 4; i++)`), and each tuft is
worth `Rules.MossPoints`, 10, so 40 is right for four. Rules scores as it should. The loop should run three times, which
is what the expected 30 and 3 describe.
