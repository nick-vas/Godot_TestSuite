namespace OrbitPatrol.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

[TestSuite]
public class ScoreTest
{
    [TestCase]
    public void Fifth_hit_in_a_row_doubles_the_points()
    {
        var score = new Score();
        for (int i = 0; i < 4; i++)
            AssertThat(score.Hit(100)).IsEqual(100);
        AssertThat(score.Hit(100)).IsEqual(200);
    }

    [TestCase]
    public void Miss_resets_the_combo()
    {
        var score = new Score();
        for (int i = 0; i < 4; i++)
            score.Hit(100);
        score.Miss();
        AssertThat(score.Combo).IsEqual(0);
        AssertThat(score.Hit(100)).IsEqual(100);
    }

    [TestCase]
    public void Points_add_up_over_a_long_combo()
    {
        var score = new Score();
        for (int i = 0; i < 10; i++)
            score.Hit(10);
        // Hits 1-4 at x1, 5-9 at x2, the tenth at x3.
        AssertThat(score.Points).IsEqual(40 + 100 + 30);
    }
}
