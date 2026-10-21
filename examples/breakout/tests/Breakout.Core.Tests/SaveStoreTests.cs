using System.Text.Json.Nodes;
using Breakout.Core.Saves;
using Xunit;

namespace Breakout.Core.Tests;

public sealed class SaveStoreTests : IDisposable
{
    readonly string _dir = Directory.CreateTempSubdirectory("breakout-saves-").FullName;
    string SavePath => Path.Combine(_dir, "save.json");

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    static JsonObject Current(int score, int level = 1) => new()
    {
        ["best"] = new JsonObject { ["score"] = score, ["level"] = level },
        ["settings"] = new JsonObject { ["musicVolume"] = 0.8 },
    };

    static string Golden(string name) => Path.Combine(AppContext.BaseDirectory, "Saves", "golden", name);

    [Fact]
    public void SaveThenLoadGivesTheSameData()
    {
        BreakoutSave.Open(SavePath).Save(Current(900, 3), 60);
        var result = BreakoutSave.Open(SavePath).Load();
        Assert.Equal(SaveStatus.Ok, result.Status);
        Assert.Equal(SaveSource.Primary, result.Source);
        Assert.Equal(Current(900, 3).ToJsonString(), result.Data!.ToJsonString());
        Assert.False(File.Exists(SavePath + ".tmp"));
    }

    // Every released version's save, committed when it shipped, must still load.
    [Theory]
    [InlineData("v1.json", 1200, 0, 2)]   // N-2, from before envelopes
    [InlineData("v2.json", 2500, 4, 1)]   // N-1
    [InlineData("v3.json", 4100, 7, 0)]   // current
    public void EveryShippedVersionLoadsAndMigrates(string file, int score, int level, int migrations)
    {
        File.Copy(Golden(file), SavePath);
        var result = BreakoutSave.Open(SavePath).Load();
        Assert.Equal(SaveStatus.Ok, result.Status);
        Assert.Equal(score, result.Data!["best"]!["score"]!.GetValue<int>());
        Assert.Equal(level, result.Data!["best"]!["level"]!.GetValue<int>());
        Assert.Equal(migrations, result.Notes.Count(n => n.StartsWith("migrated")));
    }

    [Fact]
    public void AMigratedSaveIsWrittenBackAtTheCurrentVersion()
    {
        File.Copy(Golden("v1.json"), SavePath);
        var store = BreakoutSave.Open(SavePath);
        store.Save(store.Load().Data!, 0);
        var again = BreakoutSave.Open(SavePath).Load();
        Assert.Equal(BreakoutSave.CurrentVersion, again.Meta!.Version);
        Assert.Empty(again.Notes);
    }

    [Fact]
    public void ACorruptSaveFallsBackToTheBackup()
    {
        var store = BreakoutSave.Open(SavePath);
        store.Save(Current(100), 10);
        store.Save(Current(200), 20);                        // save.json.bak now holds score 100
        var bytes = File.ReadAllBytes(SavePath);
        bytes[bytes.Length / 2] ^= 0x20;                     // one flipped bit in the middle
        File.WriteAllBytes(SavePath, bytes);

        var result = BreakoutSave.Open(SavePath).Load();
        Assert.Equal(SaveStatus.Ok, result.Status);
        Assert.Equal(SaveSource.Backup, result.Source);
        Assert.Equal(100, result.Data!["best"]!["score"]!.GetValue<int>());
    }

    // Truncated at every byte (a write cut off by power loss): the loader never throws and never loads garbage.
    [Fact]
    public void TruncationAtEveryByteIsDetected()
    {
        var store = BreakoutSave.Open(SavePath);
        store.Save(Current(100), 10);
        store.Save(Current(200), 20);
        byte[] full = File.ReadAllBytes(SavePath);
        for (int length = 0; length < full.Length - 1; length++)
        {
            File.WriteAllBytes(SavePath, full[..length]);
            var result = BreakoutSave.Open(SavePath).Load();
            Assert.Equal(SaveStatus.Ok, result.Status);
            int score = result.Data!["best"]!["score"]!.GetValue<int>();
            Assert.True(score == 100 || (score == 200 && result.Source == SaveSource.Primary), $"length {length}: score {score} from {result.Source}");
        }
    }

    // A flipped bit anywhere (disk or transfer damage): either the copy is rejected, or what loads is exactly what was saved.
    [Fact]
    public void ABitFlipAnywhereIsDetected()
    {
        var store = BreakoutSave.Open(SavePath);
        store.Save(Current(100), 10);
        store.Save(Current(200), 20);
        byte[] original = File.ReadAllBytes(SavePath);
        string expected = Current(200).ToJsonString();
        for (int i = 0; i < original.Length; i++)
        {
            byte[] damaged = (byte[])original.Clone();
            damaged[i] ^= 0x04;
            File.WriteAllBytes(SavePath, damaged);
            var result = BreakoutSave.Open(SavePath).Load();
            if (result.Source == SaveSource.Primary) Assert.Equal(expected, result.Data!.ToJsonString());
            else Assert.Equal(100, result.Data!["best"]!["score"]!.GetValue<int>());
        }
    }

    [Fact]
    public void WithNoGoodCopyTheResultIsCorruptAndNothingIsOverwritten()
    {
        File.WriteAllText(SavePath, "{ \"format\": \"breakout-save\", \"version\": 3, ");
        var result = BreakoutSave.Open(SavePath).Load();
        Assert.Equal(SaveStatus.Corrupt, result.Status);
        Assert.Equal("{ \"format\": \"breakout-save\", \"version\": 3, ", File.ReadAllText(SavePath));
    }

    // The states an interrupted Save can leave: tmp written but not swapped in, or swapped halfway.
    [Fact]
    public void AnInterruptedWriteBeforeTheSwapKeepsTheNewerCompleteCopy()
    {
        var store = BreakoutSave.Open(SavePath);
        store.Save(Current(100), 10, new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        // Simulate: the next save wrote and flushed save.json.tmp, then the power went out.
        var other = BreakoutSave.Open(Path.Combine(_dir, "next.json"));
        other.Save(Current(300), 30, new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc));
        File.Move(Path.Combine(_dir, "next.json"), SavePath + ".tmp");

        var result = BreakoutSave.Open(SavePath).Load();
        Assert.Equal(SaveSource.PendingWrite, result.Source);
        Assert.Equal(300, result.Data!["best"]!["score"]!.GetValue<int>());
    }

    [Fact]
    public void AHalfWrittenTmpIsIgnored()
    {
        BreakoutSave.Open(SavePath).Save(Current(100), 10);
        File.WriteAllText(SavePath + ".tmp", "{ \"format\": \"breakout-save\", \"ver");
        var result = BreakoutSave.Open(SavePath).Load();
        Assert.Equal(SaveSource.Primary, result.Source);
        Assert.Equal(100, result.Data!["best"]!["score"]!.GetValue<int>());
    }

    [Fact]
    public void ASwapCutBetweenItsTwoRenamesStillLoads()
    {
        var store = BreakoutSave.Open(SavePath);
        store.Save(Current(100), 10);
        File.Move(SavePath, SavePath + ".bak");              // the old save moved aside, the new one never arrived
        var result = BreakoutSave.Open(SavePath).Load();
        Assert.Equal(SaveStatus.Ok, result.Status);
        Assert.Equal(SaveSource.Backup, result.Source);
    }

    [Fact]
    public void ASaveFromANewerGameIsNeitherLoadedNorTouched()
    {
        var future = new SaveStore(SavePath, 4, new Dictionary<int, Func<JsonObject, JsonObject>>
        {
            [1] = BreakoutSave.Migrations[1], [2] = BreakoutSave.Migrations[2], [3] = d => d,
        });
        future.Save(Current(999), 99);
        string before = File.ReadAllText(SavePath);
        var result = BreakoutSave.Open(SavePath).Load();
        Assert.Equal(SaveStatus.TooNew, result.Status);
        Assert.Null(result.Data);
        Assert.Equal(before, File.ReadAllText(SavePath));
    }

    [Fact]
    public void AMissingMigrationIsRefusedAtStartup() =>
        Assert.Throws<ArgumentException>(() => new SaveStore(SavePath, 3, new Dictionary<int, Func<JsonObject, JsonObject>> { [1] = d => d }));

    [Fact]
    public void NoSaveMeansANewGame() =>
        Assert.Equal(SaveStatus.Missing, BreakoutSave.Open(SavePath).Load().Status);

    [Fact]
    public void CloudSyncDecidesByLineageNotClocks()
    {
        var pc = BreakoutSave.Open(Path.Combine(_dir, "pc.json"));
        var a = pc.Save(Current(100), 10);
        File.Copy(Path.Combine(_dir, "pc.json"), Path.Combine(_dir, "deck.json"));
        var deck = BreakoutSave.Open(Path.Combine(_dir, "deck.json"));
        deck.Load();

        Assert.Equal(SyncDecision.InSync, CloudSync.Decide(a, a));
        Assert.Equal(SyncDecision.UploadLocal, CloudSync.Decide(a, null));

        // The PC plays on: the cloud copy (a) is its ancestor, so the PC is newer, whatever the clocks say.
        var b = pc.Save(Current(200), 20, new DateTime(2000, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        Assert.Equal(SyncDecision.UploadLocal, CloudSync.Decide(b, a));
        Assert.Equal(SyncDecision.DownloadCloud, CloudSync.Decide(a, b));

        // The Deck also played on from (a): both changed since they last agreed.
        var c = deck.Save(Current(150), 15);
        Assert.Equal(SyncDecision.Conflict, CloudSync.Decide(b, c));

        // Same moment, different contents is still a conflict.
        var d = deck.Save(Current(151), 15, b.SavedAtUtc);
        Assert.Equal(SyncDecision.Conflict, CloudSync.Decide(b, d));
    }
}
