namespace OrbitPatrol.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

[TestSuite]
public class ScoreBestTest
{
    [TestCase]
    public void Best_follows_the_points()
    {
        var score = new Score();
        score.Hit(100);
        score.Hit(100);
        AssertThat(score.Best).IsEqual(200);
    }
}
