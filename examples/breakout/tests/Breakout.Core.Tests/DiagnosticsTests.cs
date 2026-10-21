using Breakout.Core.Telemetry;
using Xunit;

namespace Breakout.Core.Tests;

public sealed class DiagnosticsTests
{
    static string Thrown(Action action)
    {
        try { action(); }
        catch (Exception e) { return e.ToString(); }
        throw new InvalidOperationException("did not throw");
    }

    static void LoadLevel(string message) => throw new InvalidOperationException(message);
    static void SpawnBrick(string message) => throw new InvalidOperationException(message);
    static void BadIndex() => throw new IndexOutOfRangeException("Index was outside the bounds of the array.");
    // One call path, as the same bug takes every time it happens.
    static string CrashLoading(string message) => Thrown(() => LoadLevel(message));

    [Fact]
    public void TheSameCrashGetsTheSameFingerprintWhateverItsMessage()
    {
        string a = CrashFingerprint.From(CrashLoading("save of Ana at C:\\Users\\ana\\save.json"));
        string b = CrashFingerprint.From(CrashLoading("save of Bo at /home/bo/save.json"));
        Assert.Equal(a, b);
        Assert.Matches("^[0-9a-f]{16}$", a);
        Assert.NotEqual(a, CrashFingerprint.From(Thrown(() => SpawnBrick("x"))));   // somewhere else
        Assert.NotEqual(a, CrashFingerprint.From(Thrown(BadIndex)));                // something else
    }

    [Fact]
    public void AFingerprintFitsTheSchemaAndFreeTextDoesNot()
    {
        var schema = new TelemetrySchema(new EventDefinition("crash", 1, Purpose.Diagnostics, new Dictionary<string, FieldKind>
        {
            ["kind"] = new FieldKind.Label("exception", "engine", "unclean_exit"),
            ["fingerprint"] = new FieldKind.Fingerprint(),
        }));
        string fingerprint = CrashFingerprint.From(Thrown(BadIndex));
        Assert.Equal(fingerprint, schema.Build("crash", new Dictionary<string, object> { ["kind"] = "exception", ["fingerprint"] = fingerprint })["fingerprint"]!.GetValue<string>());
        Assert.Throws<SchemaException>(() => schema.Build("crash", new Dictionary<string, object> { ["kind"] = "exception", ["fingerprint"] = "Index was outside" }));
    }

    [Fact]
    public void AnUncleanExitIsNoticedAtTheNextStart()
    {
        string path = Path.Combine(Directory.CreateTempSubdirectory("marker-").FullName, "session.running");
        var marker = new SessionMarker(path);
        Assert.False(marker.Begin());   // first run
        marker.End();
        Assert.False(marker.Begin());   // the last one quit cleanly
        Assert.True(new SessionMarker(path).Begin());   // never reached End: crashed, killed or lost power
    }

    // A player who never agreed: no marker was written and its folder does not exist. Quitting must not throw.
    [Fact]
    public void EndingASessionThatWasNeverMarkedDoesNothing()
    {
        string path = Path.Combine(Path.GetTempPath(), $"never-{Guid.NewGuid():N}", "telemetry", "session.running");
        new SessionMarker(path).End();
        Assert.False(Directory.Exists(Path.GetDirectoryName(path)));
    }
}