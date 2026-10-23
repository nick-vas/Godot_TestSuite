using Example.Core.Narrative;
using Xunit;

namespace Example.Core.Tests;

public sealed class ResponseRulesTests
{
    static Rule Rule(Symbols s, string name, string concept, string? who, string criteria, params string[] lines) =>
        new(name, concept, who, criteria.Length == 0 ? [] : criteria.Split(';').Select(c => Criterion.Parse(c, s)).ToList(), lines);

    [Fact]
    public void TheMostSpecificRuleWins()
    {
        // Ruskin's example: "oh look a zombie" against "a zombie is on the merry-go-round next to the ice cream machine".
        var s = new Symbols();
        var system = new ResponseSystem([
            Rule(s, "zombie", "SeeZombie", null, "", "Zombie!"),
            Rule(s, "ride", "SeeZombie", null, "near=merrygoround", "Zombie on the ride!"),
            Rule(s, "icecream", "SeeZombie", null, "near=merrygoround;beside=icecream", "Zombie on the ride by the ice cream!"),
        ], s);
        var nick = new Speaker("nick");
        var facts = new Dictionary<string, double> { ["near"] = s["merrygoround"], ["beside"] = s["icecream"] };
        Assert.Equal("icecream", system.Find(nick, "SeeZombie", facts, 0)!.Rule.Name);
        Assert.Equal("ride", system.Find(nick, "SeeZombie", new Dictionary<string, double> { ["near"] = s["merrygoround"] }, 0)!.Rule.Name);
        Assert.Equal("zombie", system.Find(nick, "SeeZombie", null, 0)!.Rule.Name);
        Assert.Null(system.Find(nick, "SeeTank", null, 0));
    }

    [Fact]
    public void ARuleNamingAFactTheQueryLacksRejects()
    {
        var s = new Symbols();
        var system = new ResponseSystem([Rule(s, "hurt", "Idle", null, "health<25", "I need a medkit.")], s);
        var ellis = new Speaker("ellis");
        Assert.Null(system.Find(ellis, "Idle", null, 0));
        ellis.Facts["health"] = 24;
        Assert.NotNull(system.Find(ellis, "Idle", null, 0));
        ellis.Facts["health"] = 25;   // strict: 25 is not below 25
        Assert.Null(system.Find(ellis, "Idle", null, 0));
    }

    [Fact]
    public void ASpeakersOwnRuleBeatsAGeneralOneAndOthersFallBackToIt()
    {
        var s = new Symbols();
        var system = new ResponseSystem([
            Rule(s, "general", "Reload", null, "", "Reloading!"),
            Rule(s, "coach", "Reload", "coach", "", "Hold on, reloading!"),
        ], s);
        Assert.Equal("coach", system.Find(new Speaker("coach"), "Reload", null, 0)!.Rule.Name);
        Assert.Equal("general", system.Find(new Speaker("rochelle"), "Reload", null, 0)!.Rule.Name);
    }

    [Fact]
    public void TiesAreDrawnAtRandomAndTheSameSeedDrawsTheSame()
    {
        var s = new Symbols();
        Rule[] rules = [Rule(s, "a", "Greet", null, "", "Hi."), Rule(s, "b", "Greet", null, "", "Hey."), Rule(s, "c", "Greet", null, "", "Yo.", "Yo!")];
        var seen = new HashSet<string>();
        for (var seed = 0; seed < 60; seed++)
        {
            var first = new ResponseSystem(rules, s, seed).Find(new Speaker("x"), "Greet", null, 0)!;
            var again = new ResponseSystem(rules, s, seed).Find(new Speaker("x"), "Greet", null, 0)!;
            Assert.Equal(first.Line, again.Line);
            seen.Add(first.Line);
        }
        Assert.Equal(4, seen.Count);   // every rule, and both takes of the third
    }

    [Fact]
    public void RememberedFactsFeedLaterQueriesAndCanExpire()
    {
        // "Nick is speaking for the next few seconds": a running gag that must not repeat too close together.
        var s = new Symbols();
        var gag = Rule(s, "gag", "Idle", "nick", "!gag_cooldown", "Not this again.") with
        {
            Remembers = [new Remember("gag_cooldown", 1, ForSeconds: 30), new Remember("gag_told", 1, World: true)],
        };
        var system = new ResponseSystem([gag], s);
        var nick = new Speaker("nick");
        var match = system.Find(nick, "Idle", null, 0)!;
        system.Played(match, now: 0);
        Assert.Null(system.Find(nick, "Idle", null, 10));
        Assert.NotNull(system.Find(nick, "Idle", null, 31));
        Assert.Equal(1, system.Query(new Speaker("ellis"), null, 100)["gag_told"]);   // the world's memory is everyone's
        var notYet = Criterion.Parse("!gag_told", s);
        Assert.True(notYet.Test(new Dictionary<string, double>()));
        Assert.True(notYet.Test(new Dictionary<string, double> { ["gag_told"] = 0 }));
        Assert.False(notYet.Test(new Dictionary<string, double> { ["gag_told"] = 1 }));
    }

    [Fact]
    public void AOnceRuleIsSpentAfterPlaying()
    {
        var s = new Symbols();
        var system = new ResponseSystem([
            Rule(s, "first", "SeeTank", null, "map=hospital", "Tank!") with { Once = true },
            Rule(s, "again", "SeeTank", null, "", "Another one?"),
        ], s);
        var bill = new Speaker("bill");
        var hospital = new Dictionary<string, double> { ["map"] = s["hospital"] };
        var first = system.Find(bill, "SeeTank", hospital, 0)!;
        Assert.Equal("first", first.Rule.Name);
        system.Played(first, 0);
        for (var i = 0; i < 10; i++) Assert.Equal("again", system.Find(bill, "SeeTank", hospital, 0)!.Rule.Name);   // no "said it already" fact needed
    }

    [Fact]
    public void AFollowUpIsLookedUpWhenTheLineEndsSoAConversationStopsWhenItsSituationEnds()
    {
        var s = new Symbols();
        var system = new ResponseSystem([
            Rule(s, "ask", "Idle", "nick", "danger=false", "Anyone got a plan?") with { Then = new FollowUp("ellis", "AnswerPlan") },
            Rule(s, "answer", "AnswerPlan", "ellis", "danger=false", "My buddy Keith had a plan once."),
        ], s);
        var nick = new Speaker("nick");
        var ellis = new Speaker("ellis");
        var calm = new Dictionary<string, double> { ["danger"] = 0 };
        var then = system.Played(system.Find(nick, "Idle", calm, 0)!, 0)!.Value;
        Assert.Equal(new FollowUp("ellis", "AnswerPlan"), then);
        Assert.NotNull(system.Find(ellis, then.Concept, calm, 3));
        Assert.Null(system.Find(ellis, then.Concept, new Dictionary<string, double> { ["danger"] = 1 }, 3));   // a horde arrived mid-line
    }

    [Fact]
    public void AQuestionToEveryoneInEarshotGetsTheBestReply()
    {
        // Rochelle has nothing (score 0), Ellis a generic line, Coach a specific one.
        var s = new Symbols();
        var system = new ResponseSystem([
            Rule(s, "generic", "SeeWitch", "ellis", "", "Uh oh."),
            Rule(s, "specific", "SeeWitch", "coach", "lights=off", "Lights off, and don't startle her."),
        ], s);
        var listeners = new[] { new Speaker("rochelle"), new Speaker("ellis"), new Speaker("coach") };
        Assert.Equal("coach", system.Ask(listeners, "SeeWitch", new Dictionary<string, double> { ["lights"] = s["off"] }, 0)!.Speaker.Name);
        Assert.Equal("ellis", system.Ask(listeners, "SeeWitch", null, 0)!.Speaker.Name);
    }

    [Fact]
    public void TheEventsFactsComeBeforeTheSpeakersAndTheSpeakersBeforeTheWorlds()
    {
        var s = new Symbols();
        var system = new ResponseSystem([], s);
        var zoey = new Speaker("zoey");
        zoey.Facts["weapon"] = s["pistol"];
        zoey.Memory.Set("seen_tank", 1, 0);
        system.World.Set("seen_tank", 0, 0);
        system.World.Set("map", s["hospital"], 0);
        var q = system.Query(zoey, new Dictionary<string, double> { ["weapon"] = s["shotgun"] }, 1);
        Assert.Equal(s["shotgun"], q["weapon"]);
        Assert.Equal(1, q["seen_tank"]);
        Assert.Equal(s["hospital"], q["map"]);
    }

    [Theory]
    [InlineData("health<25", 24.999, true)]
    [InlineData("health<25", 25, false)]
    [InlineData("health<=25", 25, true)]
    [InlineData("health>25", 25, false)]
    [InlineData("health>=25", 25, true)]
    [InlineData("health=25", 25, true)]
    [InlineData("health=25", 25.5, false)]
    public void CriteriaParseToIntervals(string text, double value, bool passes)
    {
        var c = Criterion.Parse(text, new Symbols());
        Assert.Equal(passes, c.Test(new Dictionary<string, double> { [c.Key] = value }));
    }

    [Fact]
    public void TextAndBooleansBecomeNumbersAndBadCriteriaAreRefused()
    {
        var s = new Symbols();
        Assert.Equal(new Criterion("weapon", s["shotgun"], s["shotgun"]), Criterion.Parse("weapon = shotgun", s));
        Assert.Equal(new Criterion("alone", 1, 1), Criterion.Parse("alone=true", s));
        Assert.NotEqual(s["shotgun"], s["pistol"]);
        Assert.ThrowsAny<FormatException>(() => Criterion.Parse("health<lots", s));
        Assert.ThrowsAny<FormatException>(() => Criterion.Parse("health", s));
        Assert.ThrowsAny<FormatException>(() => Criterion.Parse("a=1;b=2", s));   // one criterion; ParseAll reads a list
        Assert.Throws<ArgumentException>(() => new ResponseSystem([new Rule("empty", "Idle", null, [], [])], s));
    }
}
