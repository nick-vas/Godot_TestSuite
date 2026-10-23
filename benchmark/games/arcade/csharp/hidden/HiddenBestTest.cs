namespace OrbitPatrol.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the prototype's add-feature: the best score survives Reset().</summary>
[TestSuite]
public class HiddenBestTest
{
    [TestCase]
    public void Hidden_best_survives_reset()
    {
        var score = new Score();
        score.Hit(100);
        score.Hit(100);
        score.Reset();
        AssertThat(score.Points).IsEqual(0);
        AssertThat(score.Combo).IsEqual(0);
        AssertThat(score.Best).IsEqual(200);
    }

    [TestCase]
    public void Hidden_best_keeps_the_highest_game()
    {
        var score = new Score();
        score.Hit(300);
        score.Reset();
        score.Hit(100);
        AssertThat(score.Best).IsEqual(300);
        score.Hit(100);
        score.Hit(100);
        AssertThat(score.Best).IsEqual(300);
        score.Hit(100);
        AssertThat(score.Best).IsEqual(400);
    }
}
