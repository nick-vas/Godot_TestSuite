namespace GlowmossRidge.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LaunchOptions: the flags bot runs and tests pass after "--".</summary>
[TestSuite]
public class LaunchOptionsTest
{
    [TestCase]
    public void Every_flag_is_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--autoplay", "--seed=7", "--no-save", "--level=3" });
        AssertThat(options.Autoplay).IsTrue();
        AssertThat(options.RunSeed).IsEqual(7UL);
        AssertThat(options.NoSave).IsTrue();
        AssertThat(options.Level).IsEqual(3);
    }

    [TestCase]
    public void No_flags_is_a_normal_game()
    {
        LaunchOptions options = LaunchOptions.Parse(System.Array.Empty<string>());
        AssertThat(options.Autoplay).IsFalse();
        AssertThat(options.NoSave).IsFalse();
        AssertThat(options.Level).IsEqual(1);
    }

    [TestCase]
    public void A_level_below_one_starts_at_one()
    {
        AssertThat(LaunchOptions.Parse(new[] { "--level=0" }).Level).IsEqual(1);
    }
}
