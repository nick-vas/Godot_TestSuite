using System.Text.Json;
using Breakout.Core.Narrative;
using Xunit;

namespace Breakout.Core.Tests;

public sealed class ResponseTableTests
{
    static string Copied(string name) => Path.Combine(AppContext.BaseDirectory, name);

    /// <summary>
    /// The grammar's cases, also read by tests/Test-Data.ps1 against the data runner's parser: both must give the same
    /// criteria, and the same message (column included) for every error.
    /// </summary>
    public static TheoryData<string> GrammarCases()
    {
        var data = new TheoryData<string>();
        using var doc = JsonDocument.Parse(File.ReadAllText(Copied("criteria-examples.json")));
        foreach (var c in doc.RootElement.EnumerateArray()) data.Add(c.GetRawText());
        return data;
    }

    [Theory]
    [MemberData(nameof(GrammarCases))]
    public void CriteriaParseAsTheSharedExamplesSay(string example)
    {
        using var doc = JsonDocument.Parse(example);
        var c = doc.RootElement;
        var text = c.GetProperty("text").GetString()!;
        if (c.TryGetProperty("error", out var error))
        {
            var e = Assert.Throws<CriteriaSyntaxException>(() => CriteriaSyntax.Parse(text));
            Assert.Equal(error.GetString(), e.Message);
            return;
        }
        var parsed = CriteriaSyntax.Parse(text);
        var expected = c.GetProperty("criteria").EnumerateArray().ToList();
        Assert.Equal(expected.Count, parsed.Count);
        for (var i = 0; i < parsed.Count; i++)
        {
            var want = expected[i];
            Assert.Equal(want.GetProperty("key").GetString(), parsed[i].Key);
            Assert.Equal(want.GetProperty("op").GetString(), parsed[i].Op);
            Assert.Equal(want.TryGetProperty("number", out var n) ? n.GetDouble() : null, parsed[i].Number);
            Assert.Equal(want.TryGetProperty("name", out var name) ? name.GetString() : null, parsed[i].Name);
        }
    }

    [Fact]
    public void TheGamesDialogueTableLoadsAndPlays()
    {
        var s = new Symbols();
        var rules = ResponseTable.Load(File.ReadAllText(Copied("barks.json")), s);
        Assert.InRange(rules.Count, 5, 8);
        var system = new ResponseSystem(rules, s, seed: 1);
        var ana = new Speaker("ana");
        var ben = new Speaker("ben");

        // A life lost with balls left: Ana speaks, then Ben answers if lives are still left when her line ends.
        var lost = system.Find(ana, "LifeLost", new Dictionary<string, double> { ["lives"] = 2 }, 0)!;
        Assert.Equal("ana_life_lost", lost.Rule.Name);
        var then = system.Played(lost, 0)!.Value;
        Assert.Equal(new FollowUp("ben", "ReplyLifeLost"), then);
        Assert.Equal("ben_reply_life_lost", system.Find(ben, then.Concept, new Dictionary<string, double> { ["lives"] = 2 }, 2)!.Rule.Name);
        Assert.Equal("ana_last_ball", system.Find(ana, "LifeLost", new Dictionary<string, double> { ["lives"] = 0 }, 0)!.Rule.Name);

        // The combo cheer remembers a cooldown for 20 s.
        var combo = new Dictionary<string, double> { ["combo"] = 6 };
        system.Played(system.Find(ana, "BrickBroken", combo, 0)!, 0);
        Assert.Null(system.Find(ana, "BrickBroken", combo, 10));
        Assert.NotNull(system.Find(ana, "BrickBroken", combo, 21));

        // The first wall is said once, by anyone, and the world remembers it; then the general line.
        var level1 = new Dictionary<string, double> { ["level"] = 1 };
        var first = system.Find(ben, "LevelCleared", level1, 0)!;
        Assert.Equal("first_wall", first.Rule.Name);
        system.Played(first, 0);
        Assert.Equal(1, system.Query(ana, null, 1)["cleared_once"]);
        Assert.Equal("next_wall", system.Find(ana, "LevelCleared", level1, 1)!.Rule.Name);
    }

    [Fact]
    public void EveryColumnMapsOntoTheRule()
    {
        var s = new Symbols();
        var rules = ResponseTable.Load("""
            { "nick_plan": { "who": "nick", "concept": "Idle", "criteria": "danger=false;!gag_cooldown",
                             "lines": ["Anyone got a plan?", { "text": "Plan, anyone?", "voice": "res://voice/nick_plan_2.ogg" }],
                             "then": { "who": "ellis", "concept": "AnswerPlan" },
                             "remember": [{ "fact": "gag_cooldown", "for": 30 }, { "fact": "mood", "value": "grumpy", "world": true }],
                             "once": true } }
            """, s);
        var rule = Assert.Single(rules);
        Assert.Equal("nick_plan", rule.Name);
        Assert.Equal("nick", rule.Who);
        Assert.Equal("Idle", rule.Concept);
        Assert.Equal([new Criterion("danger", 0, 0), new Criterion("gag_cooldown", 0, 0, MissingPasses: true)], rule.Criteria);
        Assert.Equal(["Anyone got a plan?", "Plan, anyone?"], rule.Lines);
        Assert.Null(rule.VoiceOf("Anyone got a plan?"));
        Assert.Equal("res://voice/nick_plan_2.ogg", rule.VoiceOf("Plan, anyone?"));
        Assert.Equal(new FollowUp("ellis", "AnswerPlan"), rule.Then);
        Assert.Equal([new Remember("gag_cooldown", 1, false, 30), new Remember("mood", s["grumpy"], true)], rule.Remembers);
        Assert.True(rule.Once);
        Assert.Equal(4, rule.Score);
    }

    [Fact]
    public void EveryBadRowIsReportedAtOnce()
    {
        var e = Assert.Throws<FormatException>(() => ResponseTable.Load("""
            [ { "id": "a", "concept": "Idle", "criteria": "health<lots", "lines": ["x"] },
              { "id": "b", "concept": "Idle", "lines": [] , "mood": 1 },
              { "concept": "Idle", "lines": ["y"], "then": { "who": "z" } } ]
            """, new Symbols()));
        Assert.Equal(string.Join("\n",
            "'a' criteria column 8: '<' needs a number, not 'lots'",
            "'b' has 'mood', which is not a column",
            "'b' has no lines",
            "row 3 has no id",
            "row 3 then needs a concept: { \"who\": ..., \"concept\": ... }"), e.Message);
        Assert.Single(ResponseTable.Load("""[ { "id": "b", "concept": "Idle", "lines": ["x"], "notes": "for the actor" } ]""", new Symbols(), ["notes"]));
    }
}
