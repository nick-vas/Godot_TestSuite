namespace Example.Core.Net;

/// <summary>What to do with one chat message, and with its sender.</summary>
public enum ChatVerdict
{
    Deliver,
    /// <summary>Too many messages too fast: drop this one, say so to the sender only.</summary>
    Slowed,
    /// <summary>The sender is muted: drop it, without telling the others.</summary>
    Muted,
    /// <summary>Deliver, and warn the sender once: their recent messages crossed the line.</summary>
    Warn,
    /// <summary>Drop it and mute the sender for <see cref="ChatGuardOptions.MuteSeconds"/>.</summary>
    Mute,
    /// <summary>Drop it, mute, and send the flagged excerpt to a person for review (the only thing kept).</summary>
    Report,
}

public sealed record ChatGuardOptions
{
    /// <summary>Messages scored over this span count toward the sender's average (clean-chat: 30 s).</summary>
    public double WindowSeconds { get; init; } = 30;
    /// <summary>Act when the average crosses this (clean-chat: 0.6 on 0 to 1)...</summary>
    public double Threshold { get; init; } = 0.6;
    /// <summary>...and act again only after it has fallen below this, so one bad stretch is one strike, not ten.</summary>
    public double Rearm { get; init; } = 0.4;
    public double MuteSeconds { get; init; } = 600;
    /// <summary>Chat rate: a burst of 5, then one message every 2 s.</summary>
    public double MessagesPerSecond { get; init; } = 0.5;
    public double Burst { get; init; } = 5;
    /// <summary>When the scorer throws or times out: false delivers the message unscored (clean-chat does, with score
    /// 0.00001), true holds it. Choose on purpose, and log it either way.</summary>
    public bool FailClosed { get; init; }
}

/// <summary>
/// Chat moderation after Google's clean-chat: score each message (0 is fine, 1 is abuse) with any scorer (a word list
/// to start, a model later), act on the sender's average over the last half minute rather than on one message (one
/// angry word is not a pattern; a stream of them is), act once per crossing (or once per window while it stays over the
/// line), and escalate: warn, then mute, then a report a person reads. Scoring happens on the server or a service, never on the client, which could skip it.
/// </summary>
public sealed class ChatGuard(Func<string, double> score, ChatGuardOptions options)
{
    sealed class Sender
    {
        public readonly Queue<(double At, double Score)> Recent = new();
        public bool Latched;
        public double LatchedAt;
        public int Strikes;
        public double MutedUntil = double.NegativeInfinity;
    }

    readonly Dictionary<string, Sender> _senders = new();
    readonly RateLimiter _rate = new(options.MessagesPerSecond, options.Burst);

    /// <summary>Scorer failures so far (the host should log and alert on a rise).</summary>
    public int ScorerFailures { get; private set; }

    public ChatVerdict Check(string playerId, string text, double now)
    {
        var s = _senders.TryGetValue(playerId, out var found) ? found : _senders[playerId] = new Sender();
        if (now < s.MutedUntil) return ChatVerdict.Muted;
        if (!_rate.Allow(playerId, now)) return ChatVerdict.Slowed;

        double value;
        try { value = Math.Clamp(score(text), 0, 1); }
        catch (Exception)
        {
            ScorerFailures++;
            if (options.FailClosed) return ChatVerdict.Slowed;
            value = 0;
        }
        s.Recent.Enqueue((now, value));
        while (s.Recent.Count > 0 && now - s.Recent.Peek().At > options.WindowSeconds) s.Recent.Dequeue();
        double average = s.Recent.Average(r => r.Score);

        if (s.Latched)
        {
            if (average < options.Rearm) s.Latched = false;
            // Still over the line a whole window after the last strike: that is the next strike, not the same one.
            if (!s.Latched || average < options.Threshold || now - s.LatchedAt < options.WindowSeconds) return ChatVerdict.Deliver;
        }
        else if (average < options.Threshold) return ChatVerdict.Deliver;
        s.Latched = true;
        s.LatchedAt = now;
        s.Strikes++;
        switch (s.Strikes)
        {
            case 1: return ChatVerdict.Warn;
            case 2: s.MutedUntil = now + options.MuteSeconds; return ChatVerdict.Mute;
            default: s.MutedUntil = now + options.MuteSeconds; return ChatVerdict.Report;
        }
    }
}

/// <summary>
/// A first scorer: whole words from a list, so "class" and "Scunthorpe" never match a shorter bad word inside them.
/// Letters only, case-insensitive, with common look-alike digits read as letters (0 o, 1 i, 3 e, 4 a, 5 s, 7 t, @ a, $ s).
/// Players get round any list; the average over time and a person reading the reports are what catch them.
/// </summary>
public sealed class WordListScorer(IEnumerable<string> words)
{
    readonly HashSet<string> _words = new(words.Select(Normalize), StringComparer.Ordinal);

    public double Score(string text)
    {
        var tokens = Normalize(text).Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return tokens.Any(_words.Contains) ? 1 : 0;
    }

    static string Normalize(string text)
    {
        var chars = text.ToLowerInvariant().Select(c => c switch
        {
            '0' => 'o', '1' => 'i', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't', '@' => 'a', '$' => 's',
            _ when char.IsLetter(c) => c,
            _ => ' ',
        });
        return new string(chars.ToArray());
    }
}
