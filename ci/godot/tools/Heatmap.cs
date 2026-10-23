// Heat maps for `hypedot.ps1 playtest`: counts on a grid drawn as a PNG, alone or over a level screenshot. Compiled into
// the PowerShell session with Add-Type (as Sfxr.cs is), because System.Drawing is Windows-only on .NET 6 and later,
// pixel loops in PowerShell take seconds per picture, and Godot's Image would mean setting up the engine to read a
// folder of JSON. PNG only, written and read here: RGBA output; input 8-bit grey, RGB, palette, grey+alpha or RGBA,
// not interlaced (what Godot's screenshots and most editors save).
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;

namespace GodotCi
{
    public static class Png
    {
        static readonly byte[] Signature = { 137, 80, 78, 71, 13, 10, 26, 10 };
        static uint[] _crcTable;

        public static uint Crc32(byte[] data, int offset, int count, uint crc = 0xFFFFFFFF)
        {
            if (_crcTable == null)
            {
                var table = new uint[256];
                for (uint n = 0; n < 256; n++)
                {
                    uint c = n;
                    for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                    table[n] = c;
                }
                _crcTable = table;
            }
            for (int i = offset; i < offset + count; i++) crc = _crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
            return crc;
        }

        static void WriteChunk(Stream output, string type, byte[] data)
        {
            var header = new byte[8];
            WriteUInt32(header, 0, (uint)data.Length);
            for (int i = 0; i < 4; i++) header[4 + i] = (byte)type[i];
            output.Write(header, 0, 8);
            output.Write(data, 0, data.Length);
            uint crc = Crc32(header, 4, 4);
            crc = Crc32(data, 0, data.Length, crc) ^ 0xFFFFFFFF;
            var tail = new byte[4];
            WriteUInt32(tail, 0, crc);
            output.Write(tail, 0, 4);
        }

        static void WriteUInt32(byte[] b, int at, uint v)
        {
            b[at] = (byte)(v >> 24); b[at + 1] = (byte)(v >> 16); b[at + 2] = (byte)(v >> 8); b[at + 3] = (byte)v;
        }

        static uint ReadUInt32(byte[] b, int at) => (uint)(b[at] << 24 | b[at + 1] << 16 | b[at + 2] << 8 | b[at + 3]);

        /// <summary>An 8-bit RGBA PNG, every row unfiltered (filter 0), so the same pixels always make the same file.</summary>
        public static byte[] Encode(byte[] rgba, int width, int height)
        {
            if (rgba.Length != width * height * 4) throw new ArgumentException("rgba must hold width * height * 4 bytes");
            var raw = new byte[(width * 4 + 1) * height];
            for (int y = 0; y < height; y++) Buffer.BlockCopy(rgba, y * width * 4, raw, y * (width * 4 + 1) + 1, width * 4);
            byte[] compressed;
            using (var packed = new MemoryStream())
            {
                using (var z = new ZLibStream(packed, CompressionLevel.Optimal, true)) z.Write(raw, 0, raw.Length);
                compressed = packed.ToArray();
            }
            var ihdr = new byte[13];
            WriteUInt32(ihdr, 0, (uint)width);
            WriteUInt32(ihdr, 4, (uint)height);
            ihdr[8] = 8; ihdr[9] = 6;   // 8 bits, RGBA; compression, filter and interlace methods 0
            using (var file = new MemoryStream())
            {
                file.Write(Signature, 0, Signature.Length);
                WriteChunk(file, "IHDR", ihdr);
                WriteChunk(file, "IDAT", compressed);
                WriteChunk(file, "IEND", new byte[0]);
                return file.ToArray();
            }
        }

        /// <summary>Reads a PNG into 8-bit RGBA. Throws InvalidDataException for anything it cannot read, saying what.</summary>
        public static byte[] Decode(byte[] file, out int width, out int height)
        {
            if (file.Length < 33) throw new InvalidDataException("not a PNG file (too short)");
            for (int i = 0; i < 8; i++) if (file[i] != Signature[i]) throw new InvalidDataException("not a PNG file");
            width = 0; height = 0;
            int depth = 0, colour = -1, interlace = 0;
            byte[] palette = null, paletteAlpha = null;
            var idat = new MemoryStream();
            int at = 8;
            while (at + 12 <= file.Length)
            {
                int length = (int)ReadUInt32(file, at);
                string type = System.Text.Encoding.ASCII.GetString(file, at + 4, 4);
                if (length < 0 || at + 12 + length > file.Length) throw new InvalidDataException("truncated PNG chunk " + type);
                int data = at + 8;
                if (type == "IHDR")
                {
                    width = (int)ReadUInt32(file, data); height = (int)ReadUInt32(file, data + 4);
                    depth = file[data + 8]; colour = file[data + 9]; interlace = file[data + 12];
                }
                else if (type == "PLTE") { palette = new byte[length]; Buffer.BlockCopy(file, data, palette, 0, length); }
                else if (type == "tRNS") { paletteAlpha = new byte[length]; Buffer.BlockCopy(file, data, paletteAlpha, 0, length); }
                else if (type == "IDAT") idat.Write(file, data, length);
                else if (type == "IEND") break;
                at += 12 + length;
            }
            if (width <= 0 || height <= 0) throw new InvalidDataException("PNG without a valid IHDR");
            if (depth != 8) throw new InvalidDataException("a " + depth + "-bit PNG; save it with 8 bits per channel");
            if (interlace != 0) throw new InvalidDataException("an interlaced PNG; save it without interlacing");
            int channels;
            switch (colour)
            {
                case 0: channels = 1; break;
                case 2: channels = 3; break;
                case 3: channels = 1; if (palette == null) throw new InvalidDataException("palette PNG without PLTE"); break;
                case 4: channels = 2; break;
                case 6: channels = 4; break;
                default: throw new InvalidDataException("PNG colour type " + colour);
            }
            if ((long)width * height > 64L * 1024 * 1024) throw new InvalidDataException("PNG larger than 64 megapixels");
            int stride = width * channels;
            var raw = new byte[(stride + 1) * height];
            idat.Position = 0;
            using (var z = new ZLibStream(idat, CompressionMode.Decompress))
            {
                int read = 0, n;
                while (read < raw.Length && (n = z.Read(raw, read, raw.Length - read)) > 0) read += n;
                if (read < raw.Length) throw new InvalidDataException("PNG image data is truncated");
            }
            var pixels = new byte[stride * height];
            for (int y = 0; y < height; y++)
            {
                int filter = raw[y * (stride + 1)];
                int src = y * (stride + 1) + 1, dst = y * stride, prior = dst - stride;
                for (int x = 0; x < stride; x++)
                {
                    int a = x >= channels ? pixels[dst + x - channels] : 0;
                    int b = y > 0 ? pixels[prior + x] : 0;
                    int c = x >= channels && y > 0 ? pixels[prior + x - channels] : 0;
                    int v = raw[src + x];
                    switch (filter)
                    {
                        case 0: break;
                        case 1: v += a; break;
                        case 2: v += b; break;
                        case 3: v += (a + b) >> 1; break;
                        case 4:
                            int p = a + b - c, pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c);
                            v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
                            break;
                        default: throw new InvalidDataException("PNG row filter " + filter);
                    }
                    pixels[dst + x] = (byte)v;
                }
            }
            var rgba = new byte[width * height * 4];
            for (int i = 0, n = width * height; i < n; i++)
            {
                int s = i * channels, d = i * 4;
                switch (colour)
                {
                    case 0: rgba[d] = rgba[d + 1] = rgba[d + 2] = pixels[s]; rgba[d + 3] = 255; break;
                    case 4: rgba[d] = rgba[d + 1] = rgba[d + 2] = pixels[s]; rgba[d + 3] = pixels[s + 1]; break;
                    case 2: rgba[d] = pixels[s]; rgba[d + 1] = pixels[s + 1]; rgba[d + 2] = pixels[s + 2]; rgba[d + 3] = 255; break;
                    case 6: Buffer.BlockCopy(pixels, s, rgba, d, 4); break;
                    case 3:
                        int k = pixels[s];
                        if (3 * k + 2 >= palette.Length) throw new InvalidDataException("PNG palette index out of range");
                        rgba[d] = palette[3 * k]; rgba[d + 1] = palette[3 * k + 1]; rgba[d + 2] = palette[3 * k + 2];
                        rgba[d + 3] = paletteAlpha != null && k < paletteAlpha.Length ? paletteAlpha[k] : (byte)255;
                        break;
                }
            }
            return rgba;
        }

        /// <summary>Width and height from the IHDR, without decoding the picture.</summary>
        public static int[] Size(byte[] file)
        {
            if (file.Length < 24) throw new InvalidDataException("not a PNG file (too short)");
            for (int i = 0; i < 8; i++) if (file[i] != Signature[i]) throw new InvalidDataException("not a PNG file");
            return new[] { (int)ReadUInt32(file, 16), (int)ReadUInt32(file, 20) };
        }
    }

    public static class Heatmap
    {
        // ColorBrewer's YlOrRd, light to dark: sequential, readable for the common colour-vision deficiencies, and dark
        // enough at the top to stand out on a light screenshot.
        static readonly byte[][] Ramp =
        {
            new byte[] { 255, 237, 160 }, new byte[] { 254, 178, 76 }, new byte[] { 253, 141, 60 },
            new byte[] { 240, 59, 32 }, new byte[] { 189, 0, 38 },
        };
        public static readonly byte[] Empty = { 20, 23, 28 };

        /// <summary>The ramp's colour for count / max (0 to 1], blended between the stops.</summary>
        public static byte[] Colour(double t)
        {
            t = Math.Max(0, Math.Min(1, t)) * (Ramp.Length - 1);
            int i = Math.Min((int)Math.Floor(t), Ramp.Length - 2);
            double f = t - i;
            var c = new byte[3];
            for (int k = 0; k < 3; k++) c[k] = (byte)Math.Round(Ramp[i][k] + (Ramp[i + 1][k] - Ramp[i][k]) * f);
            return c;
        }

        /// <summary>
        /// Draws counts (row-major, cols × rows cells of `cell` world units from origin u0, v0) into a width × height
        /// picture that shows the world rectangle [minU, maxU) × [minV, maxV), v growing downwards. Each pixel takes the cell
        /// under its centre. Cells with nothing stay the background, or dark without one; the rest take the ramp's colour
        /// for count / max, opaque, or at `opacity` over a background.
        /// </summary>
        public static byte[] Render(int[] counts, int cols, int rows, double u0, double v0, double cell,
            double minU, double minV, double maxU, double maxV, int width, int height, byte[] background, double opacity)
        {
            if (counts.Length != cols * rows) throw new ArgumentException("counts must hold cols * rows values");
            int max = 0;
            foreach (int c in counts) max = Math.Max(max, c);
            var rgba = background != null ? (byte[])background.Clone() : new byte[width * height * 4];
            var colours = new Dictionary<int, byte[]>();
            for (int y = 0; y < height; y++)
            {
                double v = minV + (y + 0.5) / height * (maxV - minV);
                int row = (int)Math.Floor((v - v0) / cell);
                for (int x = 0; x < width; x++)
                {
                    int d = (y * width + x) * 4;
                    double u = minU + (x + 0.5) / width * (maxU - minU);
                    int col = (int)Math.Floor((u - u0) / cell);
                    int count = col >= 0 && col < cols && row >= 0 && row < rows ? counts[row * cols + col] : 0;
                    if (count == 0)
                    {
                        if (background == null) { rgba[d] = Empty[0]; rgba[d + 1] = Empty[1]; rgba[d + 2] = Empty[2]; rgba[d + 3] = 255; }
                        continue;
                    }
                    if (!colours.TryGetValue(count, out var colour)) colours[count] = colour = Colour((double)count / max);
                    if (background == null)
                    {
                        rgba[d] = colour[0]; rgba[d + 1] = colour[1]; rgba[d + 2] = colour[2]; rgba[d + 3] = 255;
                    }
                    else
                    {
                        for (int k = 0; k < 3; k++) rgba[d + k] = (byte)Math.Round(rgba[d + k] * (1 - opacity) + colour[k] * opacity);
                        rgba[d + 3] = 255;
                    }
                }
            }
            return rgba;
        }
    }
}
