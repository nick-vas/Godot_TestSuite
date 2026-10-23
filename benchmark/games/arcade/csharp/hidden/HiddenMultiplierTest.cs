namespace OrbitPatrol.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the prototype's fix-bug: the fifth hit in a row doubles, the tenth triples.</summary>
[TestSuite]
public class HiddenMultiplierTest
{
    [TestCase]
    public void Hidden_fifth_hit_doubles()
    {
        var score = new Score();
        for (int i = 0; i < 4; i++)
            score.Hit(10);
        AssertThat(score.Hit(10)).IsEqual(20);
    }

    [TestCase]
    public void Hidden_tenth_hit_triples()
    {
        var score = new Score();
        for (int i = 0; i < 9; i++)
            score.Hit(10);
        AssertThat(score.Hit(10)).IsEqual(30);
    }
}
