namespace GlowmossRidge.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the release's fix-store: the library capsule is Steam's 600x900.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenCapsuleTest
{
    private static (int Width, int Height) PngSize(string path)
    {
        byte[] bytes = FileAccess.GetFileAsBytes(path);
        if (bytes.Length < 24 || bytes[1] != 0x50)
            return (0, 0);
        int w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        int h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        return (w, h);
    }

    [TestCase]
    public void Hidden_library_capsule_is_600_by_900()
    {
        (int w, int h) = PngSize("res://store/steam/library_capsule.png");
        AssertThat(w).IsEqual(600);
        AssertThat(h).IsEqual(900);
    }
}
