// The palette check of `shot`: how much of a screenshot is drawn in colours that are not in the game's palette
// (docs/STYLE.md), compiled into the PowerShell session with Add-Type (lib/Palette.ps1), so it needs neither Godot nor a
// display and runs the same on Windows and Linux. A 1920x1080 picture takes well under a second.
//
// Every distinct colour of the picture is put in one of three classes:
//   on palette  within the tolerance (CIEDE2000) of a palette colour;
//   blend       within the tolerance of a mix of two palette colours that are both on screen, mixed in sRGB (Godot's 2D
//               blending) or in linear light (3D, MSAA, HDR 2D): anti-aliased edges, filtered sprites, translucent panels;
//   off         anything else.
// Off colours are then grouped greedily, the most common first, into clusters of colours within the tolerance of the
// cluster's first colour. A cluster that covers at least the minimum share of the picture is an off-palette colour (what
// palette bloat adds: a flat fill, a sprite, a gradient over a large area); the smaller ones are scattered pixels (noise,
// dithering, the corner where three colours meet) and are reported apart.
//
// PngImage reads what Godot's save_png writes (and any 8- or 16-bit, non-interlaced PNG) and writes 8-bit RGB PNGs, for the
// picture that marks the off-palette pixels and for the self-test's generated images (tests/Test-Palette.ps1).
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Threading.Tasks;

namespace GodotCi
{
public sealed class PngImage
{
    static readonly byte[] Signature = { 137, 80, 78, 71, 13, 10, 26, 10 };
    static readonly uint[] CrcTable = MakeCrcTable();

    public int Width { get; private set; }
    public int Height { get; private set; }
    /// <summary>8-bit RGBA, row by row from the top.</summary>
    public byte[] Rgba { get; private set; }

    public PngImage(int width, int height)
    {
        if (width < 1 || height < 1) throw new ArgumentException("A picture needs a width and a height of at least 1");
        Width = width;
        Height = height;
        Rgba = new byte[checked(width * height * 4)];
        for (int i = 3; i < Rgba.Length; i += 4) Rgba[i] = 255;
    }

    /// <summary>The colour at (x, y) as 0xRRGGBB.</summary>
    public int GetPixel(int x, int y)
    {
        int i = (y * Width + x) * 4;
        return (Rgba[i] << 16) | (Rgba[i + 1] << 8) | Rgba[i + 2];
    }

    public void SetPixel(int x, int y, int rgb)
    {
        int i = (y * Width + x) * 4;
        Rgba[i] = (byte)(rgb >> 16);
        Rgba[i + 1] = (byte)(rgb >> 8);
        Rgba[i + 2] = (byte)rgb;
        Rgba[i + 3] = 255;
    }

    public void FillRect(int x0, int y0, int width, int height, int rgb)
    {
        for (int y = Math.Max(0, y0); y < Math.Min(Height, y0 + height); y++)
            for (int x = Math.Max(0, x0); x < Math.Min(Width, x0 + width); x++) SetPixel(x, y, rgb);
    }

    public static PngImage Read(string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        for (int i = 0; i < Signature.Length; i++)
            if (bytes.Length < 8 || bytes[i] != Signature[i]) throw new InvalidDataException(path + " is not a PNG file");
        int width = 0, height = 0, depth = 0, type = -1;
        byte[] plte = null;
        var idat = new MemoryStream();
        int pos = 8;
        while (pos + 8 <= bytes.Length)
        {
            int length = ReadInt(bytes, pos);
            string chunk = Encoding.ASCII.GetString(bytes, pos + 4, 4);
            if (length < 0 || pos + 12 + length > bytes.Length) throw new InvalidDataException(path + " is cut short");
            if (chunk == "IHDR")
            {
                width = ReadInt(bytes, pos + 8);
                height = ReadInt(bytes, pos + 12);
                depth = bytes[pos + 16];
                type = bytes[pos + 17];
                if (bytes[pos + 20] != 0) throw new InvalidDataException(path + " is interlaced; save it without interlacing");
            }
            else if (chunk == "PLTE")
            {
                plte = new byte[length];
                Array.Copy(bytes, pos + 8, plte, 0, length);
            }
            else if (chunk == "IDAT") idat.Write(bytes, pos + 8, length);
            else if (chunk == "IEND") break;
            pos += 12 + length;
        }
        int channels;
        switch (type)
        {
            case 0: channels = 1; break;
            case 2: channels = 3; break;
            case 3: channels = 1; break;
            case 4: channels = 2; break;
            case 6: channels = 4; break;
            default: throw new InvalidDataException(path + " has no IHDR or an unknown colour type " + type);
        }
        bool depthOk = depth == 8 || (depth == 16 && type != 3) || ((depth == 1 || depth == 2 || depth == 4) && (type == 0 || type == 3));
        if (!depthOk || width < 1 || height < 1) throw new InvalidDataException(path + ": bit depth " + depth + " with colour type " + type + " is not valid");
        if (type == 3 && plte == null) throw new InvalidDataException(path + " is indexed but has no palette");

        int bitsPerPixel = channels * depth;
        int stride = (width * bitsPerPixel + 7) / 8;
        int bpp = Math.Max(1, bitsPerPixel / 8);
        byte[] raw = new byte[checked((stride + 1) * height)];
        idat.Position = 0;
        using (var z = new ZLibStream(idat, CompressionMode.Decompress))
        {
            int got = 0;
            while (got < raw.Length)
            {
                int n = z.Read(raw, got, raw.Length - got);
                if (n == 0) throw new InvalidDataException(path + ": the image data is shorter than " + width + "x" + height);
                got += n;
            }
        }

        var image = new PngImage(width, height);
        byte[] prev = new byte[stride];
        byte[] line = new byte[stride];
        for (int y = 0; y < height; y++)
        {
            int at = y * (stride + 1);
            byte filter = raw[at];
            Array.Copy(raw, at + 1, line, 0, stride);
            for (int i = 0; i < stride; i++)
            {
                int a = i >= bpp ? line[i - bpp] : 0;
                int b = prev[i];
                int c = i >= bpp ? prev[i - bpp] : 0;
                int predicted;
                switch (filter)
                {
                    case 0: predicted = 0; break;
                    case 1: predicted = a; break;
                    case 2: predicted = b; break;
                    case 3: predicted = (a + b) / 2; break;
                    case 4:
                        int p = a + b - c, pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c);
                        predicted = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
                        break;
                    default: throw new InvalidDataException(path + ": unknown row filter " + filter);
                }
                line[i] = (byte)(line[i] + predicted);
            }
            int o = y * width * 4;
            for (int x = 0; x < width; x++, o += 4)
            {
                if (type == 3)
                {
                    int index = Sample(line, x, depth);
                    if (index * 3 + 2 >= plte.Length) throw new InvalidDataException(path + ": a pixel uses palette entry " + index + ", past the palette");
                    image.Rgba[o] = plte[index * 3];
                    image.Rgba[o + 1] = plte[index * 3 + 1];
                    image.Rgba[o + 2] = plte[index * 3 + 2];
                }
                else if (depth < 8)
                {
                    byte v = (byte)(Sample(line, x, depth) * 255 / ((1 << depth) - 1));
                    image.Rgba[o] = v; image.Rgba[o + 1] = v; image.Rgba[o + 2] = v;
                }
                else
                {
                    // 16-bit samples keep their high byte.
                    int step = depth / 8, s = x * channels * step;
                    if (channels <= 2)
                    {
                        byte v = line[s];
                        image.Rgba[o] = v; image.Rgba[o + 1] = v; image.Rgba[o + 2] = v;
                        if (channels == 2) image.Rgba[o + 3] = line[s + step];
                    }
                    else
                    {
                        image.Rgba[o] = line[s]; image.Rgba[o + 1] = line[s + step]; image.Rgba[o + 2] = line[s + 2 * step];
                        if (channels == 4) image.Rgba[o + 3] = line[s + 3 * step];
                    }
                }
            }
            byte[] swap = prev; prev = line; line = swap;
        }
        return image;
    }

    /// <summary>Writes an 8-bit RGB PNG (alpha is dropped), each row with the Sub filter.</summary>
    public void Write(string path)
    {
        int stride = Width * 3;
        var raw = new byte[(stride + 1) * Height];
        for (int y = 0; y < Height; y++)
        {
            int at = y * (stride + 1);
            raw[at] = 1;
            for (int x = 0; x < Width; x++)
            {
                int i = (y * Width + x) * 4;
                for (int ch = 0; ch < 3; ch++)
                {
                    int left = x > 0 ? Rgba[i - 4 + ch] : 0;
                    raw[at + 1 + x * 3 + ch] = (byte)(Rgba[i + ch] - left);
                }
            }
        }
        var compressed = new MemoryStream();
        using (var z = new ZLibStream(compressed, CompressionLevel.Fastest, true)) z.Write(raw, 0, raw.Length);
        var header = new byte[13];
        WriteInt(header, 0, Width);
        WriteInt(header, 4, Height);
        header[8] = 8; header[9] = 2;
        using (var file = File.Create(path))
        {
            file.Write(Signature, 0, Signature.Length);
            WriteChunk(file, "IHDR", header);
            WriteChunk(file, "IDAT", compressed.ToArray());
            WriteChunk(file, "IEND", new byte[0]);
        }
    }

    static int Sample(byte[] line, int x, int depth)
    {
        if (depth == 8) return line[x];
        int bit = x * depth;
        return (line[bit >> 3] >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
    }

    static int ReadInt(byte[] b, int at) { return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]; }

    static void WriteInt(byte[] b, int at, int value)
    {
        b[at] = (byte)(value >> 24); b[at + 1] = (byte)(value >> 16); b[at + 2] = (byte)(value >> 8); b[at + 3] = (byte)value;
    }

    static void WriteChunk(Stream stream, string type, byte[] data)
    {
        var head = new byte[8];
        WriteInt(head, 0, data.Length);
        Encoding.ASCII.GetBytes(type, 0, 4, head, 4);
        stream.Write(head, 0, 8);
        stream.Write(data, 0, data.Length);
        uint crc = 0xFFFFFFFFu;
        for (int i = 4; i < 8; i++) crc = CrcTable[(crc ^ head[i]) & 0xFF] ^ (crc >> 8);
        foreach (byte b in data) crc = CrcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
        var tail = new byte[4];
        WriteInt(tail, 0, (int)(crc ^ 0xFFFFFFFFu));
        stream.Write(tail, 0, 4);
    }

    static uint[] MakeCrcTable()
    {
        var table = new uint[256];
        for (uint n = 0; n < 256; n++)
        {
            uint c = n;
            for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            table[n] = c;
        }
        return table;
    }
}

public struct Lab
{
    public double L, A, B;
    public Lab(double l, double a, double b) { L = l; A = a; B = b; }
}

public static class ColorMath
{
    static readonly double[] LinearTable = MakeLinearTable();

    /// <summary>sRGB (0..1) to linear light.</summary>
    public static double ToLinear(double c) { return c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4); }

    public static double ToSrgb(double c)
    {
        c = Math.Min(Math.Max(c, 0.0), 1.0);
        return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.Pow(c, 1 / 2.4) - 0.055;
    }

    public static double Linear8(int channel) { return LinearTable[channel & 0xFF]; }

    /// <summary>CIELAB (D65) from linear-light sRGB primaries.</summary>
    public static Lab FromLinear(double r, double g, double b)
    {
        double x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
        double y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
        double z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
        double fx = F(x), fy = F(y), fz = F(z);
        return new Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
    }

    /// <summary>CIELAB (D65) of a 0xRRGGBB colour.</summary>
    public static Lab FromRgb(int rgb) { return FromLinear(Linear8(rgb >> 16), Linear8(rgb >> 8), Linear8(rgb)); }

    public static string Hex(int rgb) { return "#" + (rgb & 0xFFFFFF).ToString("X6"); }

    /// <summary>CIEDE2000 (kL = kC = kH = 1), as Sharma, Wu and Dalal (2005) give it, with their test data in tests/Test-Palette.ps1.</summary>
    public static double DeltaE2000(Lab p, Lab q)
    {
        const double Pow25To7 = 6103515625.0;
        double c1 = Math.Sqrt(p.A * p.A + p.B * p.B), c2 = Math.Sqrt(q.A * q.A + q.B * q.B);
        double cMean7 = Pow7((c1 + c2) / 2);
        double g = 0.5 * (1 - Math.Sqrt(cMean7 / (cMean7 + Pow25To7)));
        double a1 = (1 + g) * p.A, a2 = (1 + g) * q.A;
        double c1p = Math.Sqrt(a1 * a1 + p.B * p.B), c2p = Math.Sqrt(a2 * a2 + q.B * q.B);
        double h1 = Hue(p.B, a1), h2 = Hue(q.B, a2);
        double dL = q.L - p.L, dC = c2p - c1p;
        double dh = 0;
        if (c1p * c2p != 0)
        {
            dh = h2 - h1;
            if (dh > 180) dh -= 360; else if (dh < -180) dh += 360;
        }
        double dH = 2 * Math.Sqrt(c1p * c2p) * Math.Sin(Radians(dh / 2));
        double lMean = (p.L + q.L) / 2, cpMean = (c1p + c2p) / 2;
        double hMean;
        if (c1p * c2p == 0) hMean = h1 + h2;
        else if (Math.Abs(h1 - h2) <= 180) hMean = (h1 + h2) / 2;
        else hMean = h1 + h2 < 360 ? (h1 + h2 + 360) / 2 : (h1 + h2 - 360) / 2;
        // T from the cosine and sine of the mean hue alone: the multiples by the double-angle formulas, the offsets by
        // the angle-sum formula with the constants below (cos and sin of 30, 6 and 63 degrees).
        double hr = Radians(hMean), c = Math.Cos(hr), s = Math.Sin(hr);
        double c2h = 2 * c * c - 1, s2h = 2 * s * c;
        double c3h = c * c2h - s * s2h, s3h = s * c2h + c * s2h;
        double c4h = 2 * c2h * c2h - 1, s4h = 2 * s2h * c2h;
        double t = 1 - 0.17 * (c * Cos30 + s * Sin30) + 0.24 * c2h + 0.32 * (c3h * Cos6 - s3h * Sin6) - 0.20 * (c4h * Cos63 + s4h * Sin63);
        double dThetaArg = (hMean - 275) / 25;
        double dTheta = 30 * Math.Exp(-dThetaArg * dThetaArg);
        double cp7 = Pow7(cpMean);
        double rc = 2 * Math.Sqrt(cp7 / (cp7 + Pow25To7));
        double l50 = (lMean - 50) * (lMean - 50);
        double sl = 1 + 0.015 * l50 / Math.Sqrt(20 + l50);
        double sc = 1 + 0.045 * cpMean;
        double sh = 1 + 0.015 * cpMean * t;
        double rt = -Math.Sin(Radians(2 * dTheta)) * rc;
        double tl = dL / sl, tc = dC / sc, th = dH / sh;
        return Math.Sqrt(Math.Max(0, tl * tl + tc * tc + th * th + rt * tc * th));
    }

    static double Hue(double b, double a)
    {
        if (a == 0 && b == 0) return 0;
        double h = Math.Atan2(b, a) * 180 / Math.PI;
        return h < 0 ? h + 360 : h;
    }

    static double Radians(double degrees) { return degrees * Math.PI / 180; }

    static double Pow7(double x) { double x2 = x * x; return x2 * x2 * x2 * x; }

    const double Cos30 = 0.86602540378443865, Sin30 = 0.5;
    const double Cos6 = 0.99452189536827333, Sin6 = 0.10452846326765347;
    const double Cos63 = 0.45399049973954675, Sin63 = 0.89100652418836786;

    static double F(double t) { return t > 216.0 / 24389 ? Math.Cbrt(t) : (24389.0 / 27 * t + 16) / 116; }

    static double[] MakeLinearTable()
    {
        var table = new double[256];
        for (int i = 0; i < 256; i++) table[i] = ToLinear(i / 255.0);
        return table;
    }
}

public sealed class OffPaletteColour
{
    /// <summary>The cluster's most common colour.</summary>
    public string Hex { get; set; }
    public int Pixels { get; set; }
    public double Percent { get; set; }
    /// <summary>The palette colour closest to it, and how far (CIEDE2000).</summary>
    public string Nearest { get; set; }
    public double DeltaE { get; set; }
    /// <summary>Whether the cluster covers at least the minimum share, so it counts in OffPalettePercent.</summary>
    public bool Counted { get; set; }
}

public sealed class PaletteResult
{
    public int Width { get; set; }
    public int Height { get; set; }
    public int DistinctColours { get; set; }
    public double OnPalettePercent { get; set; }
    public double BlendPercent { get; set; }
    public double OffPalettePercent { get; set; }
    public double ScatteredPercent { get; set; }
    /// <summary>How many off-palette clusters cover at least the minimum share.</summary>
    public int OffPaletteColourCount { get; set; }
    /// <summary>The largest off-palette clusters, counted or not, largest first.</summary>
    public OffPaletteColour[] Colours { get; set; }
    /// <summary>The picture with the counted off-palette pixels in magenta over a dimmed copy, or null.</summary>
    public string Image { get; set; }
}

public static class PaletteCheck
{
    /// <summary>Classifies every pixel of the picture against the palette (0xRRGGBB colours).</summary>
    public static PaletteResult Analyze(PngImage image, int[] palette, double tolerance, double minClusterPercent, int top, string markPath)
    {
        if (palette == null || palette.Length == 0) throw new ArgumentException("The palette has no colours");
        if (tolerance <= 0) throw new ArgumentException("The tolerance must be above 0");
        int total = image.Width * image.Height;

        var counts = new Dictionary<int, int>();
        byte[] px = image.Rgba;
        for (int i = 0; i < px.Length; i += 4)
        {
            int key = (px[i] << 16) | (px[i + 1] << 8) | px[i + 2];
            int n;
            counts.TryGetValue(key, out n);
            counts[key] = n + 1;
        }

        int pc = palette.Length;
        var palLab = new Lab[pc];
        var palSrgb = new double[pc, 3];
        var palLinear = new double[pc, 3];
        for (int i = 0; i < pc; i++)
        {
            palLab[i] = ColorMath.FromRgb(palette[i]);
            for (int ch = 0; ch < 3; ch++)
            {
                int v = (palette[i] >> (16 - 8 * ch)) & 0xFF;
                palSrgb[i, ch] = v / 255.0;
                palLinear[i, ch] = ColorMath.Linear8(v);
            }
        }

        // Pass 1: the nearest palette colour of every distinct colour. Each colour is independent, so the passes run on
        // every core.
        var keys = new int[counts.Count];
        counts.Keys.CopyTo(keys, 0);
        Array.Sort(keys);
        var cnt = new int[keys.Length];
        for (int k = 0; k < keys.Length; k++) cnt[k] = counts[keys[k]];
        var labs = new Lab[keys.Length];
        var nearest = new int[keys.Length];
        var nearestDe = new double[keys.Length];
        var cls = new byte[keys.Length];   // 0 on palette, 1 blend, 2 off
        Parallel.For(0, keys.Length, k =>
        {
            labs[k] = ColorMath.FromRgb(keys[k]);
            double best = double.MaxValue; int bestI = 0;
            for (int i = 0; i < pc; i++)
            {
                double d = ColorMath.DeltaE2000(labs[k], palLab[i]);
                if (d < best) { best = d; bestI = i; }
            }
            nearest[k] = bestI;
            nearestDe[k] = best;
            cls[k] = (byte)(best <= tolerance ? 0 : 2);
        });
        var present = new bool[pc];
        long onPixels = 0, blendPixels = 0;
        for (int k = 0; k < keys.Length; k++)
            if (cls[k] == 0) { present[nearest[k]] = true; onPixels += cnt[k]; }

        // Pass 2: the rest against the mixes of two palette colours that are both on screen.
        var pairs = new List<int[]>();
        for (int i = 0; i < pc; i++)
            for (int j = i + 1; j < pc; j++)
                if (present[i] && present[j]) pairs.Add(new[] { i, j });
        Parallel.For(0, keys.Length, k =>
        {
            if (cls[k] != 2) return;
            double r = ((keys[k] >> 16) & 0xFF) / 255.0, g = ((keys[k] >> 8) & 0xFF) / 255.0, b = (keys[k] & 0xFF) / 255.0;
            double lr = ColorMath.Linear8(keys[k] >> 16), lg = ColorMath.Linear8(keys[k] >> 8), lb = ColorMath.Linear8(keys[k]);
            foreach (var pair in pairs)
            {
                if (IsBlend(labs[k], r, g, b, palSrgb, pair[0], pair[1], false, tolerance)
                    || IsBlend(labs[k], lr, lg, lb, palLinear, pair[0], pair[1], true, tolerance))
                {
                    cls[k] = 1;
                    return;
                }
            }
        });
        for (int k = 0; k < keys.Length; k++) if (cls[k] == 1) blendPixels += cnt[k];

        // Off colours, most common first, into clusters; a hash of the clusters' first colours by CIELAB cell finds the
        // candidates near each colour. A colour too rare to matter alone (under 0.001% of the picture: noise, grain) can
        // join a cluster but does not start one, which keeps a noisy picture from making a cluster of every pixel.
        var off = new List<int>();
        for (int k = 0; k < keys.Length; k++) if (cls[k] == 2) off.Add(k);
        off.Sort((x, y) => { int c = cnt[y].CompareTo(cnt[x]); return c != 0 ? c : keys[x].CompareTo(keys[y]); });
        int seedFloor = Math.Max(1, total / 100000);
        var seeds = new List<int>();          // index into keys of each cluster's first colour
        var clusterPixels = new List<long>();
        var clusterOf = new Dictionary<int, int>();
        var grid = new Dictionary<long, List<int>>();
        long unclustered = 0;
        // How far in CIELAB a colour within the tolerance can be. Lightness: CIEDE2000 is at least |dL| / SL, and SL is
        // at most 1.75. a and b: the chroma and hue terms are at least 0.134 (1 - sin 60 degrees, the most the rotation
        // term takes off) of the sum of their squares, so the a'b' distance is at most 2.75 x tolerance x SC, where SC
        // = 1 + 0.045 x the mean C' grows with the other colour's chroma too (at most this one's C' plus half the
        // distance, and C' is at most 1.5 x the chroma); the a'b' distance is never less than the ab distance. A
        // saturated colour's reach spans many cells, so when the cells outnumber the clusters, every cluster is tried.
        double reachL = 1.75 * tolerance;
        foreach (int k in off)
        {
            Lab lab = labs[k];
            long cx = (long)Math.Floor(lab.L / tolerance), cy = (long)Math.Floor(lab.A / tolerance), cz = (long)Math.Floor(lab.B / tolerance);
            double chroma = Math.Sqrt(lab.A * lab.A + lab.B * lab.B);
            double shrink = 1 - 0.062 * tolerance;
            double reachAb = shrink > 0.05 ? 2.75 * tolerance * (1 + 0.0675 * chroma) / shrink : double.MaxValue;
            int found = -1; double foundDe = double.MaxValue;
            System.Action<int> consider = c =>
            {
                Lab s = labs[seeds[c]];
                if (Math.Abs(lab.L - s.L) > reachL) return;
                double da = lab.A - s.A, db = lab.B - s.B;
                if (da * da + db * db > reachAb * reachAb) return;
                double d = ColorMath.DeltaE2000(lab, s);
                if (d <= tolerance && (d < foundDe || (d == foundDe && c < found))) { found = c; foundDe = d; }
            };
            double l0 = Math.Floor((lab.L - reachL) / tolerance), l1 = Math.Floor((lab.L + reachL) / tolerance);
            double a0 = Math.Floor((lab.A - reachAb) / tolerance), a1 = Math.Floor((lab.A + reachAb) / tolerance);
            double b0 = Math.Floor((lab.B - reachAb) / tolerance), b1 = Math.Floor((lab.B + reachAb) / tolerance);
            if ((l1 - l0 + 1) * (a1 - a0 + 1) * (b1 - b0 + 1) > seeds.Count)
            {
                for (int c = 0; c < seeds.Count; c++) consider(c);
            }
            else
            {
                for (long x = (long)l0; x <= l1; x++)
                    for (long y = (long)a0; y <= a1; y++)
                        for (long z = (long)b0; z <= b1; z++)
                        {
                            List<int> cell;
                            if (!grid.TryGetValue(CellKey(x, y, z), out cell)) continue;
                            foreach (int c in cell) consider(c);
                        }
            }
            if (found < 0 && cnt[k] < seedFloor) { unclustered += cnt[k]; continue; }
            if (found < 0)
            {
                found = seeds.Count;
                seeds.Add(k);
                clusterPixels.Add(0);
                long cellKey = CellKey(cx, cy, cz);
                List<int> list;
                if (!grid.TryGetValue(cellKey, out list)) { list = new List<int>(); grid[cellKey] = list; }
                list.Add(found);
            }
            clusterPixels[found] += cnt[k];
            clusterOf[keys[k]] = found;
        }

        double minPixels = minClusterPercent / 100.0 * total;
        var counted = new List<int>();
        var all = new List<int>();
        long offPixels = 0, scatteredPixels = unclustered;
        for (int c = 0; c < seeds.Count; c++)
        {
            all.Add(c);
            if (clusterPixels[c] >= minPixels && clusterPixels[c] > 0) { counted.Add(c); offPixels += clusterPixels[c]; }
            else scatteredPixels += clusterPixels[c];
        }
        all.Sort((x, y) => { int c = clusterPixels[y].CompareTo(clusterPixels[x]); return c != 0 ? c : keys[seeds[x]].CompareTo(keys[seeds[y]]); });
        var colours = new List<OffPaletteColour>();
        for (int i = 0; i < all.Count && i < top; i++)
        {
            int seed = seeds[all[i]];
            long pixels = clusterPixels[all[i]];
            colours.Add(new OffPaletteColour
            {
                Hex = ColorMath.Hex(keys[seed]),
                Pixels = (int)pixels,
                Percent = Math.Round(100.0 * pixels / total, 3),
                Nearest = ColorMath.Hex(palette[nearest[seed]]),
                DeltaE = Math.Round(nearestDe[seed], 1),
                Counted = pixels >= minPixels && pixels > 0,
            });
        }

        string written = null;
        // PowerShell passes $null to a string parameter as "".
        if (!string.IsNullOrEmpty(markPath) && counted.Count > 0)
        {
            var isCounted = new bool[seeds.Count];
            foreach (int c in counted) isCounted[c] = true;
            var mark = new PngImage(image.Width, image.Height);
            for (int y = 0; y < image.Height; y++)
                for (int x = 0; x < image.Width; x++)
                {
                    int rgb = image.GetPixel(x, y);
                    int cluster;
                    if (clusterOf.TryGetValue(rgb, out cluster) && isCounted[cluster]) mark.SetPixel(x, y, 0xFF00FF);
                    else
                    {
                        int grey = (int)(0.35 * (0.299 * (rgb >> 16 & 0xFF) + 0.587 * (rgb >> 8 & 0xFF) + 0.114 * (rgb & 0xFF)));
                        mark.SetPixel(x, y, (grey << 16) | (grey << 8) | grey);
                    }
                }
            mark.Write(markPath);
            written = markPath;
        }

        return new PaletteResult
        {
            Width = image.Width,
            Height = image.Height,
            DistinctColours = keys.Length,
            OnPalettePercent = Math.Round(100.0 * onPixels / total, 2),
            BlendPercent = Math.Round(100.0 * blendPixels / total, 2),
            OffPalettePercent = Math.Round(100.0 * offPixels / total, 2),
            ScatteredPercent = Math.Round(100.0 * scatteredPixels / total, 2),
            OffPaletteColourCount = counted.Count,
            Colours = colours.ToArray(),
            Image = written,
        };
    }

    // Whether the colour lies within the tolerance of a mix of palette colours i and j, mixed in the space of `space`
    // (sRGB or linear values). (x, y, z) is the colour in that space; the mix tried is the point of the segment nearest to
    // it there, which for a real blend is the blend itself, give or take rounding.
    static bool IsBlend(Lab lab, double x, double y, double z, double[,] space, int i, int j, bool linear, double tolerance)
    {
        double dx = space[j, 0] - space[i, 0], dy = space[j, 1] - space[i, 1], dz = space[j, 2] - space[i, 2];
        double len2 = dx * dx + dy * dy + dz * dz;
        if (len2 == 0) return false;
        double t = ((x - space[i, 0]) * dx + (y - space[i, 1]) * dy + (z - space[i, 2]) * dz) / len2;
        if (t <= 0 || t >= 1) return false;
        double mx = space[i, 0] + t * dx, my = space[i, 1] + t * dy, mz = space[i, 2] + t * dz;
        // The mix's lightness first: CIEDE2000 is at least |dL| / SL, and SL is at most 1.75, so a mix this much lighter
        // or darker is out without the full formula.
        if (!linear) { mx = ColorMath.ToLinear(mx); my = ColorMath.ToLinear(my); mz = ColorMath.ToLinear(mz); }
        Lab mix = ColorMath.FromLinear(mx, my, mz);
        if (Math.Abs(mix.L - lab.L) > 1.75 * tolerance) return false;
        return ColorMath.DeltaE2000(lab, mix) <= tolerance;
    }

    static long CellKey(long x, long y, long z) { return ((x + 4096) << 26) | ((y + 4096) << 13) | (z + 4096); }
}
}
