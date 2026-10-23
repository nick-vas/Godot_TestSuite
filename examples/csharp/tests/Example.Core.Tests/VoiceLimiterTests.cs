using System.Numerics;
using Example.Core.Audio;
using Xunit;

namespace Example.Core.Tests;

/// <summary>Voice limiting by place (Somberg's "max within radius"): few voices per spot, every direction still heard.</summary>
public sealed class VoiceLimiterTests
{
    // Two brick-break voices within 5 units of each other, 32 in all; a pickup with a 60 ms cooldown.
    static VoiceLimiter Limiter(int maxTotal = 32) => new(new Dictionary<string, VoiceRule>
    {
        ["brick"] = new(MaxWithinRadius: 2, Radius: 5, MaxTotal: maxTotal),
        ["pickup"] = new(MaxWithinRadius: 8, Radius: 5, MaxTotal: 32, CooldownMs: 60),
    });

    static Vector3 At(float x, float y = 0) => new(x, y, 0);

    [Fact]
    public void TenSoundsInOneSpotPlayTwoVoices()
    {
        var voices = Limiter();
        var starts = Enumerable.Range(0, 10).Select(i => voices.TryStart("brick", At(i * 0.1f), nowMs: 0)).ToList();

        Assert.Equal(2, starts.Count(s => s.Started));
        Assert.All(starts.Skip(2), s => Assert.Equal(new VoiceStart(0, VoiceRefusal.Crowded), s));
        Assert.Equal(2, voices.Playing);
    }

    [Fact]
    public void ClustersFarApartEachKeepTheirVoices()
    {
        var voices = Limiter();
        // Ten breaks shared among three spots 20 units apart: the sound keeps coming from all three.
        var starts = Enumerable.Range(0, 10).Select(i => (Cluster: i % 3, Start: voices.TryStart("brick", At(i % 3 * 20f, i * 0.1f), nowMs: 0))).ToList();

        Assert.Equal(6, voices.Playing);
        foreach (var cluster in Enumerable.Range(0, 3)) Assert.Equal(2, starts.Count(s => s.Cluster == cluster && s.Start.Started));
    }

    [Fact]
    public void ReleaseFreesThePlaceOnceAndIsSafeToRepeat()
    {
        var voices = Limiter();
        var first = voices.TryStart("brick", At(0), 0);
        voices.TryStart("brick", At(1), 0);
        Assert.False(voices.TryStart("brick", At(2), 0).Started);

        Assert.True(voices.Release(first.Handle));
        Assert.False(voices.IsPlaying(first.Handle));
        Assert.False(voices.Release(first.Handle));       // the sound's "finished" and a stop both release: no harm
        Assert.False(voices.Release(0));                  // the handle of a refused start
        Assert.False(voices.Release(12345));
        Assert.Equal(1, voices.Playing);

        var next = voices.TryStart("brick", At(2), 0);
        Assert.True(next.Started);
        Assert.False(voices.TryStart("brick", At(3), 0).Started);   // one release made room for one voice, not two
    }

    [Fact]
    public void MaxTotalCapsTheKindAcrossClusters()
    {
        var voices = Limiter(maxTotal: 4);
        var starts = Enumerable.Range(0, 9).Select(i => voices.TryStart("brick", At(i % 3 * 20f), 0)).ToList();

        Assert.Equal(4, voices.PlayingOf("brick"));
        Assert.Contains(starts, s => s.Refusal == VoiceRefusal.TooMany);
    }

    [Fact]
    public void ACooldownRefusesARepeatNearbyButNotFarAway()
    {
        var voices = Limiter();
        Assert.True(voices.TryStart("pickup", At(0), nowMs: 0).Started);
        Assert.Equal(VoiceRefusal.Cooldown, voices.TryStart("pickup", At(1), nowMs: 30).Refusal);
        Assert.True(voices.TryStart("pickup", At(40), nowMs: 30).Started);    // another place: its own sound
        Assert.True(voices.TryStart("pickup", At(1), nowMs: 60).Started);     // 60 ms later it may play again
        Assert.True(voices.TryStart("brick", At(0), nowMs: 60).Started);      // cooldowns are per kind
    }

    [Fact]
    public void HandlesAreDistinctIntegersAndUnknownKindsAreRefused()
    {
        var voices = Limiter();
        var handles = Enumerable.Range(0, 5).Select(i => voices.TryStart("brick", At(i * 20f), 0).Handle).ToList();
        Assert.DoesNotContain(0, handles);
        Assert.Equal(handles.Count, handles.Distinct().Count());

        voices.Release(handles[0]);
        Assert.DoesNotContain(voices.TryStart("brick", At(0), 0).Handle, handles);   // never reused: a stale handle reaches nothing
        Assert.Equal(new VoiceStart(0, VoiceRefusal.UnknownKind), voices.TryStart("explosion", At(0), 0));
        Assert.Throws<ArgumentException>(() => new VoiceLimiter(new Dictionary<string, VoiceRule> { ["x"] = new(0, 1, 1) }));
    }
}
