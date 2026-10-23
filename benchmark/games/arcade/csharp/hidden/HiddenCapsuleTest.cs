namespace OrbitPatrol.Tests;

using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the release's fix-store: the header capsule is Steam's 920x430.</summary>
[TestSuite]
public class HiddenCapsuleTest
{
    private static (int Width, int Height) PngSize(string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        if (bytes.Length < 24 || bytes[1] != 0x50)
            return (0, 0);
        int w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        int h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        return (w, h);
    }

    [TestCase]
    public void Hidden_header_capsule_is_920_by_430()
    {
        (int w, int h) = PngSize(Path.Combine(ProjectFiles.Root, "store/steam/header_capsule.png"));
        AssertThat(w).IsEqual(920);
        AssertThat(h).IsEqual(430);
    }
}
