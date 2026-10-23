namespace OrbitPatrol.Tests;

using System;
using System.IO;
using System.Linq;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus included, and level 5 has its boss.</summary>
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
    public void Hidden_level_five_has_the_boss()
    {
        string root = AppContext.BaseDirectory;
        for (var dir = new DirectoryInfo(root); dir != null; dir = dir.Parent)
        {
            if (File.Exists(Path.Combine(dir.FullName, "project.godot")))
            {
                root = dir.FullName;
                break;
            }
        }
        Waves waves = Waves.Parse(File.ReadAllText(Path.Combine(root, "data/enemies.json")), File.ReadAllText(Path.Combine(root, "data/levels.json")));
        AssertThat(waves.LevelCount >= 5).IsTrue();
        AssertThat(waves.Boss(5)).IsNotNull();
    }
}
