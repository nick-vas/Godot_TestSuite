namespace Example.Core.Analytics;

/// <summary>
/// How big a difference between two versions is, how sure we are of it, and the chance of seeing one this large if the
/// versions were the same (the two-tailed p-value). <see cref="NoEffect"/> is 0 for a difference and 1 for a ratio.
/// </summary>
public readonly record struct Effect(double Value, double Low, double High, double P, double NoEffect)
{
    /// <summary>False when the confidence interval straddles "no effect": then there is no result, whatever the estimate says.</summary>
    public bool IsResult => Low > NoEffect || High < NoEffect;
}

/// <param name="U">The Mann-Whitney U of the second sample: how many (a, b) pairs have b above a, ties counting half.</param>
/// <param name="ProbabilityBHigher">U over all pairs: the chance a random b beats a random a (0.5 means no difference).</param>
public readonly record struct RankEffect(double U, double ProbabilityBHigher, double P);

/// <summary>
/// The tests from "Three Statistical Tests Every Game Developer Should Know" (GDC; docs/gdc/three-statistical-tests.md),
/// chosen by what is measured: a number that has a meaningful mean (Welch's t-test, or the paired t-test when the same
/// players or seeds saw both versions), a yes/no outcome (relative risk, difference of proportions), and a skewed number
/// or a rating (Mann-Whitney). Everywhere <c>a</c> is the old version or control and <c>b</c> the new one, every p-value
/// is two-tailed, and <c>alpha</c> (fixed before looking at the data) sets the interval: 0.05 gives 95%.
/// </summary>
public static class Stats
{
    /// <summary>Two independent groups: b's mean minus a's, without assuming equal variances.</summary>
    public static Effect WelchTTest(IReadOnlyList<double> a, IReadOnlyList<double> b, double alpha = 0.05)
    {
        RequireAlpha(alpha);
        if (a.Count < 2 || b.Count < 2) throw new ArgumentException("each group needs at least two values");
        var (meanA, varA) = MeanVariance(a);
        var (meanB, varB) = MeanVariance(b);
        double seA = varA / a.Count, seB = varB / b.Count;
        double df = (seA + seB) * (seA + seB) / (seA * seA / (a.Count - 1) + seB * seB / (b.Count - 1));
        return TEffect(meanB - meanA, Math.Sqrt(seA + seB), df, alpha);
    }

    /// <summary>
    /// The same players (or seeds) measured on both versions, <c>a[i]</c> and <c>b[i]</c> belonging together: the mean of
    /// b[i] - a[i]. Differences between players cancel out, so it finds effects a two-group test misses.
    /// </summary>
    public static Effect PairedTTest(IReadOnlyList<double> a, IReadOnlyList<double> b, double alpha = 0.05)
    {
        RequireAlpha(alpha);
        if (a.Count != b.Count) throw new ArgumentException("paired samples need one b for every a");
        if (a.Count < 2) throw new ArgumentException("a paired test needs at least two pairs");
        var differences = new double[a.Count];
        for (int i = 0; i < a.Count; i++) differences[i] = b[i] - a[i];
        var (mean, variance) = MeanVariance(differences);
        return TEffect(mean, Math.Sqrt(variance / a.Count), a.Count - 1, alpha);
    }

    /// <summary>
    /// How many times as likely the outcome is in b as in a ("2.4 times as likely to buy"), with the log (Katz) interval.
    /// A group with no hits gets half a hit and half a miss added (Haldane), so the ratio stays finite.
    /// </summary>
    public static Effect RelativeRisk(int hitsA, int countA, int hitsB, int countB, double alpha = 0.05)
    {
        RequireAlpha(alpha);
        RequireCounts(hitsA, countA);
        RequireCounts(hitsB, countB);
        double hA = hitsA, nA = countA, hB = hitsB, nB = countB;
        if (hitsA == 0 || hitsB == 0) { hA += 0.5; nA += 1; hB += 0.5; nB += 1; }
        double logRatio = Math.Log(hB / nB / (hA / nA));
        double se = Math.Sqrt(1 / hB - 1 / nB + 1 / hA - 1 / nA);
        double z = NormalQuantile(1 - alpha / 2);
        double p = se == 0 ? (logRatio == 0 ? 1 : 0) : 2 * NormalCdf(-Math.Abs(logRatio) / se);
        return new Effect(Math.Exp(logRatio), Math.Exp(logRatio - z * se), Math.Exp(logRatio + z * se), p, 1);
    }

    /// <summary>
    /// b's rate minus a's in absolute terms ("from 5% to 12%, 7 points"), with the Wald interval; P is the usual pooled
    /// two-proportion z-test.
    /// </summary>
    public static Effect ProportionDifference(int hitsA, int countA, int hitsB, int countB, double alpha = 0.05)
    {
        RequireAlpha(alpha);
        RequireCounts(hitsA, countA);
        RequireCounts(hitsB, countB);
        double pA = (double)hitsA / countA, pB = (double)hitsB / countB, difference = pB - pA;
        double se = Math.Sqrt(pA * (1 - pA) / countA + pB * (1 - pB) / countB);
        double pooled = (double)(hitsA + hitsB) / (countA + countB);
        double sePooled = Math.Sqrt(pooled * (1 - pooled) * (1.0 / countA + 1.0 / countB));
        double p = sePooled == 0 ? 1 : 2 * NormalCdf(-Math.Abs(difference) / sePooled);
        double z = NormalQuantile(1 - alpha / 2);
        return new Effect(difference, difference - z * se, difference + z * se, p, 0);
    }

    /// <summary>
    /// Whether b's values tend to rank above a's: for skewed numbers (a few players who play for hours), ratings such as
    /// 1 to 5 stars, and anything that can only be ordered. Exact without ties up to 50 values in all; otherwise the
    /// normal approximation with the tie and continuity corrections.
    /// </summary>
    public static RankEffect MannWhitney(IReadOnlyList<double> a, IReadOnlyList<double> b)
    {
        if (a.Count == 0 || b.Count == 0) throw new ArgumentException("each group needs at least one value");
        int nA = a.Count, nB = b.Count, n = nA + nB;
        var all = new (double Value, bool IsB)[n];
        for (int i = 0; i < nA; i++) all[i] = (a[i], false);
        for (int i = 0; i < nB; i++) all[nA + i] = (b[i], true);
        Array.Sort(all, (x, y) => x.Value.CompareTo(y.Value));

        double rankSumB = 0, tieTerm = 0;
        for (int i = 0; i < n;)
        {
            int j = i;
            while (j < n && all[j].Value == all[i].Value) j++;
            double rank = (i + 1 + j) / 2.0;   // ties share the mean of their ranks
            for (int k = i; k < j; k++) if (all[k].IsB) rankSumB += rank;
            double tied = j - i;
            tieTerm += tied * tied * tied - tied;
            i = j;
        }
        double u = rankSumB - nB * (nB + 1) / 2.0, pairs = (double)nA * nB;

        double p;
        if (tieTerm == 0 && n <= 50) p = ExactRankP((int)u, nA, nB);
        else
        {
            double sigma = Math.Sqrt(pairs / 12 * (n + 1 - tieTerm / ((double)n * (n - 1))));
            p = sigma == 0 ? 1 : Math.Min(1, 2 * NormalCdf(-Math.Max(0, Math.Abs(u - pairs / 2) - 0.5) / sigma));
        }
        return new RankEffect(u, u / pairs, p);
    }

    /// <summary>
    /// How far a rate measured over <paramref name="rolls"/> independent rolls of a chance <paramref name="p"/> may sit
    /// from p before a test should call the chance wrong. <paramref name="falseAlarm"/> is the chance that a correct
    /// generator fails anyway; a test that checks several chance groups passes their number as <paramref name="groups"/>,
    /// and each gets falseAlarm / groups, so the whole test keeps that rate. The tolerance shrinks with the square root of
    /// the rolls: four times the rolls, half the tolerance.
    /// </summary>
    public static double BinomialTolerance(double p, int rolls, double falseAlarm = 0.001, int groups = 1)
    {
        if (!(p > 0 && p < 1)) throw new ArgumentOutOfRangeException(nameof(p), "a chance strictly between 0 and 1");
        RequireAlpha(falseAlarm);
        if (rolls < 1 || groups < 1) throw new ArgumentOutOfRangeException(nameof(rolls), "rolls and groups must be positive");
        if (rolls * p < 10 || rolls * (1 - p) < 10)
            throw new ArgumentException($"{rolls} rolls of a {p} chance are too few for this approximation: roll at least {Math.Ceiling(10 / Math.Min(p, 1 - p))}");
        return NormalQuantile(1 - falseAlarm / (2.0 * groups)) * Math.Sqrt(p * (1 - p) / rolls);
    }

    /// <summary>The standard normal distribution function.</summary>
    public static double NormalCdf(double x)
    {
        // erfc(y) = Q(1/2, y^2), the regularised upper incomplete gamma function.
        double y = Math.Abs(x) / Math.Sqrt(2);
        double half = 0.5 * UpperGamma(0.5, y * y);
        return x < 0 ? half : 1 - half;
    }

    public static double NormalQuantile(double probability) => Invert(NormalCdf, probability, -40, 40);

    /// <summary>Student's t distribution function with <paramref name="df"/> degrees of freedom (any real df &gt;= 1).</summary>
    public static double StudentTCdf(double t, double df)
    {
        double tail = 0.5 * RegularizedBeta(df / (df + t * t), df / 2, 0.5);
        return t > 0 ? 1 - tail : tail;
    }

    public static double StudentTQuantile(double probability, double df)
    {
        double bound = 1;
        while (StudentTCdf(bound, df) < probability || StudentTCdf(-bound, df) > probability) bound *= 2;
        return Invert(t => StudentTCdf(t, df), probability, -bound, bound);
    }

    static Effect TEffect(double difference, double se, double df, double alpha)
    {
        if (se == 0) return new Effect(difference, difference, difference, difference == 0 ? 1 : 0, 0);
        double p = 2 * StudentTCdf(-Math.Abs(difference / se), df);
        double half = StudentTQuantile(1 - alpha / 2, df) * se;
        return new Effect(difference, difference - half, difference + half, p, 0);
    }

    static (double Mean, double Variance) MeanVariance(IReadOnlyList<double> values)
    {
        double mean = 0;
        foreach (double v in values) mean += v;
        mean /= values.Count;
        double squares = 0;
        foreach (double v in values) squares += (v - mean) * (v - mean);
        return (mean, squares / (values.Count - 1));
    }

    // Two-tailed exact p of U for b: count how many ways nB of the ranks 1..n can be chosen for each rank sum.
    static double ExactRankP(int u, int nA, int nB)
    {
        int n = nA + nB, maxSum = n * (n + 1) / 2;
        var ways = new double[nB + 1, maxSum + 1];
        ways[0, 0] = 1;
        for (int rank = 1; rank <= n; rank++)
            for (int k = Math.Min(rank, nB); k >= 1; k--)
                for (int s = maxSum; s >= rank; s--)
                    ways[k, s] += ways[k - 1, s - rank];
        int offset = nB * (nB + 1) / 2;
        double total = 0, atMost = 0, atLeast = 0;
        for (int s = offset; s <= offset + nA * nB; s++)
        {
            double w = ways[nB, s];
            total += w;
            if (s - offset <= u) atMost += w;
            if (s - offset >= u) atLeast += w;
        }
        return Math.Min(1, 2 * Math.Min(atMost, atLeast) / total);
    }

    static double Invert(Func<double, double> cdf, double probability, double low, double high)
    {
        if (!(probability > 0 && probability < 1)) throw new ArgumentOutOfRangeException(nameof(probability), "must be strictly between 0 and 1");
        for (int i = 0; i < 200; i++)
        {
            double mid = (low + high) / 2;
            if (mid <= low || mid >= high) break;
            if (cdf(mid) < probability) low = mid; else high = mid;
        }
        return (low + high) / 2;
    }

    static void RequireAlpha(double alpha)
    {
        if (!(alpha > 0 && alpha < 1)) throw new ArgumentOutOfRangeException(nameof(alpha), "must be strictly between 0 and 1");
    }

    static void RequireCounts(int hits, int count)
    {
        if (count < 1 || hits < 0 || hits > count) throw new ArgumentOutOfRangeException(nameof(hits), $"{hits} of {count}");
    }

    // ln Gamma(x) for x >= 0.5: Lanczos, g = 7, nine terms (about 15 significant digits).
    static readonly double[] Lanczos =
    {
        0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059,
        12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7,
    };

    static double LogGamma(double x)
    {
        x -= 1;
        double sum = Lanczos[0], t = x + 7.5;
        for (int i = 1; i < Lanczos.Length; i++) sum += Lanczos[i] / (x + i);
        return 0.5 * Math.Log(2 * Math.PI) + (x + 0.5) * Math.Log(t) - t + Math.Log(sum);
    }

    const double Epsilon = 1e-15, Tiny = 1e-300;

    // Q(a, x): a series below a + 1, Lentz's continued fraction above (Numerical Recipes 6.2).
    static double UpperGamma(double a, double x)
    {
        if (x <= 0) return 1;
        double logPrefix = -x + a * Math.Log(x) - LogGamma(a);
        if (x < a + 1)
        {
            double term = 1 / a, sum = term;
            for (double ap = a + 1; Math.Abs(term) > Math.Abs(sum) * Epsilon; ap++) { term *= x / ap; sum += term; }
            return 1 - sum * Math.Exp(logPrefix);
        }
        double b = x + 1 - a, c = 1 / Tiny, d = 1 / b, h = d;
        for (int i = 1; i < 1000; i++)
        {
            double an = -i * (i - a);
            b += 2;
            d = an * d + b; if (Math.Abs(d) < Tiny) d = Tiny;
            c = b + an / c; if (Math.Abs(c) < Tiny) c = Tiny;
            d = 1 / d;
            double delta = d * c;
            h *= delta;
            if (Math.Abs(delta - 1) < Epsilon) break;
        }
        return Math.Exp(logPrefix) * h;
    }

    // I_x(a, b) by its continued fraction, on whichever side converges (Numerical Recipes 6.4).
    static double RegularizedBeta(double x, double a, double b)
    {
        if (x <= 0) return 0;
        if (x >= 1) return 1;
        double front = Math.Exp(LogGamma(a + b) - LogGamma(a) - LogGamma(b) + a * Math.Log(x) + b * Math.Log(1 - x));
        return x < (a + 1) / (a + b + 2) ? front * BetaFraction(x, a, b) / a : 1 - front * BetaFraction(1 - x, b, a) / b;
    }

    static double BetaFraction(double x, double a, double b)
    {
        double c = 1, d = 1 - (a + b) * x / (a + 1);
        if (Math.Abs(d) < Tiny) d = Tiny;
        d = 1 / d;
        double h = d;
        for (int m = 1; m < 1000; m++)
        {
            double even = m * (b - m) * x / ((a + 2 * m - 1) * (a + 2 * m));
            d = 1 + even * d; if (Math.Abs(d) < Tiny) d = Tiny;
            c = 1 + even / c; if (Math.Abs(c) < Tiny) c = Tiny;
            d = 1 / d;
            h *= d * c;
            double odd = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 2 * m + 1));
            d = 1 + odd * d; if (Math.Abs(d) < Tiny) d = Tiny;
            c = 1 + odd / c; if (Math.Abs(c) < Tiny) c = Tiny;
            d = 1 / d;
            double delta = d * c;
            h *= delta;
            if (Math.Abs(delta - 1) < Epsilon) break;
        }
        return h;
    }
}
