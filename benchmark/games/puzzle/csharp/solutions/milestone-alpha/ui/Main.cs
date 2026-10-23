namespace Frostmote;

using Godot;

/// <summary>
/// The title menu, and the holder of whatever screen is showing: the level select, the game, settings or victory.
/// Screens are children of Main rather than scene changes, so the save and the levels live in one place.
/// </summary>
public partial class Main : Control
{
    private PackedScene _gameScene = null!;
    private PackedScene _levelSelectScene = null!;
    private PackedScene _settingsScene = null!;
    private PackedScene _victoryScene = null!;
    private Node? _screen;
    private Control _menu = null!;
    private Label _title = null!;
    private Button _start = null!;
    private Button _settings = null!;
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
        _victoryScene = GD.Load<PackedScene>("res://ui/victory.tscn");
        _menu = GetNode<Control>("Menu");
        _title = GetNode<Label>("Menu/Title");
        _start = GetNode<Button>("Menu/StartButton");
        _settings = GetNode<Button>("Menu/SettingsButton");
        _quit = GetNode<Button>("Menu/QuitButton");
        _version = GetNode<Label>("Menu/VersionLabel");

        Options = LaunchOptions.FromCommandLine();
        Store = new SaveStore(ProjectSettings.GlobalizePath("user://save.json")) { Enabled = !Options.NoSave };
        Save = Store.Read();
        ApplySettings(Save);
        // Read here, not when a level starts, so a build without its levels fails at once (export -Run catches it).
        Levels = Levels.FromFile();
        _start.Pressed += ShowLevelSelect;
        _settings.Pressed += ShowSettings;
        _quit.Pressed += () => GetTree().Quit();
        RefreshText();
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
        _quit.Text = Tr("MENU_QUIT");
        _version.Text = TextFormat.Fill(Tr("MENU_VERSION"), ProjectSettings.GetSetting("application/config/version", "").AsString());
    }

    public static void ApplySettings(SaveData save)
    {
        TranslationServer.SetLocale(save.Locale);
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max(save.Volume, 0.0001f)));
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

    public void StartLevel(int id)
    {
        var game = _gameScene.Instantiate<Game>();
        game.Name = "Game";
        game.Setup(Levels, Options, id);
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

    /// <summary>A solved level is kept with its moves.</summary>
    private void OnLevelSolved(int level, int moves)
    {
        Progress.Record(Save, level, moves);
        Store.Write(Save);
    }

    private void OnFinished(bool victory)
    {
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
}
