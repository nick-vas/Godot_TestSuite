namespace Breakout.Core.Narrative;

/// <summary>
/// Turns text values into numbers so every criterion is one interval test, as in Elan Ruskin's dialogue system
/// ("Rule Databases for Contextual Dialog and Game Logic", GDC 2012; Left 4 Dead 2, Team Fortress 2, Portal 2, Dota 2):
/// "weapon = shotgun" is "id(shotgun) &lt;= weapon &lt;= id(shotgun)". One table per <see cref="ResponseSystem"/>.
/// </summary>
public sealed class Symbols
{
    readonly Dictionary<string, double> _ids = new(StringComparer.Ordinal);

    public double this[string text]
    {
        get
        {
            if (!_ids.TryGetValue(text, out var id)) _ids[text] = id = _ids.Count + 1;
            return id;
        }
    }
}

/// <summary>
/// One condition on one fact: <c>Min &lt;= fact &lt;= Max</c>. A fact the query lacks fails it, as in the talk ("one
/// mentions a fact not in the query, then the rule is considered to reject"), unless <see cref="MissingPasses"/>: then
/// "!key" also holds when nobody has written the fact or its memory has expired, which a running gag's cooldown needs.
/// </summary>
public readonly record struct Criterion(string Key, double Min, double Max, bool MissingPasses = false)
{
    public bool Test(IReadOnlyDictionary<string, double> facts) =>
        facts.TryGetValue(Key, out var value) ? value >= Min && value <= Max : MissingPasses;

    /// <summary>
    /// Parses "key=value", "key&lt;n", "key&lt;=n", "key&gt;n", "key&gt;=n", "key=true" or "!key" (missing or 0). Text
    /// values become symbols; strict comparisons step to the next representable number.
    /// </summary>
    public static Criterion Parse(string text, Symbols symbols)
    {
        text = text.Trim();
        if (text.StartsWith('!') && text.Length > 1 && text[1..].All(c => char.IsLetterOrDigit(c) || c is '_' or '.'))
            return new(text[1..], 0, 0, MissingPasses: true);
        foreach (var op in new[] { "<=", ">=", "<", ">", "=" })
        {
            var at = text.IndexOf(op, StringComparison.Ordinal);
            if (at <= 0) continue;
            var key = text[..at].Trim();
            var raw = text[(at + op.Length)..].Trim();
            if (op == "=") { var v = Value(raw, symbols); return new(key, v, v); }
            if (!double.TryParse(raw, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var n))
                throw new FormatException($"'{text}': {op} needs a number");
            return op switch
            {
                "<" => new(key, double.NegativeInfinity, Math.BitDecrement(n)),
                "<=" => new(key, double.NegativeInfinity, n),
                ">" => new(key, Math.BitIncrement(n), double.PositiveInfinity),
                _ => new(key, n, double.PositiveInfinity),
            };
        }
        throw new FormatException($"'{text}' is not a criterion (key=value, key<n, key<=n, key>n, key>=n, !key)");
    }

    internal static double Value(string raw, Symbols symbols) =>
        raw switch
        {
            "true" => 1,
            "false" => 0,
            _ when double.TryParse(raw, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var n) => n,
            _ => symbols[raw],
        };
}

/// <summary>A fact a matched rule writes into the speaker's memory (or the world's), optionally for a limited time.</summary>
public readonly record struct Remember(string Key, double Value, bool World = false, double? ForSeconds = null);

/// <summary>After the line ends, <paramref name="Concept"/> goes to <paramref name="Who"/>, or to everyone in earshot when null.</summary>
public readonly record struct FollowUp(string? Who, string Concept);

/// <summary>
/// A rule: criteria that must all hold, the lines it may say (one is picked at random; record several takes rather than
/// duplicating rules), facts it remembers, and an optional follow-up. Its score is its number of criteria, the speaker
/// and the concept included: the most specific rule wins. <see cref="Once"/> removes it after it plays, which Ruskin
/// wished he had built instead of "said it already" criteria.
/// </summary>
public sealed record Rule(string Name, string Concept, string? Who, IReadOnlyList<Criterion> Criteria, IReadOnlyList<string> Lines)
{
    public IReadOnlyList<Remember> Remembers { get; init; } = [];
    public FollowUp? Then { get; init; }
    public bool Once { get; init; }
    public int Score => Criteria.Count + 1 + (Who is null ? 0 : 1);
}

/// <summary>Facts with optional expiry times: a character's memory, or the world's.</summary>
public sealed class Memory
{
    readonly Dictionary<string, (double Value, double Until)> _facts = new(StringComparer.Ordinal);

    public void Set(string key, double value, double now, double? forSeconds = null) =>
        _facts[key] = (value, forSeconds is { } s ? now + s : double.PositiveInfinity);

    /// <summary>Copies the facts still valid at <paramref name="now"/> into <paramref name="into"/>, without replacing keys already there.</summary>
    public void AddTo(Dictionary<string, double> into, double now)
    {
        foreach (var (key, fact) in _facts)
            if (fact.Until > now) into.TryAdd(key, fact.Value);
    }
}

/// <summary>Someone who can speak: a name, facts computed now (health, weapon, nearby friends), and a memory.</summary>
public sealed class Speaker(string name)
{
    public string Name { get; } = name;
    public Memory Memory { get; } = new();
    public Dictionary<string, double> Facts { get; } = new(StringComparer.Ordinal);
}

/// <summary>A rule chosen for a speaker, with the line picked from it.</summary>
public sealed record Match(Speaker Speaker, Rule Rule, string Line, int Score);

/// <summary>
/// Ruskin's rule database. A query is one flat dictionary of every fact ("a flat pile of facts"): the event's own facts,
/// then the speaker's computed facts, the speaker's memory and the world's memory. Where two layers name the same key, the
/// earlier wins (the event is the most specific); the talk does not say. Rules are bucketed by concept and sorted by
/// score, so a lookup stops at the first match and only ties are drawn at random. Adding a rule never breaks another,
/// so content and mods can only add lines.
/// </summary>
public sealed class ResponseSystem
{
    readonly Dictionary<string, List<Rule>> _byConcept = new(StringComparer.Ordinal);
    readonly HashSet<Rule> _spent = new();
    readonly Random _random;

    public ResponseSystem(IEnumerable<Rule> rules, Symbols symbols, int seed = 0)
    {
        Symbols = symbols;
        _random = new Random(seed);
        foreach (var rule in rules)
        {
            if (rule.Lines.Count == 0) throw new ArgumentException($"rule '{rule.Name}' has no lines");
            if (!_byConcept.TryGetValue(rule.Concept, out var bucket)) _byConcept[rule.Concept] = bucket = new();
            bucket.Add(rule);
        }
        foreach (var bucket in _byConcept.Values) bucket.Sort((a, b) => b.Score.CompareTo(a.Score));
    }

    public Symbols Symbols { get; }
    public Memory World { get; } = new();

    /// <summary>The flat query for <paramref name="speaker"/>: event facts, its facts, its memory, the world's memory.</summary>
    public Dictionary<string, double> Query(Speaker speaker, IReadOnlyDictionary<string, double>? eventFacts, double now)
    {
        var facts = new Dictionary<string, double>(StringComparer.Ordinal);
        if (eventFacts is not null) foreach (var (k, v) in eventFacts) facts.TryAdd(k, v);
        foreach (var (k, v) in speaker.Facts) facts.TryAdd(k, v);
        speaker.Memory.AddTo(facts, now);
        World.AddTo(facts, now);
        return facts;
    }

    /// <summary>The best line <paramref name="speaker"/> has for <paramref name="concept"/> now, or null.</summary>
    public Match? Find(Speaker speaker, string concept, IReadOnlyDictionary<string, double>? eventFacts, double now)
    {
        if (!_byConcept.TryGetValue(concept, out var bucket)) return null;
        var facts = Query(speaker, eventFacts, now);
        var best = -1;
        var ties = new List<Rule>();
        foreach (var rule in bucket)
        {
            if (rule.Score < best) break;   // sorted: nothing below can win
            if (_spent.Contains(rule)) continue;
            if (rule.Who is not null && rule.Who != speaker.Name) continue;
            var all = true;
            foreach (var c in rule.Criteria) if (!c.Test(facts)) { all = false; break; }
            if (!all) continue;
            best = rule.Score;
            ties.Add(rule);
        }
        if (ties.Count == 0) return null;
        var chosen = ties[_random.Next(ties.Count)];
        return new Match(speaker, chosen, chosen.Lines[_random.Next(chosen.Lines.Count)], chosen.Score);
    }

    /// <summary>
    /// Asks everyone in earshot and keeps the best answer: "send one to all nearby characters within earshot
    /// simultaneously, to see if any of them have a reply; and of those which have the best reply". Equal scores go to the
    /// first listener.
    /// </summary>
    public Match? Ask(IEnumerable<Speaker> listeners, string concept, IReadOnlyDictionary<string, double>? eventFacts, double now)
    {
        Match? best = null;
        foreach (var listener in listeners)
        {
            var match = Find(listener, concept, eventFacts, now);
            if (match is not null && (best is null || match.Score > best.Score)) best = match;
        }
        return best;
    }

    /// <summary>
    /// The line was played: its facts are remembered and a <see cref="Rule.Once"/> rule is spent. The follow-up, if any,
    /// is the caller's to send when the line ends, with a fresh <see cref="Find"/> or <see cref="Ask"/>: the reply is looked
    /// up then, so a conversation stops by itself when its situation is over.
    /// </summary>
    public FollowUp? Played(Match match, double now)
    {
        foreach (var r in match.Rule.Remembers)
            (r.World ? World : match.Speaker.Memory).Set(r.Key, r.Value, now, r.ForSeconds);
        if (match.Rule.Once) _spent.Add(match.Rule);
        return match.Rule.Then;
    }
}
