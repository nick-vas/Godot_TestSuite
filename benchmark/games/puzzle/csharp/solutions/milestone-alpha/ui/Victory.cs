namespace Frostmote;

using Godot;

/// <summary>The end of the last level: every level solved, and the moves of the best solutions added up.</summary>
public partial class Victory : Control
{
    [Signal]
    public delegate void MenuPressedEventHandler();

    private int _total;
    private Label _title = null!;
    private Label _message = null!;
    private Button _menu = null!;

    public void Setup(int totalMoves)
    {
        _total = totalMoves;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _message = GetNode<Label>("Box/MessageLabel");
        _menu = GetNode<Button>("Box/MenuButton");
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
        _title.Text = Tr("VICTORY_TITLE");
        _message.Text = TextFormat.Fill(Tr("VICTORY_MESSAGE"), _total);
        _menu.Text = Tr("VICTORY_MENU");
    }
}
