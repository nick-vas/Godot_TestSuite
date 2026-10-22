namespace Breakout.Core.Access;

/// <summary>
/// Something in the game world that can be described aloud: its name and one short functional description. Flavour text
/// (lore, jokes) may be kept for the screen, but is never spoken: players listening for clues take jokes for clues, and
/// shorter text is spoken sooner (Owlchemy Labs on Cosmonious High, following web alt-text practice).
/// </summary>
public sealed record Describable(string Name, string ShortText, string? Flavour = null);

/// <summary>Builds the spoken description of an object in a fixed order, shortest and always-present first.</summary>
public static class Narration
{
    /// <summary>
    /// "state, name, short description", for example "holding, star shades, sunglasses with star-shaped lenses". The
    /// player learns the order and can cancel as soon as they have heard what they need. Empty parts are left out.
    /// </summary>
    public static string Describe(string? state, string name, string? shortText)
    {
        if (string.IsNullOrWhiteSpace(name)) throw new ArgumentException("Everything that is described has a name", nameof(name));
        var parts = new[] { state, name, shortText }.Where(p => !string.IsNullOrWhiteSpace(p)).Select(p => p!.Trim());
        return string.Join(", ", parts);
    }

    /// <summary>The description of <paramref name="item"/>; its flavour text is left out on purpose.</summary>
    public static string Describe(string? state, Describable item) => Describe(state, item.Name, item.ShortText);
}

/// <summary>The engine's speech: in Godot, <c>DisplayServer.TtsSpeak</c> and <c>DisplayServer.TtsStop</c>.</summary>
public interface ISpeech
{
    /// <summary>Starts speaking, replacing anything queued: <c>TtsSpeak(text, voice, utteranceId: id, interrupt: true)</c>.</summary>
    void Speak(string text, long utteranceId);
    /// <summary>Stops speech and empties the queue: <c>TtsStop()</c>.</summary>
    void Stop();
}

public enum NarratorState
{
    Idle,
    /// <summary>Asked for, not yet audible: speech engines can take a moment to generate a line.</summary>
    Waiting,
    Speaking,
}

/// <summary>
/// On-demand narration with one assist action. Nothing is spoken because focus moved: a tap speaks what is focused,
/// a second tap stops it, and focus moving to something else stops a description of the old thing. Tutorials are the
/// exception and speak when shown (<see cref="Announce"/>). <see cref="Ducked"/> is true from the request until the
/// line ends or is stopped, so the rest of the mix is lowered at once (the player hears that the request was taken,
/// even while the engine is still generating speech) and comes back when the line is over. The engine's utterance
/// callbacks are passed to <see cref="Started"/>, <see cref="Ended"/> and <see cref="Canceled"/>; those for lines that
/// were already replaced are ignored.
/// </summary>
public sealed class AssistNarrator
{
    readonly ISpeech _speech;
    long _nextId;
    long _currentId;
    bool _currentIsFocus;
    object? _focus;
    string? _focusText;

    public AssistNarrator(ISpeech speech) => _speech = speech;

    public NarratorState State { get; private set; } = NarratorState.Idle;
    /// <summary>True exactly while a line is waiting or being spoken: lower the music and effects buses meanwhile.</summary>
    public bool Ducked => State != NarratorState.Idle;
    /// <summary>The utterance id of the line in progress, 0 when idle.</summary>
    public long CurrentUtterance => State == NarratorState.Idle ? 0 : _currentId;

    /// <summary>
    /// What the player's cursor, hand or selection is on now (<paramref name="target"/> null for nothing), with its
    /// description. Never speaks; moving to a different target stops a description of the previous one.
    /// </summary>
    public void Focus(object? target, string? description)
    {
        bool changed = !Equals(target, _focus);
        _focus = target;
        _focusText = target is null ? null : description;
        if (changed && State != NarratorState.Idle && _currentIsFocus) Cancel();
    }

    /// <summary>The assist action: speaks the focused thing when quiet, stops the current line otherwise.</summary>
    /// <returns>True when a line was started.</returns>
    public bool Tap()
    {
        if (State != NarratorState.Idle) { Cancel(); return false; }
        if (string.IsNullOrWhiteSpace(_focusText)) return false;
        Start(_focusText, isFocus: true);
        return true;
    }

    /// <summary>Speaks without being asked, replacing any line in progress: for tutorial prompts as they appear.</summary>
    public void Announce(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        Start(text, isFocus: false);
    }

    /// <summary><c>TTS_UTTERANCE_STARTED</c>.</summary>
    public void Started(long utteranceId)
    {
        if (State == NarratorState.Waiting && utteranceId == _currentId) State = NarratorState.Speaking;
    }

    /// <summary><c>TTS_UTTERANCE_ENDED</c>.</summary>
    public void Ended(long utteranceId) => Finish(utteranceId);

    /// <summary><c>TTS_UTTERANCE_CANCELED</c>, also sent when the engine could not speak the line.</summary>
    public void Canceled(long utteranceId) => Finish(utteranceId);

    void Start(string text, bool isFocus)
    {
        _currentId = ++_nextId;
        _currentIsFocus = isFocus;
        State = NarratorState.Waiting;
        _speech.Speak(text, _currentId);
    }

    void Cancel()
    {
        State = NarratorState.Idle;
        _speech.Stop();
    }

    void Finish(long utteranceId)
    {
        if (State != NarratorState.Idle && utteranceId == _currentId) State = NarratorState.Idle;
    }
}
