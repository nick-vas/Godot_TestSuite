namespace OrbitPatrol;

using Godot;

/// <summary>
/// The title menu, and the holder of whatever screen is showing: the game, settings, credits, game over or victory.
/// Screens are children of Main rather than scene changes, so the save and the loaded tables live in one place.
/// </summary>
public partial class Main : Control
{
    private PackedScene _gameScene = null!;
    private PackedScene _settingsScene = null!;
    private PackedScene _creditsScene = null!;
    private PackedScene _gameOverScene = null!;
    private PackedScene _victoryScene = null!;
    private Node? _screen;
    private Control _menu = null!;
    private Label _title = null!;
    private Button _start = null!;
    private Button _settings = null!;
    private Button _credits = null!;
    private Button _quit = null!;
    private Label _version = null!;

    public LaunchOptions Options { get; private set; } = new();
    public SaveStore Store { get; private set; } = null!;
    public SaveData Save { get; private set; } = new();
    public Waves Waves { get; private set; } = null!;

    public override void _Ready()
    {
        _gameScene = GD.Load<PackedScene>("res://game/game.tscn");
        _settingsScene = GD.Load<PackedScene>("res://ui/settings.tscn");
        _creditsScene = GD.Load<PackedScene>("res://ui/credits.tscn");
        _gameOverScene = GD.Load<PackedScene>("res://ui/game_over.tscn");
        _victoryScene = GD.Load<PackedScene>("res://ui/victory.tscn");
        _menu = GetNode<Control>("Menu");
        _title = GetNode<Label>("Menu/Title");
        _start = GetNode<Button>("Menu/StartButton");
        _settings = GetNode<Button>("Menu/SettingsButton");
        _credits = GetNode<Button>("Menu/CreditsButton");
        _quit = GetNode<Button>("Menu/QuitButton");
        _version = GetNode<Label>("Menu/VersionLabel");

        Options = LaunchOptions.Parse(OS.GetCmdlineUserArgs());
        Store = new SaveStore(ProjectSettings.GlobalizePath("user://save.json")) { Enabled = !Options.NoSave };
        Save = Store.Read();
        ApplySettings(Save);
        // Read here, not when a game starts, so a build without its tables fails at once (export -Run catches it).
        Waves = Waves.FromFiles();
        _start.Pressed += StartGame;
        _settings.Pressed += ShowSettings;
        _credits.Pressed += ShowCredits;
        _quit.Pressed += () => GetTree().Quit();
        RefreshText();
        if (Options.Autoplay)
            StartGame();
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

    public void StartGame()
    {
        var game = _gameScene.Instantiate<Game>();
        game.Name = "Game";
        game.Setup(Waves, Options, Save.Best);
        game.Finished += OnGameFinished;
        game.QuitRequested += ShowMenu;
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

    private void OnGameFinished(bool victory, int points)
    {
        if (points > Save.Best)
        {
            Save.Best = points;
            Store.Write(Save);
        }
        if (Options.Autoplay)
        {
            // A bot run ends here; free the game first so nothing is left in use when the engine exits.
            CallDeferred(MethodName.CloseScreen);
            QuitAfterFrames(3);
            return;
        }
        ResultScreen screen = victory ? _victoryScene.Instantiate<ResultScreen>() : _gameOverScene.Instantiate<ResultScreen>();
        screen.Name = victory ? "Victory" : "GameOver";
        screen.Setup(points, Save.Best);
        screen.MenuPressed += ShowMenu;
        // The game is still inside its own physics step; swap it out once that step is over.
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
