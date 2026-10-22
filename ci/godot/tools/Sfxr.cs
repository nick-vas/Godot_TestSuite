// Sound effects from a seed: a C# port of the Bfxr synth of bfxr2 (https://github.com/increpare/bfxr2, engine 1.0.4).
//
// The synthesis (Bfxr_DSP.js) is bfxr2's modification of Thomas Vian's SfxrSynth, itself after DrPetter's sfxr:
//
//   SfxrSynth
//   Copyright 2010 Thomas Vian
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.
//
// The parameters and presets (Bfxr.js) and the seeded random numbers (bfxrlib.js) are bfxr2's: MIT License,
// Copyright (c) 2021 Stephen Lavelle. The three wavetables are Adventure Kid Waveforms (AKWF), CC0 1.0.
//
// The licence texts are in this kit: ci/godot/templates/licences/Apache-2.0.txt and MIT.txt (with the copyright
// lines above).
//
// Changes for this kit: translated from JavaScript to C#; the random numbers come from an explicit seeded generator
// (the same mulberry32 and FNV-1a seed that bfxrlib.js installs as Math.random), so a seed always gives the same sound;
// samples beyond the last one the JavaScript stores are dropped the same way; pickup_coin follows bfxr's template, as
// its editor and library do; WAV writing and a gentler mutation are this kit's own. tests/Test-Sfx.ps1 compares the samples with bfxrlib.js when it is at hand (docs/audio.md).
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace GodotCi
{
public sealed class SfxRandom
{
    uint _state;

    /// <summary>bfxrlib's generator: a number in [0, 1) picks the starting state.</summary>
    public SfxRandom(double seed01) { _state = (uint)Math.Floor(seed01 * 4294967295.0); }

    public double Next()
    {
        unchecked
        {
            _state += 0x6D2B79F5;
            uint t = (_state ^ (_state >> 15)) * (1u | _state);
            t = (t + ((t ^ (t >> 7)) * (61u | t))) ^ t;
            return (t ^ (t >> 14)) / 4294967296.0;
        }
    }

    /// <summary>bfxrlib's seed: FNV-1a over "number:12345" or "string:jump", as a number in [0, 1).</summary>
    public static double SeedOf(string text, bool isNumber)
    {
        unchecked
        {
            uint hash = 2166136261;
            foreach (char c in (isNumber ? "number:" : "string:") + text) hash = (hash ^ c) * 16777619;
            return hash / 4294967296.0;
        }
    }
}

public static class Sfxr
{
    public const int SampleRate = 44100;
    public const string EngineVersion = "1.0.4";

    // name, default, min, max (Bfxr.js); waveType is a choice from 0 to 11.
    public static readonly (string Name, double Default, double Min, double Max)[] Parameters = new[]
    {
        ("masterVolume", 0.5, 0.0, 1.0), ("waveType", 0.0, 0.0, 11.0),
        ("attackTime", 0.0, 0.0, 1.0), ("sustainTime", 0.3, 0.0, 1.0), ("sustainPunch", 0.0, 0.0, 1.0), ("decayTime", 0.4, 0.03, 1.0),
        ("compressionAmount", 0.0, 0.0, 1.0), ("frequency_start", 0.3, 0.0, 1.0), ("frequency_slide", 0.0, -0.5, 0.5),
        ("frequency_acceleration", 0.0, -1.0, 1.0), ("min_frequency_relative_to_starting_frequency", 0.0, 0.0, 0.99),
        ("vibratoDepth", 0.0, 0.0, 1.0), ("vibratoSpeed", 0.0, 0.0, 1.0), ("pitch_jump_repeat_speed", 0.0, 0.0, 1.0),
        ("pitch_jump_amount", 0.0, -1.0, 1.0), ("pitch_jump_onset_percent", 0.0, 0.0, 1.0), ("pitch_jump_2_amount", 0.0, -1.0, 1.0),
        ("pitch_jump_onset2_percent", 0.0, 0.0, 1.0), ("overtones", 0.0, 0.0, 1.0), ("overtoneFalloff", 0.0, 0.0, 1.0),
        ("squareDuty", 0.0, 0.0, 0.99), ("dutySweep", 0.0, -1.0, 1.0), ("repeatSpeed", 0.0, 0.0, 1.0),
        ("flangerOffset", 0.0, -1.0, 1.0), ("flangerSweep", 0.0, -1.0, 1.0), ("lpFilterCutoff", 1.0, 0.01, 1.0),
        ("lpFilterCutoffSweep", 0.0, -1.0, 1.0), ("lpFilterResonance", 0.0, 0.0, 1.0), ("hpFilterCutoff", 0.0, 0.0, 1.0),
        ("hpFilterCutoffSweep", 0.0, -1.0, 1.0), ("bitCrush", 0.0, 0.0, 1.0), ("bitCrushSweep", 0.0, -1.0, 1.0),
    };

    public static readonly string[] Presets = { "pickup_coin", "laser_shoot", "explosion", "powerup", "hit_hurt", "jump", "blip_select" };

    // Wave types by bfxr's names.
    const int Square = 0, Saw = 1, Sine = 2, White = 3, Bitnoise = 9, Whistle = 7, FmSyn = 10, VoiceWave = 11;

    public static Dictionary<string, double> Defaults()
    {
        var p = new Dictionary<string, double>();
        foreach (var info in Parameters) p[info.Name] = info.Default;
        return p;
    }

    static void Set(Dictionary<string, double> p, string name, double value)
    {
        foreach (var info in Parameters)
        {
            if (info.Name != name) continue;
            if (name == "waveType") { if (value >= 0 && value <= 11 && value == Math.Floor(value)) p[name] = value; return; }
            p[name] = double.IsFinite(value) ? Math.Max(info.Min, Math.Min(value, info.Max)) : info.Default;
            return;
        }
        throw new ArgumentException("unknown parameter " + name);
    }

    /// <summary>Values out of range are clamped and unknown names refused, as bfxr's set_param does.</summary>
    public static Dictionary<string, double> Normalize(IDictionary<string, double> input)
    {
        var p = Defaults();
        foreach (var kv in input) Set(p, kv.Key, kv.Value);
        return p;
    }

    /// <summary>One of <see cref="Presets"/>, its numbers drawn from the generator in bfxr's order.</summary>
    public static Dictionary<string, double> Preset(string name, double seed01)
    {
        var rng = new SfxRandom(seed01);
        Func<double> R = rng.Next;
        var p = Defaults();
        Func<string, double> G = n => p[n];
        Action<string, double> S = (n, v) => Set(p, n, v);
        Func<int[], int> Pick = waves => waves[(int)Math.Floor(R() * waves.Length)];
        switch (name)
        {
            case "pickup_coin":
                // bfxr replaces its coded coin with a template (templates/Bfxr/pickup_coin.bcol): one draw picks a
                // variety, then one draw per parameter, in this order, picks a value in its range (or one of its
                // waves). The volume's draw is spent but the volume stays: bfxr locks it.
                var variety = PickupCoin[R() * 2 <= 1 ? 0 : 1];
                foreach (var (param, values) in variety)
                {
                    double value;
                    if (param == "waveType") value = values[(int)Math.Floor(R() * values.Length)];
                    else
                    {
                        double lo = values[0], hi = values[0];
                        foreach (var v in values) { lo = Math.Min(lo, v); hi = Math.Max(hi, v); }
                        value = R() * (hi - lo) + lo;
                    }
                    if (param != "masterVolume") S(param, value);
                }
                break;
            case "laser_shoot":
                S("waveType", (int)(R() * 3));
                if (G("waveType") == 2 && R() < 0.5) S("waveType", (int)(R() * 2));
                if (R() < 0.33)
                {
                    S("frequency_start", 0.1 + R() * 0.5);
                    S("min_frequency_relative_to_starting_frequency", R() * 0.1);
                    S("frequency_slide", -0.35 - R() * 0.3);
                }
                else
                {
                    S("frequency_start", 0.5 + R() * 0.5);
                    S("min_frequency_relative_to_starting_frequency", G("frequency_start") - 0.2 - R() * 0.6);
                    if (G("min_frequency_relative_to_starting_frequency") < 0.2) S("min_frequency_relative_to_starting_frequency", 0.2);
                    S("frequency_slide", -0.15 - R() * 0.2);
                }
                if (G("frequency_start") < 0.15)
                {
                    S("min_frequency_relative_to_starting_frequency", 0);
                    S("frequency_slide", -0.1 - R() * 0.1);
                }
                if (R() < 0.5) { S("squareDuty", R() * 0.5); S("dutySweep", R() * 0.2); }
                else { S("squareDuty", 0.4 + R() * 0.5); S("dutySweep", -R() * 0.7); }
                S("sustainTime", 0.1 + R() * 0.2);
                S("decayTime", R() * 0.4);
                if (R() < 0.5) S("sustainPunch", R() * 0.3);
                if (R() < 0.33) { S("flangerOffset", R() * 0.2); S("flangerSweep", -R() * 0.2); }
                if (R() < 0.5) S("hpFilterCutoff", R() * 0.3);
                break;
            case "explosion":
                S("waveType", R() < 0.5 ? White : Bitnoise);
                if (R() < 0.5) { S("frequency_start", 0.1 + R() * 0.4); S("frequency_slide", -0.1 + R() * 0.4); }
                else { S("frequency_start", 0.2 + R() * 0.7); S("frequency_slide", -0.2 - R() * 0.2); }
                S("frequency_start", G("frequency_start") * G("frequency_start"));
                if (R() < 0.2) S("frequency_slide", 0.0);
                if (R() < 0.33) S("repeatSpeed", 0.3 + R() * 0.5);
                S("sustainTime", 0.1 + R() * 0.3);
                S("decayTime", R() * 0.5);
                S("sustainPunch", 0.2 + R() * 0.6);
                if (R() < 0.5) { S("flangerOffset", -0.3 + R() * 0.9); S("flangerSweep", -R() * 0.3); }
                if (R() < 0.33) { S("pitch_jump_onset_percent", 0.6 + R() * 0.3); S("pitch_jump_amount", 0.8 - R() * 1.6); }
                break;
            case "powerup":
                if (R() < 0.5) S("waveType", Saw); else S("squareDuty", R() * 0.6);
                if (R() < 0.5) { S("frequency_start", 0.2 + R() * 0.3); S("frequency_slide", 0.1 + R() * 0.4); S("repeatSpeed", 0.4 + R() * 0.4); }
                else
                {
                    S("frequency_start", 0.2 + R() * 0.3);
                    S("frequency_slide", 0.05 + R() * 0.2);
                    if (R() < 0.5) { S("vibratoDepth", R() * 0.7); S("vibratoSpeed", R() * 0.6); }
                }
                S("sustainTime", R() * 0.4);
                S("decayTime", 0.1 + R() * 0.4);
                break;
            case "hit_hurt":
                S("waveType", Pick(new[] { White, Bitnoise, Saw, Square, VoiceWave }));
                if (G("waveType") == Square) S("squareDuty", R() * 0.6);
                S("frequency_start", 0.2 + R() * 0.6);
                S("frequency_slide", -0.3 - R() * 0.4);
                S("sustainTime", R() * 0.1);
                S("decayTime", 0.1 + R() * 0.2);
                if (R() < 0.5) S("hpFilterCutoff", R() * 0.3);
                break;
            case "jump":
                S("waveType", Pick(new[] { Square, Saw, FmSyn }));
                S("squareDuty", R() * 0.6);
                S("frequency_start", 0.3 + R() * 0.3);
                S("frequency_slide", 0.1 + R() * 0.2);
                S("sustainTime", 0.1 + R() * 0.3);
                S("decayTime", 0.1 + R() * 0.2);
                if (R() < 0.5) S("hpFilterCutoff", R() * 0.3);
                if (R() < 0.5) S("lpFilterCutoff", 1.0 - R() * 0.6);
                break;
            case "blip_select":
                S("waveType", Pick(new[] { Square, Saw, FmSyn, Whistle }));
                if (G("waveType") == Square) S("squareDuty", R() * 0.6);
                S("frequency_start", 0.2 + R() * 0.4);
                S("sustainTime", 0.1 + R() * 0.1);
                S("decayTime", R() * 0.2);
                S("hpFilterCutoff", 0.1);
                break;
            default:
                throw new ArgumentException("unknown preset " + name + "; use " + string.Join(", ", Presets));
        }
        return p;
    }

    /// <summary>
    /// A variation: each parameter, with even odds, moved by up to <paramref name="amount"/> of its range either way
    /// (bfxrlib's gentle mutation; the editor's also re-rolls the pitch). The wave type and volume stay.
    /// </summary>
    public static Dictionary<string, double> Mutate(IDictionary<string, double> input, double amount, double seed01)
    {
        var rng = new SfxRandom(seed01);
        var p = Normalize(input);
        foreach (var info in Parameters)
        {
            if (info.Name == "waveType" || info.Name == "masterVolume") continue;
            if (rng.Next() < 0.5) continue;
            Set(p, info.Name, p[info.Name] + (rng.Next() - 0.5) * 2 * amount * (info.Max - info.Min));
        }
        return p;
    }

    /// <summary>The samples, mono at 44,100 Hz, between -1 and 1.</summary>
    public static float[] Render(IDictionary<string, double> parameters, double renderSeed01)
    {
        var dsp = new Dsp(Normalize(parameters), new SfxRandom(renderSeed01));
        return dsp.Generate();
    }

    /// <summary>16-bit mono PCM WAV. <paramref name="gain"/> scales the samples first (1: as rendered).</summary>
    public static byte[] Wav(float[] samples, double gain = 1.0)
    {
        using var stream = new MemoryStream();
        using var w = new BinaryWriter(stream, Encoding.ASCII);
        int dataBytes = samples.Length * 2;
        w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + dataBytes); w.Write(Encoding.ASCII.GetBytes("WAVE"));
        w.Write(Encoding.ASCII.GetBytes("fmt ")); w.Write(16); w.Write((short)1); w.Write((short)1);
        w.Write(SampleRate); w.Write(SampleRate * 2); w.Write((short)2); w.Write((short)16);
        w.Write(Encoding.ASCII.GetBytes("data")); w.Write(dataBytes);
        // 32767, not 32768: a full-scale sample must not wrap round to the most negative value (a click).
        foreach (float s in samples) w.Write((short)Math.Round(Math.Max(-1.0, Math.Min(1.0, s * gain)) * 32767.0));
        w.Flush();
        return stream.ToArray();
    }

    /// <summary>The largest absolute sample.</summary>
    public static double Peak(float[] samples)
    {
        double peak = 0;
        foreach (float s in samples) peak = Math.Max(peak, Math.Abs(s));
        return peak;
    }

    sealed class Dsp
    {
        const double MinLength = 0.18;
        const int LoResNoisePeriod = 8;

        readonly Dictionary<string, double> p;
        readonly SfxRandom rng;

        double frequency_period_samples, frequency_maxPeriod_samples, masterVolume, sustainPunch, phase, minFrequency;
        bool muted, filters, flanger, pitch_jump_reached, pitch_jump_2_reached, lpFilterOn;
        int waveType;
        double overtones, overtoneFalloff, compression_factor, vibratoPhase, vibratoSpeed, vibratoAmplitude;
        double envelopeVolume, envelopeTime, envelopeLength0, envelopeLength1, envelopeLength2, attack_length_samples;
        double envelope_full_length_samples, bitcrush_freq_sweep, bitcrush_phase, bitcrush_last, bitcrush_freq;
        double envelopeOverLength0, envelopeOverLength1, envelopeOverLength2, flangerDeltaOffset, flangerOffset;
        int envelopeStage, flangerPos, flangerInt, oneBitNoiseState;
        double oneBitNoise;
        readonly float[] flangerBuffer = new float[1024], noiseBuffer = new float[32], loResNoiseBuffer = new float[32];
        double pitch_jump_repeat_length_samples, pitch_jump_amount, pitch_jump_2_amount, pitch_jump_current_timestamp_samples;
        double pitch_jump_timestamp_sample, pitch_jump_2_timestamp_sample, slide, frequency_acceleration;
        double squareDuty, dutySweep, lpFilterCutoff, lpFilterDeltaCutoff, lpFilterDamping, lpFilterPos, lpFilterDeltaPos;
        double lpFilterOldPos, hpFilterPos, hpFilterCutoff, hpFilterDeltaCutoff, param_reset_period_samples;
        double param_reset_current_timestamp_samples, periodTemp;

        public Dsp(Dictionary<string, double> parameters, SfxRandom random)
        {
            p = parameters;
            rng = random;
            Reset(true);
        }

        static double Lerp(double a, double b, double t) => a + t * (b - a);

        void Reset(bool total)
        {
            frequency_period_samples = 100.0 / (p["frequency_start"] * p["frequency_start"] + 0.001);
            double minimum_frequency = Math.Pow(p["min_frequency_relative_to_starting_frequency"], 0.4) * p["frequency_start"];
            frequency_maxPeriod_samples = 100.0 / (minimum_frequency * minimum_frequency + 0.001);
            pitch_jump_reached = false;
            pitch_jump_2_reached = false;

            if (total)
            {
                masterVolume = p["masterVolume"] * p["masterVolume"];
                waveType = (int)p["waveType"];
                if (p["sustainTime"] < 0.01) p["sustainTime"] = 0.01;
                double totalTime = p["attackTime"] + p["sustainTime"] + p["decayTime"];
                if (totalTime < MinLength)
                {
                    double multiplier = MinLength / totalTime;
                    p["attackTime"] *= multiplier; p["sustainTime"] *= multiplier; p["decayTime"] *= multiplier;
                }
                sustainPunch = p["sustainPunch"];
                phase = 0;
                minFrequency = p["min_frequency_relative_to_starting_frequency"];
                muted = false;
                overtones = p["overtones"] * 10;
                overtoneFalloff = p["overtoneFalloff"];
                compression_factor = 1 / (1 + 4 * p["compressionAmount"]);
                filters = p["lpFilterCutoff"] != 1.0 || p["hpFilterCutoff"] != 0.0;
                vibratoPhase = 0.0;
                vibratoSpeed = p["vibratoSpeed"] * p["vibratoSpeed"] * 0.01;
                vibratoAmplitude = p["vibratoDepth"] * 0.5;
                envelopeVolume = 0.0;
                envelopeStage = 0;
                envelopeTime = 0;
                envelopeLength0 = p["attackTime"] * p["attackTime"] * 100000.0;
                envelopeLength1 = p["sustainTime"] * p["sustainTime"] * 100000.0;
                envelopeLength2 = p["decayTime"] * p["decayTime"] * 100000.0 + 10;
                attack_length_samples = envelopeLength0;
                envelope_full_length_samples = envelopeLength0 + envelopeLength1 + envelopeLength2;
                bitcrush_freq_sweep = -p["bitCrushSweep"] / envelope_full_length_samples;
                bitcrush_phase = 0;
                bitcrush_last = 0;
                envelopeOverLength0 = 1.0 / envelopeLength0;
                envelopeOverLength1 = 1.0 / envelopeLength1;
                envelopeOverLength2 = 1.0 / envelopeLength2;
                flanger = p["flangerOffset"] != 0.0 || p["flangerSweep"] != 0.0;
                flangerDeltaOffset = p["flangerSweep"] * p["flangerSweep"] * p["flangerSweep"] * 0.2;
                flangerPos = 0;
                oneBitNoiseState = 1 << 14;
                oneBitNoise = 0;
                Array.Clear(flangerBuffer);
                for (int i = 0; i < 32; i++) noiseBuffer[i] = (float)(rng.Next() * 2.0 - 1.0);
                for (int i = 0; i < 32; i++) loResNoiseBuffer[i] = (i % LoResNoisePeriod) == 0 ? (float)(rng.Next() * 2.0 - 1.0) : loResNoiseBuffer[i - 1];

                pitch_jump_repeat_length_samples = Lerp(envelope_full_length_samples, Sfxr.SampleRate / 50.0, p["pitch_jump_repeat_speed"]) + 32;
                double window = pitch_jump_repeat_length_samples > 0 ? pitch_jump_repeat_length_samples : envelope_full_length_samples;
                pitch_jump_amount = p["pitch_jump_amount"] > 0.0 ? 1.0 - p["pitch_jump_amount"] * p["pitch_jump_amount"] * 0.9 : 1.0 + p["pitch_jump_amount"] * p["pitch_jump_amount"] * 10.0;
                pitch_jump_2_amount = p["pitch_jump_2_amount"] > 0.0 ? 1.0 - p["pitch_jump_2_amount"] * p["pitch_jump_2_amount"] * 0.9 : 1.0 + p["pitch_jump_2_amount"] * p["pitch_jump_2_amount"] * 10.0;
                pitch_jump_current_timestamp_samples = 0;
                pitch_jump_timestamp_sample = p["pitch_jump_onset_percent"] == 1.0 ? 0 : p["pitch_jump_onset_percent"] * window + 32;
                pitch_jump_2_timestamp_sample = p["pitch_jump_onset2_percent"] == 1.0 ? 0 : p["pitch_jump_onset2_percent"] * window + 32;

                if (waveType == Bitnoise)
                {
                    // Bitnoise reads the pitch knobs differently (bfxr remaps them around the middle of their ranges).
                    double sf = 0.5 + p["frequency_start"];
                    double mf = 0.495 + p["min_frequency_relative_to_starting_frequency"] / 0.99;
                    frequency_period_samples = 100.0 / (sf * sf + 0.001);
                    frequency_maxPeriod_samples = 100.0 / (mf * mf + 0.001);
                }
            }

            slide = 1.0 - p["frequency_slide"] * p["frequency_slide"] * p["frequency_slide"] * 0.01;
            frequency_acceleration = -p["frequency_acceleration"] * p["frequency_acceleration"] * p["frequency_acceleration"] * 0.000001;
            flangerOffset = p["flangerOffset"] * p["flangerOffset"] * 1020.0;
            if (p["flangerOffset"] < 0.0) flangerOffset = -flangerOffset;
            bitcrush_freq = 1 - Math.Pow(p["bitCrush"], 1.0 / 3.0);
            // The JavaScript reads `(waveType)|0 == 0`, which is always true, so the duty is set for every wave.
            squareDuty = 0.5 - p["squareDuty"] * 0.5;
            dutySweep = -p["dutySweep"] * 0.00005;
            lpFilterCutoff = p["lpFilterCutoff"] * p["lpFilterCutoff"] * p["lpFilterCutoff"] * 0.1;
            lpFilterDeltaCutoff = 1.0 + p["lpFilterCutoffSweep"] * 0.0001;
            lpFilterDamping = 5.0 / (1.0 + p["lpFilterResonance"] * p["lpFilterResonance"] * 20.0) * (0.01 + lpFilterCutoff);
            if (lpFilterDamping > 0.8) lpFilterDamping = 0.8;
            lpFilterDamping = 1.0 - lpFilterDamping;
            lpFilterOn = p["lpFilterCutoff"] != 1.0;
            lpFilterPos = 0.0;
            lpFilterDeltaPos = 0.0;
            hpFilterPos = 0.0;
            hpFilterCutoff = p["hpFilterCutoff"] * p["hpFilterCutoff"] * 0.1;
            hpFilterDeltaCutoff = 1.0 + p["hpFilterCutoffSweep"] * 0.0003;
            param_reset_period_samples = Lerp(envelope_full_length_samples, Sfxr.SampleRate / 10.0, p["repeatSpeed"]);
            param_reset_current_timestamp_samples = 0;
        }

        static double SineApprox(double pos)
        {
            pos = pos > 0.5 ? (pos - 1.0) * 6.28318531 : pos * 6.28318531;
            double s = pos < 0 ? 1.27323954 * pos + .405284735 * pos * pos : 1.27323954 * pos - 0.405284735 * pos * pos;
            return s < 0 ? .225 * (s * -s - s) + s : .225 * (s * s - s) + s;
        }

        static double Table(ushort[] table, double tempphase, double period) =>
            table[((int)(tempphase * 256 / (int)period)) % 256] / 32768.0 - 1;

        public float[] Generate()
        {
            double length = envelope_full_length_samples;
            int stored = (int)length;   // a Float32Array of a fractional length holds the whole part
            var buffer = new float[stored];
            int end = stored;
            int last_nonzero = -1;
            bool finished = false;
            for (int i = 0; i < length; i++)
            {
                if (finished) break;
                if (param_reset_period_samples != 0)
                {
                    param_reset_current_timestamp_samples++;
                    if (param_reset_current_timestamp_samples >= param_reset_period_samples)
                    {
                        param_reset_current_timestamp_samples = 0;
                        Reset(false);
                    }
                }
                pitch_jump_current_timestamp_samples++;
                if (pitch_jump_current_timestamp_samples >= pitch_jump_repeat_length_samples)
                {
                    pitch_jump_current_timestamp_samples = 0;
                    if (pitch_jump_reached) { frequency_period_samples /= pitch_jump_amount; pitch_jump_reached = false; }
                    if (pitch_jump_2_reached) { frequency_period_samples /= pitch_jump_2_amount; pitch_jump_2_reached = false; }
                }
                if (!pitch_jump_reached && pitch_jump_current_timestamp_samples >= pitch_jump_timestamp_sample)
                {
                    pitch_jump_reached = true;
                    frequency_period_samples *= pitch_jump_amount;
                }
                if (!pitch_jump_2_reached && pitch_jump_current_timestamp_samples >= pitch_jump_2_timestamp_sample)
                {
                    frequency_period_samples *= pitch_jump_2_amount;
                    pitch_jump_2_reached = true;
                }

                slide += frequency_acceleration;
                frequency_period_samples *= slide;
                if (frequency_period_samples > frequency_maxPeriod_samples)
                {
                    frequency_period_samples = frequency_maxPeriod_samples;
                    if (minFrequency > 0.0) muted = true;
                }
                periodTemp = frequency_period_samples;
                if (vibratoAmplitude > 0.0)
                {
                    vibratoPhase += vibratoSpeed;
                    periodTemp = frequency_period_samples * (1.0 + Math.Sin(vibratoPhase) * vibratoAmplitude);
                }
                periodTemp = (int)periodTemp;
                if (periodTemp < 8) periodTemp = 8;

                if (waveType == Square)
                {
                    squareDuty += dutySweep;
                    if (squareDuty < 0.0) squareDuty = 0.001;
                    else if (squareDuty > 0.5) squareDuty = 0.5;
                }

                if (++envelopeTime > attack_length_samples)
                {
                    envelopeTime = 0;
                    switch (++envelopeStage)
                    {
                        case 1: attack_length_samples = envelopeLength1; break;
                        case 2: attack_length_samples = envelopeLength2; break;
                    }
                }
                switch (envelopeStage)
                {
                    case 0: envelopeVolume = envelopeTime * envelopeOverLength0; break;
                    case 1: envelopeVolume = 1.0 + (1.0 - envelopeTime * envelopeOverLength1) * 2.0 * sustainPunch; break;
                    case 2: envelopeVolume = 1.0 - envelopeTime * envelopeOverLength2; break;
                    case 3: envelopeVolume = 0.0; finished = true; break;
                }

                if (flanger)
                {
                    flangerOffset += flangerDeltaOffset;
                    flangerInt = (int)flangerOffset;
                    if (flangerInt < 0) flangerInt = -flangerInt;
                    else if (flangerInt > 1023) flangerInt = 1023;
                }
                if (filters && hpFilterDeltaCutoff != 0.0)
                {
                    hpFilterCutoff *= hpFilterDeltaCutoff;
                    if (hpFilterCutoff < 0.00001) hpFilterCutoff = 0.00001;
                    else if (hpFilterCutoff > 0.1) hpFilterCutoff = 0.1;
                }

                double superSample = 0.0;
                for (int j = 0; j < 8; j++)
                {
                    phase++;
                    if (phase >= periodTemp)
                    {
                        phase -= periodTemp;
                        switch (waveType)
                        {
                            case White:
                                for (int n = 0; n < 32; n++) noiseBuffer[n] = (float)(rng.Next() * 2.0 - 1.0);
                                break;
                            case 6:   // tan: refills the low-resolution buffer, which no wave reads (kept for the same random sequence)
                                for (int n = 0; n < 32; n++) loResNoiseBuffer[n] = (n % LoResNoisePeriod) == 0 ? (float)(rng.Next() * 2.0 - 1.0) : loResNoiseBuffer[n - 1];
                                break;
                            case Bitnoise:
                                int feedBit = ((oneBitNoiseState >> 1) & 1) ^ (oneBitNoiseState & 1);
                                oneBitNoiseState = (oneBitNoiseState >> 1) | (feedBit << 14);
                                oneBitNoise = (~oneBitNoiseState & 1) - 0.5;
                                break;
                        }
                    }

                    double sample = 0;
                    double overtonestrength = 1;
                    for (int k = 0; k <= overtones; k++)
                    {
                        double tempphase = (phase * (k + 1)) % periodTemp;
                        switch (waveType)
                        {
                            case Square: sample += overtonestrength * ((tempphase / periodTemp) < squareDuty ? 0.5 : -0.5); break;
                            case Saw: sample += overtonestrength * (1.0 - (tempphase / periodTemp) * 2.0); break;
                            case Sine: sample += overtonestrength * SineApprox(tempphase / periodTemp); break;
                            case White: sample += overtonestrength * noiseBuffer[((int)(tempphase * 32 / (int)periodTemp)) % 32]; break;
                            case 4: sample += overtonestrength * (Math.Abs(1 - (tempphase / periodTemp) * 2) - 1); break;
                            case 5: sample += overtonestrength * Table(Rasp, tempphase, periodTemp); break;
                            case 6: sample += Math.Tan(Math.PI * tempphase / periodTemp) * overtonestrength; break;
                            case Whistle:
                                sample += overtonestrength * (0.75 * SineApprox(tempphase / periodTemp) + 0.25 * SineApprox(((tempphase * 20) % periodTemp) / periodTemp));
                                break;
                            case 8:
                                double amp = tempphase / periodTemp;
                                sample += overtonestrength * (Math.Abs(1 - amp * amp * 2) - 1);
                                break;
                            case Bitnoise: sample += overtonestrength * oneBitNoise; break;
                            case FmSyn: sample += overtonestrength * Table(FmSynth, tempphase, periodTemp); break;
                            case VoiceWave: sample += overtonestrength * Table(Voice, tempphase, periodTemp); break;
                        }
                        overtonestrength *= 1 - overtoneFalloff;
                    }

                    if (filters)
                    {
                        lpFilterOldPos = lpFilterPos;
                        lpFilterCutoff *= lpFilterDeltaCutoff;
                        if (lpFilterCutoff < 0.0) lpFilterCutoff = 0.0;
                        else if (lpFilterCutoff > 0.1) lpFilterCutoff = 0.1;
                        if (lpFilterOn)
                        {
                            lpFilterDeltaPos += (sample - lpFilterPos) * lpFilterCutoff;
                            lpFilterDeltaPos *= lpFilterDamping;
                        }
                        else
                        {
                            lpFilterPos = sample;
                            lpFilterDeltaPos = 0.0;
                        }
                        lpFilterPos += lpFilterDeltaPos;
                        hpFilterPos += lpFilterPos - lpFilterOldPos;
                        hpFilterPos *= 1.0 - hpFilterCutoff;
                        sample = hpFilterPos;
                    }
                    if (flanger)
                    {
                        flangerBuffer[flangerPos & 1023] = (float)sample;
                        sample += flangerBuffer[(flangerPos - flangerInt + 1024) & 1023];
                        flangerPos = (flangerPos + 1) & 1023;
                    }
                    superSample += sample;
                }

                if (superSample > 8.0) superSample = 8.0;
                else if (superSample < -8.0) superSample = -8.0;

                bitcrush_phase += bitcrush_freq;
                if (bitcrush_phase > 1)
                {
                    bitcrush_phase = 0;
                    bitcrush_last = superSample;
                }
                double crushMultiplier = Lerp(1, 50 * bitcrush_freq, Math.Sqrt(bitcrush_freq));
                bitcrush_freq = Math.Max(Math.Min(bitcrush_freq + crushMultiplier * bitcrush_freq_sweep, 1), 0.00001);
                superSample = bitcrush_last;

                superSample = masterVolume * envelopeVolume * superSample * 0.125;
                superSample = superSample > 0 ? Math.Pow(superSample, compression_factor) : -Math.Pow(-superSample, compression_factor);

                if (muted) { end = Math.Min(i, stored); break; }
                if (Math.Abs(superSample) > 0.2e-2) last_nonzero = i;
                if (i < stored) buffer[i] = (float)Math.Max(-1, Math.Min(superSample, 1));
            }
            if (end < stored) Array.Resize(ref buffer, end);
            if (last_nonzero < buffer.Length - 1)
            {
                last_nonzero = Math.Max(last_nonzero, 10);
                Array.Resize(ref buffer, Math.Min(buffer.Length, last_nonzero + 1));
            }
            return buffer;
        }
    }

    // bfxr's two pickup_coin varieties ("Coin", "Coin2"): each parameter's possible values, in bfxr's order.
    static readonly (string Param, double[] Values)[][] PickupCoin = new[]
    {
        // Coin
        new (string, double[])[] {
            ("masterVolume", new[] { 0.85185 }), ("waveType", new[] { 0.0 }),
            ("attackTime", new[] { 0.0 }), ("sustainTime", new[] { 0.016874472672728978, 0.10333 }),
            ("sustainPunch", new[] { 0.30333, 0.60333 }), ("decayTime", new[] { 0.16312552732727104, 0.50333 }),
            ("compressionAmount", new[] { 0.0 }), ("frequency_start", new[] { 0.4, 0.9 }),
            ("min_frequency_relative_to_starting_frequency", new[] { 0.0 }), ("frequency_slide", new[] { 0.0 }),
            ("frequency_acceleration", new[] { 0.0 }), ("vibratoDepth", new[] { 0.0 }),
            ("vibratoSpeed", new[] { 0.0 }), ("overtones", new[] { 0.0 }),
            ("overtoneFalloff", new[] { 0.0 }), ("pitch_jump_repeat_speed", new[] { 0.0 }),
            ("pitch_jump_amount", new[] { 0.0 }), ("pitch_jump_onset_percent", new[] { 0.0 }),
            ("pitch_jump_2_amount", new[] { 0.0 }), ("pitch_jump_onset2_percent", new[] { 0.0 }),
            ("squareDuty", new[] { 0.0 }), ("dutySweep", new[] { 0.0 }),
            ("repeatSpeed", new[] { 0.0 }), ("flangerOffset", new[] { 0.0 }),
            ("flangerSweep", new[] { 0.0 }), ("lpFilterCutoff", new[] { 1.0 }),
            ("lpFilterCutoffSweep", new[] { 0.0 }), ("lpFilterResonance", new[] { 0.0 }),
            ("hpFilterCutoff", new[] { 0.0 }), ("hpFilterCutoffSweep", new[] { 0.0 }),
            ("bitCrush", new[] { 0.0 }), ("bitCrushSweep", new[] { 0.0 }),
        },
        // Coin2
        new (string, double[])[] {
            ("masterVolume", new[] { 0.85185 }), ("waveType", new[] { 0.0, 2.0, 4.0, 1.0, 7.0, 11.0, 5.0, 10.0 }),
            ("attackTime", new[] { 0.0 }), ("sustainTime", new[] { 0.016874472672728978, 0.10333 }),
            ("sustainPunch", new[] { 0.30333, 0.60333 }), ("decayTime", new[] { 0.16312552732727104, 0.50333 }),
            ("compressionAmount", new[] { 0.0 }), ("frequency_start", new[] { 0.4, 0.9 }),
            ("min_frequency_relative_to_starting_frequency", new[] { 0.0 }), ("frequency_slide", new[] { 0.0, 0.05333 }),
            ("frequency_acceleration", new[] { 0.0, 0.09333 }), ("vibratoDepth", new[] { 0.0 }),
            ("vibratoSpeed", new[] { 0.0 }), ("overtones", new[] { 0.0 }),
            ("overtoneFalloff", new[] { 0.0 }), ("pitch_jump_repeat_speed", new[] { 0.0 }),
            ("pitch_jump_amount", new[] { 0.34667, 0.38667 }), ("pitch_jump_onset_percent", new[] { 0.32667, 0.29333 }),
            ("pitch_jump_2_amount", new[] { 0.0 }), ("pitch_jump_onset2_percent", new[] { 0.0 }),
            ("squareDuty", new[] { 0.0 }), ("dutySweep", new[] { 0.0 }),
            ("repeatSpeed", new[] { 0.0 }), ("flangerOffset", new[] { 0.0 }),
            ("flangerSweep", new[] { 0.0 }), ("lpFilterCutoff", new[] { 1.0 }),
            ("lpFilterCutoffSweep", new[] { 0.0 }), ("lpFilterResonance", new[] { 0.0 }),
            ("hpFilterCutoff", new[] { 0.0 }), ("hpFilterCutoffSweep", new[] { 0.0 }),
            ("bitCrush", new[] { 0.0 }), ("bitCrushSweep", new[] { 0.0 }),
        },
    };

    // Adventure Kid Waveforms (AKWF), CC0 1.0: granular_0044 (Rasp), fmsynth_0012 (FMSyn), hvoice_0012 (Voice).
    static readonly ushort[] Rasp = new ushort[] {
        32869, 33554, 33950, 34774, 35134, 36047, 36319, 37297, 37454, 38494, 38511, 39617, 39443, 40664, 40161, 41814,
        38882, 23368, 22518, 21974, 20997, 20545, 19523, 19169, 18210, 17982, 17163, 17128, 16552, 16803, 16594, 17281,
        17607, 18928, 20002, 22162, 24166, 27270, 30129, 33900, 37194, 41086, 44210, 47679, 50274, 53080, 55123, 57263,
        58843, 60380, 61646, 62635, 63750, 64193, 65294, 65000, 65535, 64171, 65114, 62655, 64487, 59956, 65114, 36210,
        212, 3832, 99, 1558, 1, 510, 0, 197, 120, 547, 1094, 1697, 2901, 3914, 5892, 7586,
        10533, 13157, 17216, 20988, 26107, 30361, 35515, 39386, 43777, 46670, 49891, 51621, 53703, 54463, 55644, 55730,
        56241, 55895, 55900, 55320, 54914, 54268, 53486, 52949, 51761, 51561, 49784, 50399, 47306, 51139, 28999, 14730,
        19959, 17550, 20023, 18982, 20690, 20318, 21655, 21737, 22859, 23286, 24286, 24994, 25914, 26840, 27701, 28756,
        29549, 30623, 31268, 32196, 32566, 33184, 33197, 33422, 33100, 32970, 32677, 32843, 32704, 32820, 32726, 32801,
        32745, 32785, 32759, 32771, 32771, 32760, 32779, 32753, 32784, 32751, 32787, 32749, 32786, 32751, 32785, 32753,
        32782, 32756, 32779, 32759, 32775, 32762, 32773, 32765, 32771, 32768, 32768, 32769, 32767, 32769, 32766, 32770,
        32766, 32769, 32767, 32770, 32767, 32769, 32767, 32770, 32768, 32768, 32768, 32768, 32768, 32768, 32768, 32768,
        32768, 32767, 32767, 32768, 32767, 32768, 32767, 32768, 32769, 32768, 32768, 32768, 32768, 32768, 32768, 32768,
        32767, 32768, 32768, 32768, 32769, 32768, 32768, 32768, 32767, 32768, 32768, 32769, 32768, 32768, 32767, 32769,
        32767, 32769, 32768, 32769, 32767, 32768, 32767, 32768, 32768, 32768, 32768, 32767, 32770, 32767, 32770, 32766,
        32771, 32765, 32772, 32762, 32775, 32757, 32786, 32653, 32303, 32073, 32011, 32104, 32434, 32756, 32768, 32767,
    };
    static readonly ushort[] FmSynth = new ushort[] {
        33063, 33949, 34766, 35596, 36388, 37173, 37929, 38666, 39379, 40067, 40731, 41364, 41976, 42552, 43106, 43625,
        44121, 44580, 45016, 45417, 45794, 46139, 46456, 46745, 47012, 47248, 47464, 47656, 47829, 47980, 48113, 48229,
        48329, 48416, 48490, 48551, 48601, 48643, 48676, 48703, 48723, 48736, 48745, 48748, 48747, 48741, 48728, 48714,
        48693, 48667, 48635, 48595, 48550, 48497, 48436, 48364, 48284, 48193, 48090, 47974, 47846, 47706, 47550, 47380,
        47192, 46991, 46774, 46540, 46289, 46023, 45740, 45441, 45125, 44794, 44446, 44084, 43708, 43316, 42915, 42499,
        42073, 41634, 41187, 40727, 40263, 39791, 39311, 38826, 38337, 37843, 37348, 36850, 36350, 35850, 35350, 34852,
        34356, 33862, 33369, 32882, 32401, 31923, 31451, 30983, 30524, 30072, 29626, 29187, 28759, 28338, 27928, 27527,
        27135, 26754, 26385, 26024, 25678, 25343, 25020, 24708, 24412, 24128, 23858, 23602, 23360, 23134, 22922, 22727,
        22547, 22383, 22235, 22105, 21991, 21894, 21816, 21755, 21711, 21687, 21680, 21693, 21724, 21775, 21845, 21934,
        22044, 22172, 22320, 22487, 22677, 22885, 23113, 23363, 23631, 23921, 24229, 24558, 24908, 25279, 25671, 26081,
        26514, 26965, 27437, 27932, 28443, 28979, 29533, 30108, 30703, 31318, 31954, 32607, 33281, 33975, 34687, 35416,
        36163, 36925, 37703, 38490, 39289, 40096, 40909, 41719, 42527, 43324, 44108, 44867, 45598, 46286, 46925, 47500,
        47996, 48401, 48694, 48858, 48869, 48707, 48340, 47746, 46886, 45734, 44239, 42380, 40091, 37352, 34077, 30264,
        25772, 21005, 16784, 13147, 10049, 7453, 5312, 3592, 2252, 1258, 572, 166, 4, 62, 308, 722,
        1277, 1954, 2735, 3599, 4533, 5522, 6558, 7622, 8712, 9817, 10931, 12049, 13166, 14275, 15381, 16475,
        17558, 18628, 19685, 20730, 21760, 22777, 23780, 24757, 25723, 26697, 27638, 28588, 29498, 30430, 31300, 32236,
    };
    static readonly ushort[] Voice = new ushort[] {
        33078, 34077, 35044, 36007, 36938, 37805, 38590, 39410, 40186, 40979, 41828, 42751, 43765, 44750, 45625, 46506,
        47377, 48459, 49580, 50412, 51254, 52132, 53054, 53969, 55064, 56224, 57157, 57762, 58474, 59326, 60025, 60421,
        60707, 60933, 61192, 61199, 60011, 57771, 55825, 55237, 55020, 53932, 51409, 48089, 45399, 44422, 44106, 42490,
        39350, 35232, 30729, 27122, 25230, 23798, 21402, 18034, 14910, 12701, 11362, 10543, 9717, 8561, 7008, 4596,
        1765, 131, 201, 1146, 2023, 2735, 3299, 3911, 5049, 7131, 9717, 11930, 13324, 14032, 14722, 16044,
        18235, 21043, 24261, 27245, 29408, 31047, 33083, 35737, 38158, 39841, 40886, 41556, 42213, 43245, 44552, 45917,
        47119, 47870, 48264, 48770, 49539, 49925, 49668, 49229, 48873, 48432, 47913, 47384, 46902, 46605, 46302, 45760,
        45142, 44704, 44318, 43802, 43332, 43042, 42636, 41996, 41337, 40780, 40348, 40072, 39783, 39377, 39035, 38729,
        38329, 37958, 37837, 37831, 37639, 37223, 36573, 35566, 34312, 33093, 32117, 31428, 30844, 30079, 29059, 27979,
        27098, 26276, 25428, 24454, 23049, 21274, 19381, 17785, 16557, 15675, 15000, 14446, 13983, 13647, 13422, 13168,
        12982, 12753, 12429, 12068, 11998, 12294, 12943, 13955, 15251, 16750, 18381, 20097, 21804, 23476, 25102, 26674,
        28171, 29696, 31260, 32930, 34804, 36952, 39192, 41282, 43127, 44699, 46099, 47372, 48514, 49476, 50175, 50618,
        50888, 51099, 51305, 51404, 51383, 51221, 50812, 50133, 49166, 47971, 46660, 45347, 44055, 42645, 40991, 39107,
        37176, 35376, 33764, 32251, 30646, 28956, 27272, 25659, 24192, 22866, 21633, 20368, 19107, 17971, 16966, 16123,
        15408, 14840, 14468, 14309, 14374, 14559, 14792, 14960, 15096, 15298, 15643, 16099, 16589, 17068, 17606, 18341,
        19312, 20471, 21661, 22740, 23624, 24392, 25151, 25945, 26715, 27439, 28051, 28700, 29403, 30342, 31272, 32180,
    };
}
}
