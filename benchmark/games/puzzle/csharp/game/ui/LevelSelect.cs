namespace Frostmote;

using Godot;

/// <summary>The levels, one button each: open once the level before is solved, with the best moves of a solved one.</summary>
public partial class LevelSelect : Control
{
    [Signal]
    public delegate void LevelChosenEventHandler(int id);

    [Signal]
    public delegate void ClosedEventHandler();

    private Levels? _levels;
    private SaveData _save = new();
    private Label _title = null!;
    private GridContainer _grid = null!;
    private Button _back = null!;

    public void Setup(Levels levels, SaveData save)
    {
        _levels = levels;
        _save = save;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _grid = GetNode<GridContainer>("Box/Grid");
        _back = GetNode<Button>("Box/BackButton");
        _levels ??= Levels.FromFile();
        for (int id = 1; id <= _levels.LevelCount; id++)
        {
            int chosen = id;
            var button = new Button
            {
                Name = $"Level{id}Button",
                CustomMinimumSize = new Vector2(150, 88),
                Disabled = !Progress.IsUnlocked(_save, id),
            };
            button.AddThemeFontSizeOverride("font_size", 22);
            button.Pressed += () => EmitSignal(SignalName.LevelChosen, chosen);
            _grid.AddChild(button);
        }
        _back.Pressed += () => EmitSignal(SignalName.Closed);
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("SELECT_TITLE");
        _back.Text = Tr("SELECT_BACK");
        for (int id = 1; id <= _grid.GetChildCount(); id++)
        {
            var button = _grid.GetChild<Button>(id - 1);
            int best = Progress.Best(_save, id);
            button.Text = TextFormat.Fill(Tr("SELECT_LEVEL"), id);
            if (best > 0)
                button.Text += "\n" + TextFormat.Fill(Tr("SELECT_BEST"), best);
        }
    }
}
