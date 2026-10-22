using System.Numerics;

namespace Breakout.Core.Audio;

// Voice limiting by place, after Guy Somberg's "max within radius" (Hellgate: London, BioShock 2; GDC talk "Lessons
// Learned from a Decade of Audio Programming"). It rests on Walter Murch's rule of two and a half: past two sources,
// listeners hear "footsteps", not each step. So each kind of sound plays at most a few voices within a radius of any new
// one: ten bricks breaking in one corner give two voices, bricks breaking on both sides still sound from both sides.
// Plain C#: the caller passes the time in, and plays the sound only when TryStart says so.

/// <summary>
/// The limits for one kind of sound. <see cref="MaxWithinRadius"/> voices may play within <see cref="Radius"/> of a new
/// one (world units; a 2D game passes Z = 0), <see cref="MaxTotal"/> anywhere. A start within the radius of another
/// start of the same kind less than <see cref="CooldownMs"/> earlier is refused, so copies started together do not stack
/// into one loud, phasing hit.
/// </summary>
public sealed record VoiceRule(int MaxWithinRadius, float Radius, int MaxTotal, double CooldownMs = 0);

public enum VoiceRefusal { None, UnknownKind, Cooldown, TooMany, Crowded }

/// <summary>
/// The answer to <see cref="VoiceLimiter.TryStart"/>: a handle to play under, or why not. A refused sound is dropped,
/// not queued: do not ask again every frame until it starts.
/// </summary>
public readonly record struct VoiceStart(int Handle, VoiceRefusal Refusal)
{
    public bool Started => Refusal == VoiceRefusal.None;
}

/// <summary>
/// Decides which sounds play. Handles are plain integers, never 0 and never reused, so a caller holding a stale one
/// cannot reach another voice; <see cref="Release"/> (call it when the sound finishes or is stopped) is safe to repeat.
/// </summary>
public sealed class VoiceLimiter
{
    readonly Dictionary<string, VoiceRule> _rules;
    readonly Dictionary<int, (string Kind, Vector3 Position)> _voices = new();
    readonly Dictionary<string, List<(int Handle, Vector3 Position)>> _playing = new();
    readonly Dictionary<string, List<(Vector3 Position, double AtMs)>> _recent = new();
    int _next = 1;

    public VoiceLimiter(IReadOnlyDictionary<string, VoiceRule> rules)
    {
        foreach (var (kind, rule) in rules)
        {
            if (rule.MaxWithinRadius < 1 || rule.MaxTotal < 1 || rule.Radius < 0 || rule.CooldownMs < 0)
                throw new ArgumentException($"rule for {kind}: limits must be at least 1, radius and cooldown not negative", nameof(rules));
        }
        _rules = new Dictionary<string, VoiceRule>(rules);
    }

    public int Playing => _voices.Count;
    public int PlayingOf(string kind) => _playing.TryGetValue(kind, out var list) ? list.Count : 0;
    public bool IsPlaying(int handle) => _voices.ContainsKey(handle);

    /// <summary>Starts a voice of <paramref name="kind"/> at <paramref name="position"/>, or says why it must not play.</summary>
    public VoiceStart TryStart(string kind, Vector3 position, double nowMs)
    {
        if (!_rules.TryGetValue(kind, out var rule)) return new VoiceStart(0, VoiceRefusal.UnknownKind);
        float radiusSquared = rule.Radius * rule.Radius;

        if (rule.CooldownMs > 0)
        {
            var recent = _recent.TryGetValue(kind, out var r) ? r : _recent[kind] = new();
            recent.RemoveAll(start => nowMs - start.AtMs >= rule.CooldownMs);
            foreach (var start in recent)
            {
                if (Vector3.DistanceSquared(start.Position, position) <= radiusSquared) return new VoiceStart(0, VoiceRefusal.Cooldown);
            }
        }

        var playing = _playing.TryGetValue(kind, out var p) ? p : _playing[kind] = new();
        if (playing.Count >= rule.MaxTotal) return new VoiceStart(0, VoiceRefusal.TooMany);
        int near = 0;
        foreach (var voice in playing)
        {
            if (Vector3.DistanceSquared(voice.Position, position) <= radiusSquared) near++;
        }
        if (near >= rule.MaxWithinRadius) return new VoiceStart(0, VoiceRefusal.Crowded);

        int handle = _next++;
        playing.Add((handle, position));
        _voices[handle] = (kind, position);
        if (rule.CooldownMs > 0) _recent[kind].Add((position, nowMs));
        return new VoiceStart(handle, VoiceRefusal.None);
    }

    /// <summary>Frees the voice's place. False when the handle is not playing (already released, refused or unknown).</summary>
    public bool Release(int handle)
    {
        if (!_voices.Remove(handle, out var voice)) return false;
        _playing[voice.Kind].RemoveAll(v => v.Handle == handle);
        return true;
    }
}
