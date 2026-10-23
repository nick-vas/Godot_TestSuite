using System.Globalization;
using System.Text;

namespace Example.Core.Procgen;

/// <summary>
/// A number that scores one generated output ("leniency", "dead-end share"), and the fixed range it is binned over. Fixed,
/// not fitted to the data, so maps of two parameter sets share their axes and can be compared bin by bin.
/// </summary>
public sealed record Metric<T>(string Name, Func<T, double> Score, double Min, double Max);

/// <summary>
/// The expressive range of a generator ("Making Things Up: The Power and Peril of PCG", Gillian Smith and Julian Togelius,
/// GDC; docs/gdc/expressive-range.md): generate many seeds, score each output on two metrics, and count the outputs in a
/// <see cref="Bins"/> x <see cref="Bins"/> histogram, the data behind a heat map. Pressing generate a few times shows a
/// handful of outputs; the map shows where the generator piles up, what it never makes, and how a parameter change moves it.
/// </summary>
public sealed class ExpressiveRange
{
    readonly int[] _counts;

    public string XName { get; }
    public string YName { get; }
    public double XMin { get; }
    public double XMax { get; }
    public double YMin { get; }
    public double YMax { get; }
    public int Bins { get; }

    /// <summary>How many outputs were scored.</summary>
    public int Total { get; }

    /// <summary>The mean of each metric over all outputs.</summary>
    public double MeanX { get; }
    public double MeanY { get; }

    ExpressiveRange(int[] counts, int bins, string xName, double xMin, double xMax, string yName, double yMin, double yMax,
        int total, double meanX, double meanY)
    {
        (_counts, Bins, XName, XMin, XMax, YName, YMin, YMax) = (counts, bins, xName, xMin, xMax, yName, yMin, yMax);
        (Total, MeanX, MeanY) = (total, meanX, meanY);
    }

    /// <summary>Outputs in bin (<paramref name="x"/>, <paramref name="y"/>); bin 0 holds each metric's Min.</summary>
    public int this[int x, int y] => _counts[Index(x, y)];

    /// <summary>Bins that hold at least one output.</summary>
    public int Occupied => _counts.Count(c => c > 0);

    /// <summary>Occupied bins over all bins: how much of the plotted space the generator reaches.</summary>
    public double OccupiedShare => (double)Occupied / _counts.Length;

    /// <summary>The fullest bin (the lowest x, then the lowest y, on a tie).</summary>
    public (int X, int Y) PeakBin
    {
        get
        {
            int best = 0;
            for (int i = 1; i < _counts.Length; i++) if (_counts[i] > _counts[best]) best = i;
            return (best % Bins, best / Bins);
        }
    }

    /// <summary>The fullest bin's share of all outputs: near 1 means nearly every seed gives the same kind of level.</summary>
    public double PeakShare => (double)_counts.Max() / Total;

    /// <summary>
    /// Generates every seed, scores the output on both metrics and bins it. Throws, naming the seed, when a score is not a
    /// number or falls outside its metric's range (a metric that escapes its range is a bug, and clamping would hide it).
    /// </summary>
    public static ExpressiveRange Map<T>(Func<ulong, T> generate, IEnumerable<ulong> seeds, Metric<T> x, Metric<T> y, int bins = 10)
    {
        if (bins < 1) throw new ArgumentOutOfRangeException(nameof(bins), "at least one bin per axis");
        RequireRange(x.Name, x.Min, x.Max);
        RequireRange(y.Name, y.Min, y.Max);
        var counts = new int[bins * bins];
        int total = 0;
        double sumX = 0, sumY = 0;
        foreach (ulong seed in seeds)
        {
            T output = generate(seed);
            double sx = x.Score(output), sy = y.Score(output);
            counts[Bin(sy, y.Min, y.Max, bins, y.Name, seed) * bins + Bin(sx, x.Min, x.Max, bins, x.Name, seed)]++;
            (sumX, sumY) = (sumX + sx, sumY + sy);
            total++;
        }
        if (total == 0) throw new ArgumentException("no seeds to map", nameof(seeds));
        return new ExpressiveRange(counts, bins, x.Name, x.Min, x.Max, y.Name, y.Min, y.Max, total, sumX / total, sumY / total);
    }

    /// <summary>
    /// The share of outputs the two maps put in the same bins (the sum over bins of the smaller of the two shares): 1 for the
    /// same distribution, 0 when the two parameter sets never make the same kind of level. Both maps need the same axes.
    /// </summary>
    public double Overlap(ExpressiveRange other)
    {
        RequireSameAxes(other);
        double shared = 0;
        for (int i = 0; i < _counts.Length; i++)
            shared += Math.Min((double)_counts[i] / Total, (double)other._counts[i] / other.Total);
        return shared;
    }

    /// <summary>The bins <paramref name="other"/> reaches and this map never does, by x then y.</summary>
    public IReadOnlyList<(int X, int Y)> Unreached(ExpressiveRange other)
    {
        RequireSameAxes(other);
        var missing = new List<(int X, int Y)>();
        for (int x = 0; x < Bins; x++)
            for (int y = 0; y < Bins; y++)
                if (this[x, y] == 0 && other[x, y] > 0) missing.Add((x, y));
        return missing;
    }

    /// <summary>One log line: <c>[range] leniency x linearity: 2000 outputs, 36% of bins, fullest bin 9.1%, means 0.83 / 0.72</c>.</summary>
    public string Summary() => string.Create(CultureInfo.InvariantCulture,
        $"[range] {XName} x {YName}: {Total} outputs, {OccupiedShare * 100:0}% of bins, fullest bin {PeakShare * 100:0.0}%, means {MeanX:0.00} / {MeanY:0.00}");

    /// <summary>
    /// Every bin, empty ones included so holes show, one row each: both metrics' bin edges and the count. Long format, so a
    /// spreadsheet pivot or any plotting tool draws the heat map from it.
    /// </summary>
    public string ToCsv()
    {
        var csv = new StringBuilder();
        csv.Append(CultureInfo.InvariantCulture, $"{XName}_low,{XName}_high,{YName}_low,{YName}_high,count\n");
        for (int y = 0; y < Bins; y++)
            for (int x = 0; x < Bins; x++)
                csv.Append(CultureInfo.InvariantCulture,
                    $"{Edge(XMin, XMax, x):0.####},{Edge(XMin, XMax, x + 1):0.####},{Edge(YMin, YMax, y):0.####},{Edge(YMin, YMax, y + 1):0.####},{this[x, y]}\n");
        return csv.ToString();
    }

    int Index(int x, int y) =>
        x >= 0 && x < Bins && y >= 0 && y < Bins ? y * Bins + x : throw new ArgumentOutOfRangeException(nameof(x), $"bin ({x},{y}) of {Bins}x{Bins}");

    double Edge(double min, double max, int bin) => min + (max - min) * bin / Bins;

    // Equal-width bins; Max itself belongs to the last one.
    static int Bin(double score, double min, double max, int bins, string name, ulong seed)
    {
        if (double.IsNaN(score) || score < min || score > max)
            throw new InvalidOperationException(string.Create(CultureInfo.InvariantCulture,
                $"seed {seed}: {name} scored {score}, outside its range {min} to {max}"));
        return Math.Min(bins - 1, (int)((score - min) / (max - min) * bins));
    }

    static void RequireRange(string name, double min, double max)
    {
        if (!(min < max) || double.IsInfinity(min) || double.IsInfinity(max))
            throw new ArgumentException($"metric {name} needs a finite range with Min below Max");
    }

    void RequireSameAxes(ExpressiveRange other)
    {
        if (other.Bins != Bins || other.XName != XName || other.YName != YName || other.XMin != XMin || other.XMax != XMax
            || other.YMin != YMin || other.YMax != YMax)
            throw new ArgumentException("the two maps need the same metrics, ranges and bins to be compared", nameof(other));
    }
}
