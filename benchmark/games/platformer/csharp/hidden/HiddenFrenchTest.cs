namespace GlowmossRidge.Tests;

using System;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus included, and has five levels.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenFrenchTest
{
    [AfterTest]
    public void BackToEnglish()
    {
        TranslationServer.SetLocale("en");
    }

    [TestCase]
    public void Hidden_french_is_loaded()
    {
        AssertThat(Array.IndexOf(TranslationServer.GetLoadedLocales(), "fr") >= 0).IsTrue();
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
    public void Hidden_five_levels()
    {
        AssertThat(Levels.FromFiles().Count >= 5).IsTrue();
    }
}
