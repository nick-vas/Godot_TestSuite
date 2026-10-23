namespace Frostmote;

using Godot;

/// <summary>
/// The panel over a solved level: the moves against par, Next (Finish on the last level, none on a daily drift) and
/// Back to menu.
/// </summary>
public partial class SolvedMenu : CanvasLayer
{
    [Signal]
    public delegate void NextPressedEventHandler();

    [Signal]
    public delegate void MenuPressedEventHandler();

    private int _moves;
    private int _par;
    private string _nextKey = "SOLVED_NEXT";
    private Label _title = null!;
    private Label _movesLabel = null!;
    private Button _next = null!;
    private Button _menu = null!;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _movesLabel = GetNode<Label>("Box/MovesLabel");
        _next = GetNode<Button>("Box/NextButton");
        _menu = GetNode<Button>("Box/MenuButton");
        Visible = false;
        _next.Pressed += () => EmitSignal(SignalName.NextPressed);
        _menu.Pressed += () => EmitSignal(SignalName.MenuPressed);
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("SOLVED_TITLE");
        _movesLabel.Text = TextFormat.Fill(Tr("SOLVED_MOVES"), _moves, _par);
        _next.Text = _nextKey != "" ? Tr(_nextKey) : "";
        _menu.Text = Tr("SOLVED_MENU");
    }

    /// <summary>nextKey: the Next button's text key, or "" for no Next button.</summary>
    public void Open(int moves, int par, string nextKey)
    {
        _moves = moves;
        _par = par;
        _nextKey = nextKey;
        _next.Visible = nextKey != "";
        RefreshText();
        Visible = true;
    }

    public void Close()
    {
        Visible = false;
    }
}
