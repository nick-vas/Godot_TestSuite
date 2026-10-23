The failing test is `A_slide_stops_before_the_wall` in `test/BoardTest.cs`, at line 16
(`AssertThat(board.Position.X).IsEqual(4)`): it expected the mote to stop at x = 4 and got x = 5.

The test is wrong, not the game. Its board is `{ "#######", "#S....#", "#######" }`: four ice tiles after the start, so the
wall is at x = 6 and a slide to the right correctly stops on the tile before it, x = 5. The expected 4 belongs to the
shorter corridor `"#S...#"`. Board's slide is right, and the other tests pass.
