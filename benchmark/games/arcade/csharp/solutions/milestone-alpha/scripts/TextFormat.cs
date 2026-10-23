namespace OrbitPatrol;

using System.Globalization;
using System.Text;

/// <summary>
/// Fills the %d and %s of a translated text, in order. The translation table uses Godot's placeholders, which both the
/// GDScript and the C# version of the game share.
/// </summary>
public static class TextFormat
{
    public static string Fill(string pattern, params object[] values)
    {
        var text = new StringBuilder(pattern.Length + 16);
        int next = 0;
        for (int i = 0; i < pattern.Length; i++)
        {
            if (pattern[i] == '%' && i + 1 < pattern.Length && (pattern[i + 1] == 'd' || pattern[i + 1] == 's') && next < values.Length)
            {
                text.Append(System.Convert.ToString(values[next++], CultureInfo.InvariantCulture));
                i++;
            }
            else
            {
                text.Append(pattern[i]);
            }
        }
        return text.ToString();
    }
}
