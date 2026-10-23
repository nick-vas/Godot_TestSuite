using Example.Core.Economy;
using Xunit;
using Xunit.Abstractions;

namespace Example.Core.Tests;

/// <summary>Sources against sinks over 10, 100 and 1000 hours: a stable economy, inflation, and a dead one.</summary>
public sealed class EconomySimTests
{
    readonly ITestOutputHelper _output;
    public EconomySimTests(ITestOutputHelper output) => _output = output;

    // Gold for an hour of play: 1,000 in, 950 out, so a player saves about 50 an hour for something big.
    static readonly Flow[] Gold =
    {
        new("quest rewards", "gold", 600, Spread: 0.3),
        new("loot sold", "gold", 400, Spread: 0.5),
        new("repairs", "gold", -450, Spread: 0.2),
        new("consumables", "gold", -350, Spread: 0.3),
        new("upgrades", "gold", -150, Spread: 0.5),
    };

    [Theory]
    [InlineData(10)]
    [InlineData(100)]
    [InlineData(1000)]
    public void ABalancedEconomyStaysInsideItsBand(int hours)
    {
        var sim = new EconomySim(Gold);
        Assert.Equal(50, sim.PlannedNetPerHour["gold"], 6);
        Assert.Empty(sim.WithoutSink);
        var gold = sim.Simulate(hours, seed: 7)["gold"];
        _output.WriteLine($"{hours} h: net {gold.NetPerHour:F1} gold an hour, {gold.BalanceByHour[^1]:F0} at the end, {gold.ShortHours} hours short");
        Assert.InRange(gold.NetPerHour, 0, 150);         // saving, slowly: neither inflation nor a drain
        Assert.Equal(0, gold.ShortHours);
        Assert.Equal(hours, gold.BalanceByHour.Count);
    }

    [Fact]
    public void ASourceWithNoSinkIsFlaggedAndOnlyPilesUp()
    {
        var sim = new EconomySim(Gold.Append(new Flow("daily gems", "gems", 20)));
        Assert.Equal(new[] { "gems" }, sim.WithoutSink);
        var gems = sim.Simulate(1000, seed: 7)["gems"];
        Assert.Equal(20, gems.NetPerHour, 6);
        Assert.Equal(20_000, gems.BalanceByHour[^1], 6);
    }

    [Fact]
    public void SinksAboveSourcesShowAsHoursShortNotAsANegativeBalance()
    {
        var sim = new EconomySim(new Flow[] { new("quest rewards", "gold", 500, 0.3), new("repairs", "gold", -700, 0.2) });
        Assert.Equal(-200, sim.PlannedNetPerHour["gold"], 6);
        var gold = sim.Simulate(100, seed: 3)["gold"];
        _output.WriteLine($"dead economy: net {gold.NetPerHour:F1} an hour, short {gold.ShortHours} of 100 hours");
        Assert.All(gold.BalanceByHour, b => Assert.True(b >= 0));
        Assert.InRange(gold.NetPerHour, -1, 1);           // near zero, which alone would look healthy...
        Assert.True(gold.ShortHours > 90);                // ...but the player cannot pay for repairs
    }

    [Fact]
    public void TheSameSeedGivesTheSameRun()
    {
        var sim = new EconomySim(Gold);
        Assert.Equal(sim.Simulate(100, seed: 11)["gold"].BalanceByHour, sim.Simulate(100, seed: 11)["gold"].BalanceByHour);
        Assert.NotEqual(sim.Simulate(100, seed: 11)["gold"].BalanceByHour, sim.Simulate(100, seed: 12)["gold"].BalanceByHour);
    }
}
