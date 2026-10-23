namespace Frostmote;

using Godot;

/// <summary>
/// The title menu, and the holder of whatever screen is showing: the level select, the game, settings, credits or
/// victory. Screens are children of Main rather than scene changes, so the save and the levels live in one place.
/// </summary>
public partial class Main : Control
{
    private PackedScene _gameScene = null!;
    private PackedScene _levelSelectScene = null!;
    private PackedScene _settingsScene = null!;
    private PackedScene _creditsScene = null!;
    private PackedScene _victoryScene = null!;
    private Node? _screen;
    private Control _menu = null!;
    private Label _title = null!;
    private Button _start = null!;
    private Button _daily = null!;
    private Button _settings = null!;
    private Button _credits = null!;
    private Button _quit = null!;
    private Label _version = null!;

    public LaunchOptions Options { get; private set; } = new();
    public SaveStore Store { get; private set; } = null!;
    public SaveData Save { get; private set; } = new();
    public Levels Levels { get; private set; } = null!;

    public override void _Ready()
    {
        _gameScene = GD.Load<PackedScene>("res://game/game.tscn");
        _levelSelectScene = GD.Load<PackedScene>("res://ui/level_select.tscn");
        _settingsScene = GD.Load<PackedScene>("res://ui/settings.tscn");
        _creditsScene = GD.Load<PackedScene>("res://ui/credits.tscn");
        _victoryScene = GD.Load<PackedScene>("res://ui/victory.tscn");
        _menu = GetNode<Control>("Menu");
        _title = GetNode<Label>("Menu/Title");
        _start = GetNode<Button>("Menu/StartButton");
        _daily = GetNode<Button>("Menu/DailyButton");
        _settings = GetNode<Button>("Menu/SettingsButton");
        _credits = GetNode<Button>("Menu/CreditsButton");
        _quit = GetNode<Button>("Menu/QuitButton");
        _version = GetNode<Label>("Menu/VersionLabel");

        Options = LaunchOptions.FromCommandLine();
        Store = new SaveStore(ProjectSettings.GlobalizePath("user://save.json")) { Enabled = !Options.NoSave };
        Save = Store.Read();
        ApplySettings(Save);
        // Read here, not when a level starts, so a build without its levels fails at once (export -Run catches it).
        Levels = Levels.FromFile();
        _start.Pressed += ShowLevelSelect;
        _daily.Pressed += StartDaily;
        _settings.Pressed += ShowSettings;
        _credits.Pressed += ShowCredits;
        _quit.Pressed += () => GetTree().Quit();
        RefreshText();
        if (Options.Autoplay)
            StartLevel(Options.Level);
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("MENU_TITLE");
        _start.Text = Tr("MENU_START");
        _daily.Text = Tr("MENU_DAILY");
        _settings.Text = Tr("MENU_SETTINGS");
        _credits.Text = Tr("MENU_CREDITS");
        _quit.Text = Tr("MENU_QUIT");
        _version.Text = TextFormat.Fill(Tr("MENU_VERSION"), ProjectSettings.GetSetting("application/config/version", "").AsString());
    }

    public static void ApplySettings(SaveData save)
    {
        TranslationServer.SetLocale(save.Locale);
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max(save.Volume, 0.0001f)));
    }

    /// <summary>Today's daily drift: the date as a number (20261023), or --seed=N when given, so a bug report can name its drift.</summary>
    public static long DailySeed(long optionsSeed)
    {
        if (optionsSeed > 0)
            return optionsSeed;
        Godot.Collections.Dictionary today = Time.GetDateDictFromSystem();
        return today["year"].AsInt64() * 10000 + today["month"].AsInt64() * 100 + today["day"].AsInt64();
    }

    public void ShowLevelSelect()
    {
        var select = _levelSelectScene.Instantiate<LevelSelect>();
        select.Name = "LevelSelect";
        select.Setup(Levels, Save);
        select.LevelChosen += StartLevel;
        select.Closed += ShowMenu;
        ShowScreen(select);
    }

    public void StartLevel(int id) => StartGame(id, 0);

    public void StartDaily() => StartGame(0, DailySeed(Options.RunSeed));

    private void StartGame(int id, long seed)
    {
        var game = _gameScene.Instantiate<Game>();
        game.Name = "Game";
        game.Setup(Levels, Options, id, seed);
        game.LevelSolved += OnLevelSolved;
        game.Finished += OnFinished;
        game.MenuRequested += ShowMenu;
        ShowScreen(game);
    }

    public void ShowSettings()
    {
        var settings = _settingsScene.Instantiate<Settings>();
        settings.Name = "Settings";
        settings.Setup(Save);
        settings.Closed += OnSettingsClosed;
        ShowScreen(settings);
    }

    public void ShowCredits()
    {
        var credits = _creditsScene.Instantiate<Credits>();
        credits.Name = "Credits";
        credits.Closed += ShowMenu;
        ShowScreen(credits);
    }

    public void ShowMenu()
    {
        CloseScreen();
        _menu.Visible = true;
    }

    private void ShowScreen(Node screen)
    {
        CloseScreen();
        _menu.Visible = false;
        _screen = screen;
        AddChild(screen);
    }

    private void CloseScreen()
    {
        if (_screen == null)
            return;
        RemoveChild(_screen);
        _screen.QueueFree();
        _screen = null;
    }

    private void OnSettingsClosed()
    {
        Store.Write(Save);
        ShowMenu();
    }

    /// <summary>A daily drift (level 0) is not progress; a hand-made level is kept with its moves.</summary>
    private void OnLevelSolved(int level, int moves)
    {
        if (level > 0)
        {
            Progress.Record(Save, level, moves);
            Store.Write(Save);
        }
    }

    private void OnFinished(bool victory)
    {
        if (Options.Autoplay)
        {
            // A bot run ends here; free the game first so nothing is left in use when the engine exits.
            CallDeferred(MethodName.CloseScreen);
            QuitAfterFrames(3);
            return;
        }
        if (!victory)
        {
            CallDeferred(MethodName.ShowMenu);
            return;
        }
        var screen = _victoryScene.Instantiate<Victory>();
        screen.Name = "Victory";
        screen.Setup(Progress.TotalMoves(Save));
        screen.MenuPressed += ShowMenu;
        // The game is still inside its own physics step or a button's signal; swap it out once that is over.
        CallDeferred(MethodName.ShowScreen, screen);
    }

    /// <summary>Lets the freed game's sounds stop before the engine exits, so the exit is clean.</summary>
    private async void QuitAfterFrames(int frames)
    {
        for (int i = 0; i < frames; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        GetTree().Quit();
    }
}
