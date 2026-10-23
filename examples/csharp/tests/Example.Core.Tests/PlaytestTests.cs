using System.Text.Json.Nodes;
using Example.Core.Telemetry;
using Xunit;

namespace Example.Core.Tests;

public sealed class PlaytestTests
{
    double _now;
    readonly TelemetryClient _client;
    readonly PlaytestTracker _tracker;

    public PlaytestTests()
    {
        _client = new TelemetryClient(new TelemetrySchema(PlaytestEvents.Definitions(new[] { "hub", "cave" })), "1.0.0");
        _client.SetConsent(Purpose.Analytics, Consent.Granted);
        _tracker = new PlaytestTracker(_client, () => _now);   // 4-unit cells, 120 s stall, 30 s stay, 8-unit radius, 10 s away
    }

    List<(string Name, JsonObject Fields)> Events() =>
        JsonNode.Parse(_client.Export())!["queued"]!.AsArray()
            .Select(e => (e!["event"]!.GetValue<string>(), e["fields"]!.AsObject())).ToList();

    List<JsonObject> Events(string name) => Events().Where(e => e.Name == name).Select(e => e.Fields).ToList();

    // Moves once a second until `until`, at a fixed place.
    void StayUntil(double until, double x, double y, double z = 0)
    {
        while (_now < until) { _now += 1; _tracker.Move(x, y, z); }
    }

    [Fact]
    public void NothingIsRecordedWithoutConsent()
    {
        var client = new TelemetryClient(new TelemetrySchema(PlaytestEvents.Definitions(new[] { "hub" })), "1.0.0");
        var tracker = new PlaytestTracker(client, () => _now);
        tracker.StartLevel("hub");
        for (_now = 0; _now < 300; _now++) tracker.Move(1, 1);
        tracker.Died(1);
        tracker.EndLevel(LevelResult.Finished);
        Assert.Equal(0, client.Queued);
    }

    [Fact]
    public void AStallIsSentWhenItEndsWithItsWholeLengthAtThePlaceItBegan()
    {
        _tracker.StartLevel("hub");
        _tracker.Move(1, 1);
        StayUntil(119, 1, 1);
        Assert.Empty(Events(PlaytestEvents.Stuck));   // 119 s without progress is not yet a stall
        StayUntil(120, 2, 3);                          // becomes one here, at (2, 3)
        StayUntil(200, 1, 1);
        Assert.Empty(Events(PlaytestEvents.Stuck));   // still stuck: sent when it ends, with its whole length
        _tracker.Progress();
        var stuck = Assert.Single(Events(PlaytestEvents.Stuck));
        Assert.Equal(200, stuck["seconds"]!.GetValue<double>());
        Assert.Equal(120, stuck["level_seconds"]!.GetValue<double>());
        Assert.Equal((2.0, 3.0, 0.0), (stuck["x"]!.GetValue<double>(), stuck["y"]!.GetValue<double>(), stuck["z"]!.GetValue<double>()));
        Assert.Equal("hub", stuck["level"]!.GetValue<string>());
    }

    [Fact]
    public void PacingBetweenKnownCellsIsStuckButNewGroundIsProgress()
    {
        _tracker.StartLevel("hub");
        // Back and forth between two cells for 130 s: the same area, no progress.
        for (int i = 0; i < 130; i++) { _now += 1; _tracker.Move(i % 2 == 0 ? 1 : 5, 1); }
        _tracker.Move(41, 1);   // new ground ends the stall
        Assert.Single(Events(PlaytestEvents.Stuck));

        // A player who keeps reaching new cells, slowly, is exploring, not stuck.
        for (int i = 1; i <= 5; i++) StayUntil(_now + 100, 41 + 4 * i, 1);
        _tracker.EndLevel(LevelResult.Finished);
        Assert.Single(Events(PlaytestEvents.Stuck));
    }

    [Fact]
    public void ReenteringACellAfterTimeAwayIsARevisit()
    {
        _tracker.StartLevel("cave");
        _tracker.Move(1, 1);            // cell (0, 0)
        _now = 1; _tracker.Move(5, 1);  // (1, 0)
        _now = 2; _tracker.Move(1, 1);  // back after 1 s: walking along an edge, not a revisit
        _now = 3; _tracker.Move(5, 1);
        Assert.Empty(Events(PlaytestEvents.Revisit));
        _now = 20; _tracker.Move(1.5, 2, 0);   // back after 17 s away
        var revisit = Assert.Single(Events(PlaytestEvents.Revisit));
        Assert.Equal(2, revisit["visits"]!.GetValue<int>());
        Assert.Equal(20, revisit["level_seconds"]!.GetValue<double>());
        Assert.Equal(1.5, revisit["x"]!.GetValue<double>());
        _now = 40; _tracker.Move(5, 1);       // (1, 0) again, 37 s after leaving it
        _now = 60; _tracker.Move(1, 1);
        Assert.Equal(new[] { 2, 2, 3 }, Events(PlaytestEvents.Revisit).Select(e => e["visits"]!.GetValue<int>()));
    }

    [Fact]
    public void StayingBesideASolvedPuzzleIsSentOnLeaving()
    {
        _tracker.StartLevel("cave");
        _now = 10; _tracker.Move(2, 2);
        _tracker.PuzzleSolved(7);
        StayUntil(50, 3, 2);                   // within 8 units for 40 s
        Assert.Empty(Events(PlaytestEvents.SolvedButStayed));
        _now = 51; _tracker.Move(20, 2);       // gone
        var stayed = Assert.Single(Events(PlaytestEvents.SolvedButStayed));
        Assert.Equal(7, stayed["puzzle"]!.GetValue<int>());
        Assert.Equal(41, stayed["seconds"]!.GetValue<double>());
        Assert.Equal(10, stayed["level_seconds"]!.GetValue<double>());   // where and when it was solved
        Assert.Equal(2, stayed["x"]!.GetValue<double>());

        // Left within 30 s, through the game's own room exit: nothing to report.
        _tracker.PuzzleSolved(8);
        _now += 20; _tracker.Move(21, 2);
        _tracker.LeftPuzzle();
        _now += 60; _tracker.Move(21, 2);
        Assert.Single(Events(PlaytestEvents.SolvedButStayed));
    }

    [Fact]
    public void ItemsDeathsAndHintsAreSentWhereThePlayerIsAndTheLevelIsTimed()
    {
        _tracker.StartLevel("hub");
        _now = 5; _tracker.Move(10, -4, 2.5);
        _tracker.ItemFound(3);
        _now = 9; _tracker.Died(2);
        _tracker.HintRequested();
        _now = 12.346; _tracker.EndLevel(LevelResult.Failed);
        Assert.Equal(new[] { PlaytestEvents.ItemFound, PlaytestEvents.Death, PlaytestEvents.HintRequested, PlaytestEvents.LevelTime },
            Events().Select(e => e.Name));
        var death = Events(PlaytestEvents.Death)[0];
        Assert.Equal((10.0, -4.0, 2.5, 9.0, 2), (death["x"]!.GetValue<double>(), death["y"]!.GetValue<double>(), death["z"]!.GetValue<double>(),
            death["level_seconds"]!.GetValue<double>(), death["checkpoint"]!.GetValue<int>()));
        var time = Events(PlaytestEvents.LevelTime)[0];
        Assert.Equal(12.35, time["seconds"]!.GetValue<double>());   // hundredths of a second
        Assert.Equal("failed", time["result"]!.GetValue<string>());
        Assert.Null(_tracker.Level);
    }

    [Fact]
    public void TheLevelsEndClosesAnOpenStallAndANewLevelEndsTheOldOne()
    {
        _tracker.StartLevel("hub");
        StayUntil(150, 1, 1);
        _tracker.StartLevel("cave");   // hub was never ended: quit, with its stall
        Assert.Equal(150, Assert.Single(Events(PlaytestEvents.Stuck))["seconds"]!.GetValue<double>());
        var time = Assert.Single(Events(PlaytestEvents.LevelTime));
        Assert.Equal(("hub", "quit", 150.0), (time["level"]!.GetValue<string>(), time["result"]!.GetValue<string>(), time["seconds"]!.GetValue<double>()));
        Assert.Equal("cave", _tracker.Level);
    }

    [Fact]
    public void ALevelTheSchemaDoesNotListIsRefused()
    {
        _tracker.StartLevel("secret_room");
        Assert.Throws<SchemaException>(() => _tracker.Died(0));
    }

    [Fact]
    public void TheKitsTemplateDescribesTheSameEvents()
    {
        // ci/godot/templates/playtest-events.json is what hyperdot.ps1 playtest reads sessions with, and what a game in
        // another language copies: it must say exactly what PlaytestEvents does.
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !File.Exists(Path.Combine(dir.FullName, "ci", "godot", "templates", "playtest-events.json"))) dir = dir.Parent;
        Assert.True(dir != null, "ci/godot/templates/playtest-events.json was not found above " + AppContext.BaseDirectory);
        var template = JsonNode.Parse(File.ReadAllText(Path.Combine(dir!.FullName, "ci", "godot", "templates", "playtest-events.json")))!;
        Assert.Equal(PlaytestEvents.Version, template["version"]!.GetValue<int>());
        var events = template["events"]!.AsObject();
        var definitions = PlaytestEvents.Definitions(new[] { "hub" });
        Assert.Equal(definitions.Select(d => d.Name).OrderBy(n => n, StringComparer.Ordinal), events.Select(e => e.Key).OrderBy(n => n, StringComparer.Ordinal));
        foreach (var definition in definitions)
        {
            Assert.Equal(Purpose.Analytics, definition.Purpose);
            var json = events[definition.Name]!;
            Assert.Equal(definition.Version, json["v"]!.GetValue<int>());
            var fields = json["fields"]!.AsObject();
            Assert.Equal(definition.Fields.Keys.OrderBy(k => k, StringComparer.Ordinal), fields.Select(f => f.Key).OrderBy(k => k, StringComparer.Ordinal));
            foreach (var (name, kind) in definition.Fields)
            {
                var field = fields[name]!;
                string where = $"{definition.Name}.{name}";
                switch (kind)
                {
                    case FieldKind.Label when name == "level":
                        Assert.True(field["kind"]!.GetValue<string>() == "label" && field["allowed"] == null, $"{where}: the game's level ids");
                        break;
                    case FieldKind.Label label:
                        Assert.Equal("label", field["kind"]!.GetValue<string>());
                        Assert.Equal(label.Allowed, field["allowed"]!.AsArray().Select(a => a!.GetValue<string>()));
                        break;
                    case FieldKind.Number number:
                        Assert.Equal(("number", number.Min, number.Max), (field["kind"]!.GetValue<string>(), field["min"]!.GetValue<double>(), field["max"]!.GetValue<double>()));
                        break;
                    case FieldKind.Integer integer:
                        Assert.Equal(("integer", integer.Min, integer.Max), (field["kind"]!.GetValue<string>(), field["min"]!.GetValue<long>(), field["max"]!.GetValue<long>()));
                        break;
                    default:
                        Assert.Fail($"{where}: {kind} has no form in the template");
                        break;
                }
            }
        }
    }
}
