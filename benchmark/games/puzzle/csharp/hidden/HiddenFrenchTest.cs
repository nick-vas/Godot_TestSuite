namespace Frostmote.Tests;

using System.Linq;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus included, and has eight levels.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenFrenchTest
{
    [AfterTest]
    public void BackToEnglish() => TranslationServer.SetLocale("en");

    [TestCase]
    public void Hidden_french_is_loaded()
    {
        AssertThat(TranslationServer.GetLoadedLocales().Contains("fr")).IsTrue();
    }

    [TestCase]
    public void Hidden_menu_is_translated()
    {
        TranslationServer.SetLocale("en");
        string english = TranslationServer.Translate("MENU_START");
        TranslationServer.SetLocale("fr");
        string french = TranslationServer.Translate("MENU_START");
        AssertThat(french).IsNotEqual("MENU_START");
        AssertThat(french).IsNotEqual(english);
    }

    [TestCase]
    public void Hidden_eight_levels_each_solvable_in_its_par()
    {
        Levels levels = Levels.FromFile();
        AssertThat(levels.LevelCount).IsGreaterEqual(8);
        var solver = new Solver();
        for (int id = 1; id <= 8; id++)
            AssertThat(solver.MinMoves(levels.Board(id))).OverrideFailureMessage($"level {id}").IsEqual(levels.Par(id));
    }
}
