namespace OrbitPatrol.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

[TestSuite]
public class ScoreBestTest
{
    [TestCase]
    public void Best_is_kept_across_reset()
    {
        var score = new Score();
        score.Hit(300);
        score.Reset();
        AssertThat(score.Points).IsEqual(0);
        AssertThat(score.Combo).IsEqual(0);
        AssertThat(score.Best).IsEqual(300);
    }

    [TestCase]
    public void Best_is_the_highest_game_not_the_last()
    {
        var score = new Score();
        score.Hit(500);
        score.Reset();
        score.Hit(100);
        AssertThat(score.Best).IsEqual(500);
    }

    [TestCase]
    public void Best_follows_a_better_game()
    {
        var score = new Score { Best = 150 };
        score.Hit(100);
        score.Hit(100);
        AssertThat(score.Best).IsEqual(200);
    }
}
