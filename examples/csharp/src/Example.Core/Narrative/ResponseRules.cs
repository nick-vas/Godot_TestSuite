namespace Example.Core.Narrative;

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
    /// Parses one criterion: "key=value", "key&lt;n", "key&lt;=n", "key&gt;n", "key&gt;=n", "key=true" or "!key"
    /// (missing or 0), in the grammar of <see cref="CriteriaSyntax"/>. Text values become symbols; strict comparisons step
    /// to the next representable number.
    /// </summary>
    public static Criterion Parse(string text, Symbols symbols)
    {
        var parsed = CriteriaSyntax.Parse(text);
        if (parsed.Count != 1) throw new FormatException($"'{text}' is {parsed.Count} criteria, not one (ParseAll reads a list)");
        return From(parsed[0], symbols);
    }

    /// <summary>Parses a list of criteria separated by ";" ("health&lt;25;weapon=shotgun"); empty or blank text is none.</summary>
    public static IReadOnlyList<Criterion> ParseAll(string? text, Symbols symbols) =>
        text is null ? [] : CriteriaSyntax.Parse(text).Select(c => From(c, symbols)).ToList();

    /// <summary>The interval a written criterion stands for.</summary>
    public static Criterion From(CriterionText c, Symbols symbols)
    {
        if (c.Op == "!") return new(c.Key, 0, 0, MissingPasses: true);
        var n = c.Number ?? symbols[c.Name!];
        return c.Op switch
        {
            "=" => new(c.Key, n, n),
            "<" => new(c.Key, double.NegativeInfinity, Math.BitDecrement(n)),
            "<=" => new(c.Key, double.NegativeInfinity, n),
            ">" => new(c.Key, Math.BitIncrement(n), double.PositiveInfinity),
            ">=" => new(c.Key, n, double.PositiveInfinity),
            _ => throw new FormatException($"unknown operator '{c.Op}'"),
        };
    }

    /// <summary>A value as a fact holds it: a number, true (1), false (0) or a name (its symbol).</summary>
    public static double Value(string raw, Symbols symbols) =>
        raw switch
        {
            "true" => 1,
            "false" => 0,
            _ when CriteriaSyntax.IsNumber(raw) => double.Parse(raw, System.Globalization.CultureInfo.InvariantCulture),
            _ => symbols[raw],
        };
}

/// <summary>
/// One criterion as written, before its value becomes a number: the fact, the operator ("=", "&lt;", "&lt;=", "&gt;",
/// "&gt;=", or "!" for missing or 0) and the value, a number (true is 1, false 0) or a name.
/// </summary>
public readonly record struct CriterionText(string Key, string Op, double? Number = null, string? Name = null);

/// <summary>A criteria syntax error: <see cref="Column"/> is 1-based, in UTF-16 characters of the whole text.</summary>
public sealed class CriteriaSyntaxException(int column, string reason) : FormatException($"column {column}: {reason}")
{
    public int Column { get; } = column;
    public string Reason { get; } = reason;
}

/// <summary>
/// The one grammar of criteria, shared with the kit's <c>data</c> runner (<c>Read-ResponseCriteria</c> in
/// ci/godot/lib/Data.ps1); <c>criteria-examples.json</c> in the tests holds the cases both must agree on, errors included.
/// <code>
/// criteria  = blank | criterion { ";" criterion }
/// criterion = blank ( "!" name | name blank op blank value ) blank
/// op        = "&lt;=" | "&gt;=" | "&lt;" | "&gt;" | "="
/// value     = number | "true" | "false" | name       (after &lt;, &lt;=, &gt;, &gt;=: a number only)
/// number    = [ "-" ] digit { digit } [ "." digit { digit } ]     (ASCII digits, a dot, no exponent)
/// name      = ( letter | "_" ) { letter | digit | "_" | "." | "-" }
/// blank     = { " " | "\t" }
/// </code>
/// </summary>
public static class CriteriaSyntax
{
    static readonly System.Text.RegularExpressions.Regex Number = new(@"^-?[0-9]+(\.[0-9]+)?\z");

    public static bool IsNumber(string raw) => Number.IsMatch(raw);

    public static bool IsName(string raw) =>
        raw.Length > 0 && (char.IsLetter(raw[0]) || raw[0] == '_') && raw.All(IsNameChar);

    static bool IsNameChar(char c) => char.IsLetterOrDigit(c) || c is '_' or '.' or '-';

    static bool IsBlank(char c) => c is ' ' or '\t';

    public static IReadOnlyList<CriterionText> Parse(string text)
    {
        var list = new List<CriterionText>();
        if (text.All(IsBlank)) return list;
        var i = 0;
        while (true)
        {
            list.Add(One(text, ref i));
            if (i == text.Length) return list;
            i++;   // past the ';'
        }
    }

    static CriterionText One(string t, ref int i)
    {
        SkipBlank(t, ref i);
        if (i == t.Length || t[i] == ';') throw Error(i, "empty criterion");
        var missing = t[i] == '!';
        if (missing) i++;
        if (i == t.Length || !(char.IsLetter(t[i]) || t[i] == '_'))
            throw Error(i, missing ? "expected a fact name after '!'" : "expected a fact name");
        var start = i;
        while (i < t.Length && IsNameChar(t[i])) i++;
        var key = t[start..i];
        SkipBlank(t, ref i);
        if (missing) { AtEnd(t, i); return new(key, "!"); }
        string op;
        if (i + 1 < t.Length && t[i] is ('<' or '>') && t[i + 1] == '=') op = t.Substring(i, 2);
        else if (i < t.Length && t[i] is ('<' or '>' or '=')) op = t[i].ToString();
        else throw Error(i, $"expected =, <, <=, > or >= after '{key}'");
        i += op.Length;
        SkipBlank(t, ref i);
        start = i;
        while (i < t.Length && !IsBlank(t[i]) && t[i] != ';') i++;
        var raw = t[start..i];
        if (raw.Length == 0) throw Error(start, $"expected a value after '{op}'");
        CriterionText parsed;
        if (IsNumber(raw)) parsed = new(key, op, double.Parse(raw, System.Globalization.CultureInfo.InvariantCulture));
        else if (op != "=") throw Error(start, $"'{op}' needs a number, not '{raw}'");
        else if (raw is "true" or "false") parsed = new(key, op, raw == "true" ? 1 : 0);
        else if (IsName(raw)) parsed = new(key, op, Name: raw);
        else throw Error(start, $"'{raw}' is neither a number nor a name");
        SkipBlank(t, ref i);
        AtEnd(t, i);
        return parsed;
    }

    static void SkipBlank(string t, ref int i) { while (i < t.Length && IsBlank(t[i])) i++; }

    static void AtEnd(string t, int i)
    {
        if (i < t.Length && t[i] != ';') throw Error(i, $"unexpected '{t[i]}'");
    }

    static CriteriaSyntaxException Error(int index, string reason) => new(index + 1, reason);
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

    /// <summary>The voice file of each line, in the order of <see cref="Lines"/>; null for a line not recorded yet.</summary>
    public IReadOnlyList<string?> Voices { get; init; } = [];

    public int Score => Criteria.Count + 1 + (Who is null ? 0 : 1);

    /// <summary>The voice file recorded for <paramref name="line"/> (a <see cref="Match.Line"/>), or null.</summary>
    public string? VoiceOf(string line)
    {
        for (var i = 0; i < Lines.Count && i < Voices.Count; i++)
            if (Lines[i] == line) return Voices[i];
        return null;
    }
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
