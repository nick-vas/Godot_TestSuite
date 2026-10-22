namespace Breakout.Core.Audio;

/// <summary>
/// Gameplay on the music's beat, without the engine. The clock is Godot's documented method ("Sync the gameplay with audio
/// and music"): the song time the player hears is the player's playback position, plus the time since the last audio mix,
/// minus the output latency. <see cref="SpeedScale"/> is the idea Tango Gameworks described for Hi-Fi Rush (John Johanas,
/// GDC): whenever the player presses, the action's impact lands on the beat, because the animation is sped up after a late
/// press and slowed down after an early one. Times are seconds of song time; a beat is a quarter note.
/// </summary>
public static class BeatSync
{
    /// <summary>Seconds per beat (quarter note) at <paramref name="bpm"/>.</summary>
    public static double BeatLength(double bpm) =>
        bpm > 0 ? 60.0 / bpm : throw new ArgumentOutOfRangeException(nameof(bpm), bpm, "BPM must be positive");

    /// <summary>
    /// The song time the player hears now: AudioStreamPlayer.GetPlaybackPosition() + AudioServer.GetTimeSinceLastMix()
    /// - AudioServer.GetOutputLatency(). The position alone moves in whole mix chunks; the time since the last mix fills
    /// them in, and the latency is how long mixed sound takes to reach the speakers.
    /// </summary>
    public static double SongTime(double playbackPosition, double timeSinceLastMix, double outputLatency) =>
        playbackPosition + timeSinceLastMix - outputLatency;

    /// <summary>Beats since <paramref name="firstBeat"/> (the song time of beat 0, after any lead-in), fractional.</summary>
    public static double BeatPosition(double time, double beatLength, double firstBeat = 0) => (time - firstBeat) / beatLength;

    /// <summary>The song time of the first beat at or after <paramref name="time"/>.</summary>
    public static double NextBeat(double time, double beatLength, double firstBeat = 0) =>
        firstBeat + Math.Ceiling(BeatPosition(time, beatLength, firstBeat) - 1e-9) * beatLength;

    /// <summary>
    /// How far <paramref name="time"/> is from the nearest beat, in seconds: negative is early, positive late, never more
    /// than half a beat either way. Compare it with a window to decide whether a press earns the on-beat rewards.
    /// </summary>
    public static double OffsetFromBeat(double time, double beatLength, double firstBeat = 0) =>
        time - (firstBeat + NearestBeatIndex(time, beatLength, firstBeat) * beatLength);

    /// <summary>
    /// Where an action pressed at <paramref name="inputTime"/> lands: <paramref name="impactBeats"/> after the beat nearest
    /// the press, so a slightly early press and a slightly late one both hit the beat a punctual press would have.
    /// </summary>
    public static double ImpactTime(double inputTime, double beatLength, double impactBeats, double firstBeat = 0) =>
        firstBeat + (NearestBeatIndex(inputTime, beatLength, firstBeat) + impactBeats) * beatLength;

    /// <summary>
    /// The AnimationPlayer.SpeedScale that lands the action's impact on the beat (<see cref="ImpactTime"/>). The animation
    /// reaches its impact <paramref name="baseImpactSeconds"/> after it starts at speed 1; author it on the beat grid
    /// (impactBeats beats at the song's tempo) and a press exactly on the beat plays at 1.0, a late one faster (above 1)
    /// and an early one slower (below 1). The impact time never moves; only the wind-up stretches.
    /// </summary>
    public static double SpeedScale(double inputTime, double beatLength, double impactBeats, double baseImpactSeconds, double firstBeat = 0)
    {
        if (beatLength <= 0) throw new ArgumentOutOfRangeException(nameof(beatLength), beatLength, "beat length must be positive");
        if (impactBeats <= 0.5) throw new ArgumentOutOfRangeException(nameof(impactBeats), impactBeats, "an impact needs more than half a beat, or a late press would have no time left");
        double remaining = ImpactTime(inputTime, beatLength, impactBeats, firstBeat) - inputTime;
        return baseImpactSeconds / remaining;
    }

    static double NearestBeatIndex(double time, double beatLength, double firstBeat) =>
        Math.Floor(BeatPosition(time, beatLength, firstBeat) + 0.5);
}

/// <summary>
/// The song clock read once per frame. Several threads update the values it is built from, so a reading can come out a
/// little earlier than the last one; Godot's documentation says to discard such a reading. A step back can be as long
/// as one mix chunk (86 ms measured on Godot 4.7.2's Dummy driver, whose chunks are 93 ms). A jump back of more than
/// <see cref="MaxJitter"/> is a loop, and is taken; call <see cref="Reset"/> after a seek.
/// </summary>
public sealed class MusicClock
{
    public double MaxJitter = 0.25;
    public double Time { get; private set; } = double.NegativeInfinity;

    /// <summary>Pass the three engine values each frame; read GetOutputLatency() once (on start or a device change), it is expensive.</summary>
    public double Update(double playbackPosition, double timeSinceLastMix, double outputLatency)
    {
        double now = BeatSync.SongTime(playbackPosition, timeSinceLastMix, outputLatency);
        if (now >= Time || Time - now > MaxJitter) Time = now;
        return Time;
    }

    public void Reset() => Time = double.NegativeInfinity;
}
