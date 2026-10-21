using System.Text.Json.Nodes;
using Breakout.Core.Telemetry;
using Xunit;

namespace Breakout.Core.Tests;

public sealed class TelemetryTests
{
    sealed class ListSink : ITelemetrySink
    {
        public List<string> Batches { get; } = new();
        public bool Fail;
        public Task SendAsync(string batchJson, CancellationToken cancel)
        {
            if (Fail) throw new HttpRequestException("offline");
            Batches.Add(batchJson);
            return Task.CompletedTask;
        }
    }

    static readonly TelemetrySchema Schema = new(
        new EventDefinition("level_end", 1, Purpose.Analytics, new Dictionary<string, FieldKind>
        {
            ["floor"] = new FieldKind.Integer(1, 999),
            ["result"] = new FieldKind.Label("cleared", "died", "quit"),
            ["seconds"] = new FieldKind.Number(0, 86_400),
        }),
        new EventDefinition("crash", 1, Purpose.Diagnostics, new Dictionary<string, FieldKind>
        {
            ["kind"] = new FieldKind.Label("exception", "native", "hang"),
            ["in_menu"] = new FieldKind.Flag(),
        }));

    static Dictionary<string, object> LevelEnd(int floor = 3) => new() { ["floor"] = floor, ["result"] = "died", ["seconds"] = 61.5 };

    [Fact]
    public void NothingIsRecordedBeforeConsentOrAfterItIsWithdrawn()
    {
        var client = new TelemetryClient(Schema, "1.0.0");
        Assert.False(client.Track("level_end", LevelEnd()));
        Assert.Equal(0, client.Queued);

        client.SetConsent(Purpose.Analytics, Consent.Granted);
        Assert.True(client.Track("level_end", LevelEnd()));
        Assert.False(client.Track("crash", new Dictionary<string, object> { ["kind"] = "hang", ["in_menu"] = false }));   // not asked
        Assert.Equal(1, client.Queued);

        client.SetConsent(Purpose.Analytics, Consent.Refused);
        Assert.Equal(0, client.Queued);   // withdrawn: what was held is gone, unsent
        Assert.False(client.Track("level_end", LevelEnd()));
    }

    [Fact]
    public async Task EveryBatchCarriesItsConsentAndNoIdentifier()
    {
        var client = new TelemetryClient(Schema, "1.0.0") { MaxBatch = 2 };
        client.SetConsent(Purpose.Analytics, Consent.Granted);
        for (int i = 1; i <= 5; i++) client.Track("level_end", LevelEnd(i));
        var sink = new ListSink();
        Assert.Equal(5, await client.FlushAsync(sink));
        Assert.Equal(3, sink.Batches.Count);

        foreach (var batch in sink.Batches.Select(b => JsonNode.Parse(b)!.AsObject()))
        {
            Assert.Equal("Granted", batch["consent"]!["analytics"]!.GetValue<string>());
            Assert.Equal(new[] { "schema", "session", "build", "consent", "events" }, batch.Select(p => p.Key));
            Assert.Equal(32, batch["session"]!.GetValue<string>().Length);   // random per launch, nothing else identifies
            foreach (var e in batch["events"]!.AsArray())
                Assert.Equal(new[] { "event", "v", "seq", "t", "fields" }, e!.AsObject().Select(p => p.Key));
        }
        Assert.NotEqual(new TelemetryClient(Schema, "1.0.0").SessionId, client.SessionId);
    }

    [Fact]
    public async Task AFailedSendKeepsTheEventsAndOldOnesExpireUnsent()
    {
        var now = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var client = new TelemetryClient(Schema, "1.0.0", () => now);
        client.SetConsent(Purpose.Analytics, Consent.Granted);
        client.Track("level_end", LevelEnd());
        var sink = new ListSink { Fail = true };
        await Assert.ThrowsAsync<HttpRequestException>(() => client.FlushAsync(sink));
        Assert.Equal(1, client.Queued);

        now = now.AddDays(8);   // offline for longer than events are kept
        sink.Fail = false;
        Assert.Equal(0, await client.FlushAsync(sink));
        Assert.Empty(sink.Batches);
    }

    [Fact]
    public void EventsMustFitTheSchemaExactly()
    {
        var client = new TelemetryClient(Schema, "1.0.0");
        client.SetConsent(Purpose.Analytics, Consent.Granted);
        Assert.Throws<SchemaException>(() => client.Track("level_end", new Dictionary<string, object>(LevelEnd()) { ["player"] = "Ana" }));   // extra field
        Assert.Throws<SchemaException>(() => client.Track("level_end", new Dictionary<string, object> { ["floor"] = 3, ["result"] = "died" }));   // missing
        Assert.Throws<SchemaException>(() => client.Track("level_end", new Dictionary<string, object>(LevelEnd()) { ["result"] = "rage quit at Ana's house" }));
        Assert.Throws<SchemaException>(() => client.Track("level_end", LevelEnd(floor: 5000)));
        Assert.Throws<SchemaException>(() => client.Track("level_end", new Dictionary<string, object>(LevelEnd()) { ["seconds"] = double.NaN }));
        Assert.Throws<SchemaException>(() => client.Track("unknown_event"));
    }

    [Theory]
    [InlineData("player_email")]
    [InlineData("user_id")]
    [InlineData("device_id")]
    [InlineData("ip")]
    [InlineData("chat_text")]
    [InlineData("display_name")]
    [InlineData("save_path")]
    public void FieldsThatSoundPersonalAreRefused(string field)
    {
        var ex = Assert.Throws<SchemaException>(() => new TelemetrySchema(new EventDefinition("e", 1, Purpose.Analytics,
            new Dictionary<string, FieldKind> { [field] = new FieldKind.Flag() })));
        Assert.Contains("personal", ex.Message);
    }

    [Theory]
    [InlineData("clip_count")]
    [InlineData("level_name")]
    [InlineData("damage")]
    [InlineData("ship_speed")]
    public void OrdinaryGameFieldsAreAllowed(string field) => Assert.False(TelemetrySchema.LooksPersonal(field));

    [Fact]
    public async Task ThePlayerCanSeeAndEraseWhatIsHeld()
    {
        var client = new TelemetryClient(Schema, "1.0.0");
        client.SetConsent(Purpose.Diagnostics, Consent.Granted);
        client.Track("crash", new Dictionary<string, object> { ["kind"] = "exception", ["in_menu"] = true });
        await client.FlushAsync(new ListSink());
        client.Track("crash", new Dictionary<string, object> { ["kind"] = "hang", ["in_menu"] = false });

        var export = JsonNode.Parse(client.Export())!;
        Assert.Equal(client.SessionId, export["sessions"]![0]!.GetValue<string>());
        Assert.Single(export["queued"]!.AsArray());

        var toDelete = client.Erase();
        Assert.Equal(new[] { client.SessionId }, toDelete);   // what the server must delete
        Assert.Equal(0, client.Queued);
    }
}
