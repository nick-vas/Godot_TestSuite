namespace Example.Core.Audio;

// A global voice budget with categories and priorities, the part Godot leaves to the game: each AudioStreamPlayer has
// its own MaxPolyphony, but nothing caps the voices of all players together or decides which sound gives way. Budgets
// as the audio middleware does them (FMOD and Wwise "voice stealing"): a cap per category, where a new sound steals that
// category's oldest voice; a cap over all categories, where a new sound steals the oldest voice of the lowest priority
// below its own; and protected categories (dialogue, the UI, the player's own weapon) whose voices are never stolen.
// Plain C#: the caller fades out the stolen voices and plays the new one. VoiceLimiter decides by place; use both.

/// <param name="MaxVoices">Voices of this category at once; a new one past it steals this category's oldest.</param>
/// <param name="Priority">Higher wins the global budget. A sound never steals one of equal or higher priority.</param>
/// <param name="Protected">Never stolen, by its own category or any other: when full, a new one is refused instead.</param>
public sealed record VoiceCategory(int MaxVoices, int Priority, bool Protected = false);

/// <summary>
/// The answer to <see cref="VoiceBudget.TryStart"/>: the new voice's handle (0 when refused), why not, and the voices it
/// took the place of, which the caller stops now (with a short fade, as Godot does for its own polyphony).
/// </summary>
public readonly record struct BudgetStart(int Handle, VoiceRefusal Refusal, IReadOnlyList<int> Stolen)
{
    public bool Started => Refusal == VoiceRefusal.None;
}

public sealed class VoiceBudget
{
    readonly Dictionary<string, VoiceCategory> _categories;
    // Every playing voice, oldest first: (handle, category, start order).
    readonly List<(int Handle, string Category)> _voices = new();
    int _next = 1;

    public VoiceBudget(int maxVoices, IReadOnlyDictionary<string, VoiceCategory> categories)
    {
        if (maxVoices < 1) throw new ArgumentException("The budget needs at least one voice", nameof(maxVoices));
        foreach (var (name, c) in categories)
            if (c.MaxVoices < 1) throw new ArgumentException($"category {name}: MaxVoices must be at least 1", nameof(categories));
        MaxVoices = maxVoices;
        _categories = new Dictionary<string, VoiceCategory>(categories);
    }

    public int MaxVoices { get; }
    public int Playing => _voices.Count;
    public int PlayingOf(string category) => _voices.Count(v => v.Category == category);
    public bool IsPlaying(int handle) => _voices.Exists(v => v.Handle == handle);

    public BudgetStart TryStart(string category)
    {
        if (!_categories.TryGetValue(category, out var c)) return new BudgetStart(0, VoiceRefusal.UnknownKind, []);
        var stolen = new List<int>();

        // The category's own cap first: its oldest voice gives way, unless the category is protected.
        if (PlayingOf(category) >= c.MaxVoices)
        {
            if (c.Protected) return new BudgetStart(0, VoiceRefusal.TooMany, []);
            var oldest = _voices.FindIndex(v => v.Category == category);
            stolen.Add(_voices[oldest].Handle);
            _voices.RemoveAt(oldest);
        }

        // Then the global cap: the oldest voice of the lowest priority below this one, never a protected one.
        if (_voices.Count >= MaxVoices)
        {
            int victim = -1;
            for (int i = 0; i < _voices.Count; i++)
            {
                var v = _categories[_voices[i].Category];
                if (v.Protected || v.Priority >= c.Priority) continue;
                if (victim < 0 || v.Priority < _categories[_voices[victim].Category].Priority) victim = i;   // ties keep the older
            }
            // Reached only without a same-category steal, which frees a place itself: nothing has been taken yet.
            if (victim < 0) return new BudgetStart(0, VoiceRefusal.TooMany, []);
            stolen.Add(_voices[victim].Handle);
            _voices.RemoveAt(victim);
        }

        int handle = _next++;
        _voices.Add((handle, category));
        return new BudgetStart(handle, VoiceRefusal.None, stolen);
    }

    /// <summary>Frees the voice's place when it finishes or is stopped. False when it is not playing.</summary>
    public bool Release(int handle) => _voices.RemoveAll(v => v.Handle == handle) > 0;
}
